# frozen_string_literal: true

require "rails_helper"
require "codespaces"

RSpec.describe Codespaces do
  describe ".active?" do
    it "is true only when CODESPACES is exactly \"true\"" do
      expect(described_class.active?({ "CODESPACES" => "true" })).to be(true)
    end

    it "is false when CODESPACES is absent" do
      expect(described_class.active?({})).to be(false)
    end

    it "is false when CODESPACES holds any other value" do
      expect(described_class.active?({ "CODESPACES" => "false" })).to be(false)
      expect(described_class.active?({ "CODESPACES" => "1" })).to be(false)
    end
  end

  describe ".forwarding_domain" do
    it "returns the injected port-forwarding domain" do
      env = { "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev" }
      expect(described_class.forwarding_domain(env)).to eq("app.github.dev")
    end

    it "returns nil when the domain is unset" do
      expect(described_class.forwarding_domain({})).to be_nil
    end
  end

  describe ".forwarded_host" do
    it "builds <name>-<port>.<domain> with no scheme or trailing slash" do
      env = {
        "CODESPACE_NAME" => "musical-space-abc123",
        "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev"
      }
      expect(described_class.forwarded_host(port: 3000, env: env))
        .to eq("musical-space-abc123-3000.app.github.dev")
    end

    it "reflects the port argument" do
      env = {
        "CODESPACE_NAME" => "cs",
        "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev"
      }
      expect(described_class.forwarded_host(port: 1080, env: env))
        .to eq("cs-1080.app.github.dev")
    end
  end
end
