module ProjectTools
  # Code-defined catalogue of project tools — the fork extension seam. Forks
  # register their own tools in config/initializers/project_tools.rb after
  # building them. Holds module-level state repopulated on each boot/reload via
  # the initializer's `to_prepare` (reset! keeps it idempotent).
  module Registry
    module_function

    def all
      @tools ||= []
    end

    def reset!
      @tools = []
    end

    def register(key:, path_helper: nil, default_enabled: true, implemented: true)
      if implemented && path_helper.blank?
        raise ArgumentError, "ProjectTools: implemented tool #{key.inspect} needs a path_helper"
      end

      tool = Tool.new(key: key.to_sym, default_enabled:, implemented:, path_helper:)
      all << tool
      tool
    end

    def find(key)
      all.find { |t| t.key == key.to_sym }
    end

    def implemented
      all.select(&:implemented?)
    end

    # Tools a user may flip on/off — only ones with a real surface.
    def toggleable
      implemented
    end

    # String keys (JSON-friendly) of the tools enabled by default on a new project.
    def default_keys
      implemented.select(&:default_enabled?).map { |t| t.key.to_s }
    end
  end
end
