require "rails_helper"

# ProjectTools::Tool#name and #description read dynamic keys
# (`project_tools.<key>.name`), which the static i18n gate cannot see, and they
# used to carry inline defaults, which the runtime gate cannot see through. Both
# gates are blind here, so this spec is the gate: every registered tool has both
# keys. A fork registering a tool without them gets a red test, not a humanized
# key or an empty description in the tab bar.
RSpec.describe "Code smell: every registered project tool has its locale keys" do
  def missing_keys_for(tools)
    tools.flat_map do |tool|
      %w[name description].reject { |leaf| I18n.exists?("project_tools.#{tool.key}.#{leaf}") }
                          .map { |leaf| "project_tools.#{tool.key}.#{leaf}" }
    end
  end

  it "finds a name and a description for every tool in the registry" do
    missing = missing_keys_for(ProjectTools::Registry.all)

    expect(missing).to be_empty,
      "Registered project tools without locale keys:\n  #{missing.join("\n  ")}\n" \
      "Add them under project_tools.<key> in config/locales/en/project_tools.en.yml."
  end

  # The check must be able to fail: a tool nobody wrote keys for is reported.
  it "reports a tool without keys" do
    tool = ProjectTools::Tool.new(key: :zz_unkeyed, default_enabled: false, implemented: false, path_helper: nil)

    expect(missing_keys_for([ tool ])).to contain_exactly(
      "project_tools.zz_unkeyed.name", "project_tools.zz_unkeyed.description"
    )
  end
end
