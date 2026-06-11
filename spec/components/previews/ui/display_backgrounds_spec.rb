# frozen_string_literal: true

require "rails_helper"

# Per-preview `@display background <value>` tags drive the preview-layout body background
# (raised default · sunken · surface · bleed). Guard the vocabulary and require the
# two tagged families to exist (raised containers + page chrome).
RSpec.describe "Lookbook display backgrounds" do
  preview_root = Rails.root.join("spec/components/previews/ui")
  layout = Rails.root.join("app/views/layouts/component_preview.html.erb")
  allowed = %w[sunken surface bleed]

  tags = Dir.glob(preview_root.join("*_component_preview.rb")).each_with_object({}) do |path, acc|
    value = File.read(path)[/^\s*#\s*@display background\s+(\S+)/, 1]
    acc[File.basename(path, "_component_preview.rb")] = value if value
  end

  it "uses only vocabulary values" do
    bad = tags.reject { |_c, v| allowed.include?(v) }
    expect(bad).to be_empty, "unknown @display background values: #{bad.inspect} (allowed: #{allowed.join(", ")})"
  end

  it "tags the raised-container and page-chrome families" do
    expect(tags).not_to be_empty
    expect(tags.keys).to include("card", "navbar")
  end

  it "the preview layout consumes the background param" do
    expect(File.read(layout)).to match(/lookbook.*display.*background/m)
  end
end
