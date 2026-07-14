# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :blob, "https://www.gravatar.com"
    policy.object_src  :none
    policy.script_src  :self, "https://cdn.jsdelivr.net"
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self
    policy.frame_src   :none
    policy.base_uri    :self
    # OAuth providers need form-action allowance because CSP evaluates the
    # entire redirect chain. POST to /auth/:provider returns a 302 to the
    # provider's consent page, and browsers block that step unless the
    # provider host is in form-action.
    policy.form_action :self,
      "https://accounts.google.com",
      "https://github.com"
  end

  # Generate session nonces for permitted importmap and inline scripts. A
  # visitor's FIRST request has no session yet, so request.session.id is nil
  # there — falling back to a random nonce avoids emitting the invalid
  # `script-src ... 'nonce-'` (blank) that browsers ignore, which blocks
  # every inline script (the importmap bootstrap + `import "application"`),
  # leaving Stimulus never booting for first-time visitors.
  config.content_security_policy_nonce_generator = lambda do |request|
    request.session.id&.to_s.presence || SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src]

  # Enforcement mode is NOT set here. Rails defaults to enforced (false)
  # everywhere; config/environments/test.rb explicitly enforces it in test
  # too (PR #120) so CSP bugs fail the suite instead of shipping silently.
  # Do not reintroduce a Rails.env.test? override here — an earlier version
  # of this line did exactly that, loaded after test.rb in Rails' boot order,
  # and silently undid PR #120's fix for the lifetime of this bug.
end
