# frozen_string_literal: true

require "yaml"

# The names bin/release reads from an optional .release_flow.yml; each defaults to this repository's.
module ReleaseFlow
  class Error < StandardError; end

  FILE = ".release_flow.yml"
  DEFAULTS = { integration_branch: "next", production_branch: "main", ci_workflow: "ci.yml",
               staging_workflow: "deploy.yml", guide: "/docs/developer/releasing", template: nil }.freeze

  Config = Data.define(*DEFAULTS.keys) do
    def self.load(root)
      path = File.join(root, FILE)
      settings = File.exist?(path) ? YAML.safe_load_file(path).to_h.transform_keys(&:to_sym) : {}
      unknown = settings.keys - members
      raise Error, "#{FILE} has no setting #{unknown.join(', ')}; it takes #{members.join(', ')}" if unknown.any?

      new(**DEFAULTS, **settings)
    end
  end
end
