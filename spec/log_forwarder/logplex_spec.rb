require "spec_helper"
require_relative "../../lib/log_forwarder/logplex"

RSpec.describe LogForwarder::Logplex do
  describe ".frames" do
    it "extracts octet-counted frames from a Logplex batch" do
      first = "<40>1 2026-10-05T16:44:15+00:00 host heroku web.1 - first"
      second = "<40>1 2026-10-05T16:44:16+00:00 host heroku web.1 - second"
      payload = "#{first.bytesize} #{first}\n#{second.bytesize} #{second}"

      expect(described_class.frames(payload)).to eq([first, second])
    end

    it "rejects malformed frame lengths" do
      expect { described_class.frames("nope message") }
        .to raise_error(LogForwarder::Logplex::InvalidFrame, "invalid Logplex frame length")
    end

    it "rejects truncated frames" do
      expect { described_class.frames("10 short") }
        .to raise_error(LogForwarder::Logplex::InvalidFrame, "truncated Logplex frame")
    end
  end

  describe ".message" do
    it "extracts the message from Heroku's syslog envelope" do
      frame = "<40>1 2026-10-05T16:44:15+00:00 host heroku sidekiq.1 - hello"

      expect(described_class.message(frame)).to eq("hello")
    end

    it "returns nil for invalid syslog data" do
      expect(described_class.message("not syslog")).to be_nil
    end
  end

  describe ".parse" do
    it "decomposes a syslog frame into its parts" do
      frame = "<40>1 2026-10-08T13:41:00.443714+00:00 host heroku sidekiq.1 - " \
              "source=sidekiq.1 dyno=heroku.x sample#load_avg_1m=0.00"

      expect(described_class.parse(frame)).to eq(
        "timestamp" => "2026-10-08T13:41:00.443714+00:00",
        "host" => "host",
        "app" => "heroku",
        "procid" => "sidekiq.1",
        "message" => "source=sidekiq.1 dyno=heroku.x sample#load_avg_1m=0.00"
      )
    end

    it "decomposes frames from non-Heroku apps" do
      frame = "<40>1 2026-10-08T13:41:00+00:00 host app web.1 - app[web.1]: boot log"

      expect(described_class.parse(frame)).to include(
        "app" => "app",
        "procid" => "web.1",
        "message" => "app[web.1]: boot log"
      )
    end

    it "returns nil for invalid syslog data" do
      expect(described_class.parse("not syslog")).to be_nil
    end
  end
end