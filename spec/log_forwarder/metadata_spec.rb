require "spec_helper"
require_relative "../../lib/log_forwarder/metadata"

RSpec.describe LogForwarder::Metadata do
  around do |example|
    previous = ENV[described_class::ENV_VAR]
    example.run
    ENV[described_class::ENV_VAR] = previous
  end

  describe ".resolve" do
    it "resolves the staging route" do
      expect(described_class.resolve("makeshift-staging")).to eq(
        "makeshift_app" => "makeshift-staging",
        "makeshift_environment" => "staging"
      )
    end

    it "resolves the production route" do
      expect(described_class.resolve("makeshift-prod")).to eq(
        "makeshift_app" => "makeshift-prod",
        "makeshift_environment" => "production"
      )
    end

    it "resolves routes configured through the environment variable" do
      ENV[described_class::ENV_VAR] = "cipher-staging:staging, rpush-prod:production"

      expect(described_class.resolve("cipher-staging")).to eq(
        "makeshift_app" => "cipher-staging",
        "makeshift_environment" => "staging"
      )
      expect(described_class.resolve("rpush-prod")).to include(
        "makeshift_environment" => "production"
      )
    end

    it "returns nil for unknown routes" do
      expect(described_class.resolve("unknown-app")).to be_nil
    end

    it "returns nil for blank or missing sources" do
      expect(described_class.resolve(nil)).to be_nil
      expect(described_class.resolve("")).to be_nil
    end
  end

  describe ".enrich" do
    it "replaces any payload-supplied values for the contract attributes" do
      record = {
        "makeshift_app" => "attacker",
        "makeshift_environment" => "production",
        "logtype" => "heroku.runtime_metrics",
        "load_avg_1m" => 0.02
      }
      metadata = described_class.resolve("makeshift-staging")

      expect(described_class.enrich(record, metadata)).to eq(
        "makeshift_app" => "makeshift-staging",
        "makeshift_environment" => "staging",
        "logtype" => "heroku.runtime_metrics",
        "load_avg_1m" => 0.02
      )
    end
  end
end