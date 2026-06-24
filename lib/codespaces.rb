# frozen_string_literal: true

# GitHub Codespaces detection + forwarded-URL helpers. A browser Codespace
# reaches the app through an HTTPS proxy at
# <codespace-name>-<port>.<forwarding-domain> (not localhost), which dev config
# must allow past host authorization and target with mailer links. Pure
# functions over an env hash so they unit-test without a real Codespace.
# Required explicitly by config/environments/development.rb — environment config
# runs before Zeitwerk autoloading, same as lib/markdowndocs_local_categories.rb.
module Codespaces
  # The platform sets CODESPACES=true only inside a Codespace.
  def self.active?(env = ENV)
    env["CODESPACES"] == "true"
  end

  # The port-forwarding domain the platform injects, e.g. "app.github.dev".
  def self.forwarding_domain(env = ENV)
    env["GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"]
  end

  # The forwarded host for a given app port, e.g.
  # "musical-space-abc123-3000.app.github.dev" — no scheme, no trailing slash.
  def self.forwarded_host(port:, env: ENV)
    "#{env["CODESPACE_NAME"]}-#{port}.#{forwarding_domain(env)}"
  end
end
