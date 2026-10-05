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
end
