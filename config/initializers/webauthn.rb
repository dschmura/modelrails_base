# Passkeys (WebAuthn) relying-party configuration.
#
# RP ID / origin MUST match window.location.origin in the browser. Derived from
# the app host (the same value mailers use) — including the port, since the
# browser origin carries it (e.g. http://localhost:3000) — overridable per
# environment via WEBAUTHN_ORIGIN, the classic forker footgun, so it's a single
# explicit seam. See app/docs/developer/passkeys.md.
module Passkeys
  def self.origin
    ENV.fetch("WEBAUTHN_ORIGIN") do
      opts   = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
      host   = opts[:host] || "localhost"
      port   = opts[:port]
      scheme = host.start_with?("localhost", "127.0.0.1") ? "http" : "https"
      host   = "#{host}:#{port}" if port.present? && [ 80, 443 ].exclude?(port.to_i)
      "#{scheme}://#{host}"
    end
  end

  def self.rp_id
    ENV.fetch("WEBAUTHN_RP_ID") { URI(origin).host }
  end
end

Rails.application.config.after_initialize do
  WebAuthn.configure do |config|
    config.allowed_origins = [ Passkeys.origin ]
    config.rp_name = I18n.t("application.name")
    config.rp_id = Passkeys.rp_id
  end
end
