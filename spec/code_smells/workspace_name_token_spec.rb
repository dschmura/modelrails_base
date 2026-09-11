require "rails_helper"

# The interpolation that carries a workspace's NAME is `%{workspace_name}`,
# never `%{workspace}`. The short spelling is a homonym of the domain noun:
# it read two ways in the same file, and it is the one token a vocabulary
# seam could silently fill when a caller forgets the argument (#1108).
RSpec.describe "Code smell: the workspace-name interpolation is spelled workspace_name" do
  it "uses %{workspace_name} in every locale value that carries the name" do
    offenders = Dir.glob(Rails.root.join("config/locales/**/*.yml")).flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{Pathname.new(path).relative_path_from(Rails.root)}:#{index + 1}" if line.include?("%{workspace}")
      end
    end

    expect(offenders).to be_empty,
      "Locale values still spell the workspace's name %{workspace}; use %{workspace_name}:\n  #{offenders.join("\n  ")}"
  end
end
