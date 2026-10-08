require "spec_helper"
require_relative "../app"
require "time"

RSpec.describe LogForwarderApp do
  let(:logger) { instance_double(Fluent::Logger::FluentLogger, post: true) }

  def app
    described_class.set :fluent_logger, logger
    described_class
  end

  def logplex_batch(frame)
    "#{frame.bytesize} #{frame}"
  end

  describe "GET /healthz" do
    it "returns OK" do
      get "/healthz"

      expect(last_response).to be_ok
      expect(last_response.body).to eq("OK")
    end
  end

  describe "POST /newrelic/:source" do
    let(:frame) do
      "<40>1 2026-10-08T13:41:00.443714+00:00 host heroku sidekiq.1 - " \
        "source=sidekiq.1 dyno=heroku.x sample#load_avg_1m=0.00 sample#memory_total=459.95MB"
    end

    it "forwards wire-format runtime metrics with source attribution" do
      post "/newrelic/makeshift-staging", logplex_batch(frame),
           "CONTENT_TYPE" => "application/logplex-1"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-length"]).to eq("0")
      expect(last_response.body).to be_empty
      expect(logger).to have_received(:post).with(
        "heroku.runtime_metrics",
        hash_including(
          "timestamp" => 1_791_466_860_443,
          "source" => "makeshift-staging",
          "dyno_source" => "sidekiq.1",
          "logtype" => "heroku.runtime_metrics",
          "load_avg_1m" => 0.0,
          "memory_total_mb" => 460
        )
      )
    end

    it "forwards the committed fixture as-is" do
      post "/newrelic/local-test", File.read(File.expand_path("../fixtures/sample.log", __dir__)),
           "CONTENT_TYPE" => "application/logplex-1"

      expect(last_response).to be_ok
      expect(logger).to have_received(:post).with(
        "heroku.runtime_metrics",
        hash_including("source" => "local-test", "dyno_source" => "sidekiq.1", "load_avg_1m" => 0.0)
      )
    end

    it "forwards frames carried with Heroku's newline-inclusive octet count" do
      wire_frame = "<134>1 2026-10-08T14:37:27.905855+00:00 host heroku web.1 - " \
        "source=web.1 dyno=heroku.16814144.06d61a51-dd23-4a64-8df7-0dba4557951f sample#load_avg_1m=0.02"
      payload = "#{(wire_frame + "\n").bytesize} #{wire_frame}\n"

      post "/newrelic/makeshift-staging", payload, "CONTENT_TYPE" => "application/logplex-1"

      expect(last_response).to be_ok
      expect(logger).to have_received(:post).with(
        "heroku.runtime_metrics",
        hash_including("dyno_source" => "web.1", "timestamp" => 1_791_470_247_905, "load_avg_1m" => 0.02)
      )
    end

    it "ignores non-runtime-metrics frames" do
      message_frame = "<40>1 2026-10-08T13:41:00+00:00 host app web.1 - app[web.1]: boot log"

      post "/newrelic/makeshift-staging", logplex_batch(message_frame)

      expect(last_response).to be_ok
      expect(logger).not_to have_received(:post)
    end

    it "ignores heroku frames without sample pairs" do
      message_frame = "<40>1 2026-10-08T13:41:00+00:00 host heroku web.1 - State changed from up to down"

      post "/newrelic/makeshift-staging", logplex_batch(message_frame)

      expect(last_response).to be_ok
      expect(logger).not_to have_received(:post)
    end

    it "rejects malformed Logplex framing" do
      post "/newrelic/makeshift-staging", "not-a-frame",
           "CONTENT_TYPE" => "application/logplex-1"

      expect(last_response.status).to eq(400)
      expect(logger).not_to have_received(:post)
    end
  end
end