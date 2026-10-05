require "spec_helper"
require_relative "../app"

RSpec.describe LogForwarderApp do
  let(:logger) { instance_double(Fluent::Logger::FluentLogger, post: true) }

  def app
    described_class.set :fluent_logger, logger
    described_class
  end

  def logplex_batch(message)
    "#{message.bytesize} #{message}"
  end

  describe "GET /healthz" do
    it "returns OK" do
      get "/healthz"

      expect(last_response).to be_ok
      expect(last_response.body).to eq("OK")
    end
  end

  describe "POST /newrelic/:source" do
    let(:line) do
      "2026-10-05T16:44:15.708424+00:00 heroku[sidekiq.1]: " \
        "source=sidekiq.1 dyno=heroku.x sample#load_avg_1m=0.00 " \
        "sample#memory_total=459.95MB"
    end
    let(:frame) { "<40>1 2026-10-05T16:44:15+00:00 host heroku sidekiq.1 - #{line}" }

    it "forwards parsed metrics with source attribution" do
      post "/newrelic/makeshift-staging", logplex_batch(frame),
           "CONTENT_TYPE" => "application/logplex-1"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-length"]).to eq("0")
      expect(last_response.body).to be_empty
      expect(logger).to have_received(:post).with(
        "heroku.runtime_metrics",
        hash_including(
          "source" => "makeshift-staging",
          "dyno_source" => "sidekiq.1",
          "logtype" => "heroku.runtime_metrics",
          "load_avg_1m" => 0.0,
          "memory_total_mb" => 460
        )
      )
    end

    it "ignores non-runtime-metrics frames" do
      message = "<40>1 2026-10-05T16:44:15+00:00 host app web.1 - app[web.1]: boot log"

      post "/newrelic/makeshift-staging", logplex_batch(message)

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
