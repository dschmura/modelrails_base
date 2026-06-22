# frozen_string_literal: true

# Virtual WebAuthn authenticator via Playwright CDP.
#
# Wraps `WebAuthn.enable` + `WebAuthn.addVirtualAuthenticator` in a helper
# block so any system spec can drive real navigator.credentials.create /
# navigator.credentials.get without user interaction (automaticPresenceSimulation
# auto-approves every credential gesture).
#
# CDP access pattern: `playwright_page.context.new_cdp_session(playwright_page)`
# returns a `Playwright::CDPSession`; messages are sent via `cdp.send_message`.
#
# Origin alignment: WebAuthn's RP `allowed_origins` (from the initializer) is
# `http://localhost` (derived from the test mailer host). Capybara binds its
# server to `127.0.0.1:<dynamic_port>` and Playwright navigates to that host.
# `127.0.0.1` and `localhost` are treated as different origins in WebAuthn,
# so we temporarily set `Capybara.app_host` to force Playwright to use
# `http://localhost:<port>`, which matches the configured RP origin. We also
# ensure `allowed_origins` includes that exact URL.
#
# Usage in a system spec:
#   with_virtual_authenticator do
#     sign_in_via_form(user)
#     visit settings_passkeys_path
#     # ... navigate + click Add a passkey ...
#   end
module WebauthnVirtualAuthenticator
  # Enable the CDP virtual authenticator for the duration of the block.
  # The authenticator is ctap2/internal with resident-key + user-verification;
  # `automaticPresenceSimulation: true` means every create/get call is
  # auto-approved without a real user gesture.
  def with_virtual_authenticator
    # Force Playwright to navigate to http://localhost:<port> so the browser
    # origin matches WebAuthn's RP origin. Capybara.server_port is set once
    # the server starts; access it via the current session's server object.
    server = Capybara.current_session.server
    original_app_host = Capybara.app_host
    localhost_origin = "http://localhost:#{server.port}"
    Capybara.app_host = localhost_origin

    # Temporarily extend allowed_origins to include the localhost URL.
    # (The initializer sets http://localhost without a port — with a port we
    # need the full URL so the webauthn gem's origin check passes.)
    original_origins = WebAuthn.configuration.allowed_origins.dup
    WebAuthn.configuration.allowed_origins = [ localhost_origin ]

    # Enable the CDP virtual authenticator on the Playwright page.
    Capybara.current_session.driver.with_playwright_page do |playwright_page|
      cdp = playwright_page.context.new_cdp_session(playwright_page)
      cdp.send_message("WebAuthn.enable", params: { enableUI: false })
      cdp.send_message("WebAuthn.addVirtualAuthenticator", params: {
        options: {
          protocol:                    "ctap2",
          transport:                   "internal",
          hasResidentKey:              true,
          hasUserVerification:         true,
          isUserVerified:              true,
          automaticPresenceSimulation: true
        }
      })
    end

    yield
  ensure
    # Restore Capybara app_host and WebAuthn allowed_origins.
    Capybara.app_host = original_app_host
    WebAuthn.configuration.allowed_origins = original_origins if original_origins

    # Clean up: disable the virtual authenticator environment so it doesn't
    # bleed into subsequent specs sharing the same browser page.
    begin
      Capybara.current_session.driver.with_playwright_page do |playwright_page|
        cdp = playwright_page.context.new_cdp_session(playwright_page)
        cdp.send_message("WebAuthn.disable")
      end
    rescue StandardError
      # Ignore cleanup errors — the page may already be reset.
    end
  end
end

RSpec.configure do |config|
  config.include WebauthnVirtualAuthenticator, type: :system
end
