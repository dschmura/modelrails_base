require "rails_helper"

RSpec.describe "WebAuthn configuration" do
  it "pins allowed_origins to the app host so a misconfig fails loudly" do
    expect(WebAuthn.configuration.allowed_origins).to be_present
  end

  it "exposes the rp_id via Passkeys.rp_id" do
    expect(Passkeys.rp_id).to be_present
  end

  it "sets a relying-party name" do
    expect(WebAuthn.configuration.rp_name).to eq(I18n.t("application.name"))
  end

  describe "Passkeys.origin derivation" do
    around do |example|
      original = ENV["WEBAUTHN_ORIGIN"]
      ENV.delete("WEBAUTHN_ORIGIN")
      begin
        example.run
      ensure
        original.nil? ? ENV.delete("WEBAUTHN_ORIGIN") : (ENV["WEBAUTHN_ORIGIN"] = original)
      end
    end

    def with_mailer_host(opts)
      allow(Rails.application.config.action_mailer)
        .to receive(:default_url_options).and_return(opts)
      yield
    end

    it "includes the port so it matches the browser origin (the localhost:3000 dev case)" do
      with_mailer_host(host: "localhost", port: 3000) do
        expect(Passkeys.origin).to eq("http://localhost:3000")
      end
    end

    it "uses https and no port for a bare production host" do
      with_mailer_host(host: "example.com") do
        expect(Passkeys.origin).to eq("https://example.com")
      end
    end

    it "appends a non-standard port" do
      with_mailer_host(host: "example.com", port: 8080) do
        expect(Passkeys.origin).to eq("https://example.com:8080")
      end
    end

    it "omits the standard https port 443" do
      with_mailer_host(host: "example.com", port: 443) do
        expect(Passkeys.origin).to eq("https://example.com")
      end
    end

    it "prefers the WEBAUTHN_ORIGIN override" do
      ENV["WEBAUTHN_ORIGIN"] = "https://custom.example"
      with_mailer_host(host: "localhost", port: 3000) do
        expect(Passkeys.origin).to eq("https://custom.example")
      end
    end
  end
end
