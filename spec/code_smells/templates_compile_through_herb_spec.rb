# frozen_string_literal: true

require "rails_helper"
require "action_view/herb_checker"
require "tmpdir"

# Rails 8.2 compiles HTML+ERB through Herb; this runs `bin/rails herb:check`'s checker on every PR,
# so a mismatched tag or unsafe ERB output fails here instead of in a browser.
RSpec.describe "Code smell: templates compile through Herb" do
  let(:view_paths) { ActionController::Base.view_paths.select { |resolver| resolver.respond_to?(:all_unbound_templates) } }
  # Under app/, not Rails.root: CI bundles gems into vendor/bundle inside the repo.
  let(:app_paths) { view_paths.select { |resolver| resolver.path.to_s.start_with?("#{Rails.root.join('app')}/") } }
  let(:app_templates_written_against) { 185 }

  # A gem's template that fails, with the issue tracking it upstream; an entry that starts compiling fails below.
  let(:known_gem_failures) { { "biscuit-rails" => "biscuit/banner/_banner.html.erb (#1341, garethfr/biscuit-rails#5)" } }

  def html_erb_templates(resolvers)
    resolvers.flat_map(&:all_unbound_templates).select { |template| template.format == :html && template.handler == :erb }
  end

  def failures(resolvers)
    ActionView::HerbChecker.check(resolvers).map do |failure|
      "#{failure.template.short_identifier}: #{failure.error.message.lines.first.strip}"
    end
  end

  def gem_name(identifier) = identifier[%r{/gems/([a-z_-]+)-\d}, 1]

  it "reads every app template (floor)" do
    expect(html_erb_templates(app_paths).size).to be >= app_templates_written_against
  end

  it "compiles every app template" do
    expect(failures(app_paths)).to be_empty
  end

  it "compiles every gem template except the reviewed failures, and each of those still fails" do
    failing_gems = failures(view_paths - app_paths).map { |failure| gem_name(failure) }

    expect(failing_gems - known_gem_failures.keys).to be_empty
    expect(known_gem_failures.keys - failing_gems).to be_empty, "these gems' templates compile now; remove them from known_gem_failures"
  end

  it "catches a mismatched tag, an unclosed element and ERB output in attribute position (positive control)" do
    planted = {
      "mismatched" => "<div><p>hi</div>",
      "unclosed" => "<section><p>hi</p>",
      "attribute_position" => %(<div <%= "class=x" %>>hi</div>),
      "well_formed" => "<div><p>hi</p></div>"
    }

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "planted"))
      planted.each { |name, source| File.write(File.join(dir, "planted", "_#{name}.html.erb"), source) }

      caught = failures([ ActionView::FileSystemResolver.new(dir) ]).map { |failure| failure[%r{planted/_(\w+)}, 1] }
      expect(caught).to contain_exactly("mismatched", "unclosed", "attribute_position")
    end
  end
end
