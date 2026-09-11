require "rails_helper"

# In the template the vocabulary tokens resolve to the same words, so a spec
# asserting "Create a workspace" stays green here — and goes red in every fork
# that renamed. Assert copy through I18n.t so the same spec passes in both.
# Model names (Workspace, workspace.name, :workspace factories) are not copy.
RSpec.describe "Code smell: spec copy assertions go through I18n.t" do
  matcher = /\b(have_content|have_text|have_button|have_link|have_title|have_field|click_(?:link|button|on)|fill_in)\(\s*(["'])((?:(?!\2).)*)\2/
  noun = /\b(workspace|project)s?\b/i

  def offenders_in(path, matcher, noun)
    File.readlines(path).each_with_index.filter_map do |line, index|
      m = line.match(matcher) or next
      "#{path.relative_path_from(Rails.root)}:#{index + 1}  #{m[0][0, 70]}" if m[3].match?(noun)
    end
  end

  it "never asserts the bare noun in a text matcher" do
    offenders = Dir.glob(Rails.root.join("spec/**/*_spec.rb"))
      .map { |f| Pathname.new(f) }
      .reject { |p| p.to_s == __FILE__ }
      .flat_map { |p| offenders_in(p, matcher, noun) }

    expect(offenders).to be_empty,
      "Text matchers with the literal noun — assert I18n.t(\"…\") so a renamed fork stays green:\n  #{offenders.join("\n  ")}"
  end

  it "reports a planted literal and ignores a model reference" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe_spec.rb")
      path.write(%(expect(page).to have_content("Create a workspace")\nexpect(page).to have_content(workspace.name)\n))

      expect(offenders_in(path, matcher, noun).size).to eq(1)
    end
  end
end
