require "spec_helper"
require_relative "../../lib/log_forwarder/runtime_metrics"

RSpec.describe LogForwarder::RuntimeMetrics do
  describe ".parse" do
    let(:line) do
      "2026-10-05T16:44:15.708424+00:00 heroku[sidekiq.1]: " \
        "source=sidekiq.1 dyno=heroku.x sample#load_avg_1m=0.00 " \
        "sample#memory_total=459.95MB sample#memory_rss=1024kB " \
        "sample#running=3pages"
    end

    it "returns dashboard attributes and parsed numeric metrics" do
      expect(described_class.parse("makeshift-staging", line)).to eq(
        "timestamp" => "2026-10-05T16:44:15.708424+00:00",
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
      %w[web.1 sidekiq.1 sidekiq_integrations.1 rpush.1].each do |dyno|
        input = line.sub("sidekiq.1", dyno)

        expect(described_class.parse("makeshift-staging", input)).to include("dyno_source" => dyno)
      end
    end

    it "returns nil for non-runtime-metrics lines" do
      expect(described_class.parse("makeshift-staging", "app[web.1]: boot log")).to be_nil
    end
  end
end
