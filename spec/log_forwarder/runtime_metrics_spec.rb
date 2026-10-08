require "spec_helper"
require_relative "../../lib/log_forwarder/runtime_metrics"

RSpec.describe LogForwarder::RuntimeMetrics do
  describe ".parse" do
    let(:message) do
      "source=sidekiq.1 dyno=heroku.x sample#load_avg_1m=0.00 " \
        "sample#memory_total=459.95MB sample#memory_rss=1024kB " \
        "sample#running=3pages"
    end

    it "parses a wire-format drain message" do
      expect(
        described_class.parse("makeshift-staging", "sidekiq.1", "2026-10-08T13:41:00.443714+00:00", message)
      ).to eq(
        "timestamp" => 1_791_466_860_443,
        "source" => "makeshift-staging",
        "dyno_source" => "sidekiq.1",
        "logtype" => "heroku.runtime_metrics",
        "load_avg_1m" => 0.0,
        "memory_total_mb" => 460,
        "memory_rss_kb" => 1024.0,
        "running_pages" => 3.0
      )
    end

    it "accepts each supported dyno name" do
      %w[web.1 sidekiq.1 sidekiq_integrations.1 rpush.1].each do |procid|
        per_dyno_message = message.sub("source=sidekiq.1", "source=#{procid}")
        record = described_class.parse("makeshift-staging", procid, "2026-10-08T13:41:00.443714+00:00", per_dyno_message)

        expect(record).to include("dyno_source" => procid)
      end
    end

    it "parses a rendered CLI line as a compat case" do
      rendered = "2026-10-05T16:44:15.708424+00:00 heroku[sidekiq.1]: sample#load_avg_1m=0.00"

      expect(
        described_class.parse("makeshift-staging", nil, nil, rendered)
      ).to include(
        "timestamp" => 1_791_218_655_708,
        "dyno_source" => "sidekiq.1",
        "load_avg_1m" => 0.0
      )
    end

    it "returns nil for non-runtime-metrics messages" do
      expect(
        described_class.parse("makeshift-staging", "web.1", "2026-10-08T13:41:00+00:00", "app[web.1]: boot log")
      ).to be_nil
    end

    it "omits timestamp when it cannot be converted" do
      record = described_class.parse("makeshift-staging", "web.1", "not-a-time", message)

      expect(record).to include("dyno_source" => "sidekiq.1")
      expect(record).not_to include("timestamp")
    end

    it "omits timestamp when none is provided" do
      record = described_class.parse("makeshift-staging", "web.1", nil, message)

      expect(record).not_to include("timestamp")
    end

    it "drops dyno when procid is the syslog nilvalue" do
      record = described_class.parse("makeshift-staging", "-", "2026-10-08T13:41:00+00:00", message)

      expect(record).to include("dyno_source" => "sidekiq.1")
    end
  end

  describe "wire-frame attribution" do
    it "prefers the message source token over the procid" do
      message = "source=web.1 dyno=heroku.16814144.06d61a51-dd23-4a64-8df7-0dba4557951f sample#load_avg_1m=0.02"

      record = described_class.parse("makeshift-staging", nil, "2026-10-08T14:37:27.905855+00:00", message)

      expect(record).to include("dyno_source" => "web.1")
    end

    it "falls back to the procid when the message carries no source token" do
      record = described_class.parse("makeshift-staging", "web.1", "2026-10-08T13:41:00+00:00", "sample#load_avg_1m=0.02")

      expect(record).to include("dyno_source" => "web.1")
    end

    it "attributes addon metric frames to the addon source" do
      message = "source=HEROKU_REDIS_MAUVE addon=redis-trapezoidal-46536 " \
        "sample#active-connections=20 sample#max-connections=78"

      record = described_class.parse("makeshift-staging", "heroku-redis", "2026-10-08T14:36:54+00:00", message)

      expect(record).to include("dyno_source" => "HEROKU_REDIS_MAUVE", "active_connections" => 20)
    end
  end

  describe "logtype split" do
    it "tags dyno frames with the runtime-metrics logtype" do
      record = described_class.parse(
        "makeshift-staging",
        "web.1",
        "2026-10-08T14:37:27.905855+00:00",
        "source=web.1 dyno=heroku.16814144.06d61a51-dd23-4a64-8df7-0dba4557951f sample#load_avg_1m=0.02"
      )

      expect(record).to include("logtype" => "heroku.runtime_metrics")
    end

    it "tags addon frames without a dyno with the addon-metrics logtype" do
      message = "source=HEROKU_POSTGRESQL_COBALT addon=postgresql-transparent-31333 " \
        "sample#active-connections=27 sample#max-connections=200 " \
        "sample#db-size-percentage-used=0.08015 sample#memory-percentage-used=0.97971"

      record = described_class.parse("makeshift-staging", nil, "2026-10-08T14:36:54+00:00", message)

      expect(record).to include("logtype" => "heroku.addon_metrics")
      expect(record).to include(
        "dyno_source" => "HEROKU_POSTGRESQL_COBALT",
        "db_size_percentage_used" => 0.08015,
        "memory_percentage_used" => 0.97971
      )
    end

    it "keeps the rendered CLI compat path on the runtime-metrics logtype" do
      rendered = "2026-10-05T16:44:15.708424+00:00 heroku[sidekiq.1]: sample#load_avg_1m=0.00"

      record = described_class.parse("makeshift-staging", nil, nil, rendered)

      expect(record).to include("logtype" => "heroku.runtime_metrics", "dyno_source" => "sidekiq.1")
    end
  end

  describe "metric key normalization" do
    it "unifies the postgres plural connections-percentage key to the singular" do
      postgres = "source=HEROKU_POSTGRESQL_COBALT addon=postgresql-transparent-31333 " \
        "sample#connections-percentage-used=0.13"

      record = described_class.parse("makeshift-staging", nil, "2026-10-08T14:36:54+00:00", postgres)

      expect(record).to include("connection_percentage_used" => 0.13)
      expect(record).not_to include("connections_percentage_used")
    end
  end
end