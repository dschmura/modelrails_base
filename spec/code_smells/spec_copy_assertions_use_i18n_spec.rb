require "rails_helper"

# In the template the vocabulary tokens resolve to the same words, so a spec
# asserting "Create a workspace" stays green here — and goes red in every fork
# that renamed. Assert copy through I18n.t so the same spec passes in both.
# Model names (Workspace, workspace.name, :workspace factories) are not copy.
RSpec.describe "Code smell: spec copy assertions go through I18n.t" do
  matcher = /\b(have_content|have_text|have_button|have_link|have_title|have_field|click_(?:link|button|on)|fill_in)(?:\(\s*|\s+)(["'])((?:(?!\2).)*)\2/
  text_option = /\btext:\s*(["'])((?:(?!\1).)*)\1/
  noun = /\b(workspace|project)s?\b/i

  # Fixture/preview text with no locale key behind it — a Lookbook preview's
  # sample copy or a generic partial spec's arbitrary local. Not app copy, so
  # there is no key to convert to; converting anyway would either invent a
  # fake key or desync the assertion from what's actually rendered. Keep this
  # list a decision, not a fossil.
  allowed = {
    "spec/system/ui/card_component_spec.rb:42" => "preview fixture text, not app copy",
    "spec/system/ui/card_component_spec.rb:43" => "preview fixture text, not app copy",
    "spec/system/ui/dialog_component_spec.rb:60" => "preview fixture text, not app copy",
    "spec/system/ui/timeline_component_spec.rb:34" => "preview fixture text, not app copy",
    "spec/views/shared/section_nav_strip_spec.rb:13" => "arbitrary local passed to a generic partial spec, not app copy"
  }

  def offenders_in(path, matcher, text_option, noun, allowed = {})
    File.readlines(path).each_with_index.filter_map do |line, index|
      location = "#{path.relative_path_from(Rails.root)}:#{index + 1}"
      next if allowed[location]
      # Check for paren/paren-less matcher calls
      m = line.match(matcher)
      if m && m[3].match?(noun)
        "#{location}  #{m[0][0, 70]}"
      # Check for text: option
      elsif (m = line.match(text_option)) && m[2].match?(noun)
        "#{location}  #{m[0][0, 70]}"
      end
    end
  end

  it "never asserts the bare noun in a text matcher" do
    offenders = Dir.glob(Rails.root.join("spec/**/*_spec.rb"))
      .map { |f| Pathname.new(f) }
      .reject { |p| p.to_s == __FILE__ }
      .flat_map { |p| offenders_in(p, matcher, text_option, noun, allowed) }

    expect(offenders).to be_empty,
      "Text matchers with the literal noun — assert I18n.t(\"…\") so a renamed fork stays green:\n  #{offenders.join("\n  ")}"
  end

  it "reports planted literals and ignores model references" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("probe_spec.rb")
      path.write(%(expect(page).to have_content("Create a workspace")\nclick_link "New workspace"\nexpect(page).to have_css("h1", text: "Your workspaces")\nexpect(page).to have_content(workspace.name)\n))

      expect(offenders_in(path, matcher, text_option, noun).size).to eq(3)
    end
  end
end
