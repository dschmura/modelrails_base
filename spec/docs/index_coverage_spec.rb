require "rails_helper"

# Guards the docs *journey*, not just the docs. Every file in app/docs/ must be
# reachable from the /docs index — i.e. assigned to a category in
# config/initializers/markdowndocs.rb. An uncategorized doc still renders by
# direct URL but is invisible to a newcomer browsing the index, which is how
# the most important doc (presets) silently went missing. This guard fails CI
# the moment a new doc is added without a home.
RSpec.describe "Documentation index coverage" do
  let(:doc_slugs) do
    base = Rails.root.join("app/docs")
    Dir[base.join("**/*.md")].map { |f| Pathname(f).relative_path_from(base).to_s.delete_suffix(".md") }
  end
  let(:categorized) { Markdowndocs.configuration.categories.values.flatten }

  it "assigns every app/docs file to a category (no orphans hidden from the index)" do
    orphans = doc_slugs - categorized
    expect(orphans).to be_empty,
      "Uncategorized docs (add to config/initializers/markdowndocs.rb): #{orphans.sort.join(', ')}"
  end

  it "references no category slug that lacks a backing file (catches renames/typos)" do
    stale = categorized - doc_slugs
    expect(stale).to be_empty,
      "Categorized slugs with no app/docs/*.md file: #{stale.sort.join(', ')}"
  end
end
