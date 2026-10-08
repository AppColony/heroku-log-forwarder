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
        record = described_class.parse("makeshift-staging", procid, "2026-10-08T13:41:00.443714+00:00", message)

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

      expect(record).to include("dyno_source" => "web.1")
      expect(record).not_to include("timestamp")
    end

    it "omits timestamp when none is provided" do
      record = described_class.parse("makeshift-staging", "web.1", nil, message)

      expect(record).not_to include("timestamp")
    end

    it "drops dyno when procid is the syslog nilvalue" do
      record = described_class.parse("makeshift-staging", "-", "2026-10-08T13:41:00+00:00", message)

      expect(record).to include("dyno_source" => nil)
    end
  end
end