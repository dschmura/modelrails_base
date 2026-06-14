require "rails_helper"

# Guards the layout chrome shared between application.html.erb and
# settings.html.erb via shared/_layout_head and shared/_layout_tail (#146):
# both layouts must render the same head, skip link, and tail.
#
# The settings hub's Turbo morph is deliberately NOT activated by this refactor.
# turbo_refreshes_with was dead code (it provides :head but no layout yields it)
# and was dropped; re-enabling morph is tracked in #327. The morph-absent
# assertion guards against the shared head silently re-activating it.
RSpec.describe "Shared layout chrome", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  shared_examples "shared layout chrome" do
    it "renders the shared head, skip link, and notifications live region" do
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('meta[name="description"]')).not_to be_nil
      expect(doc.at_css('link[rel="manifest"]')).not_to be_nil
      expect(doc.at_css('a[href="#main-content"]')).not_to be_nil
      expect(doc.at_css('#notifications-live[aria-live="polite"]')).not_to be_nil
    end

    it "does not emit a turbo-refresh meta (morph re-enable tracked in #327)" do
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('meta[name="turbo-refresh-method"]')).to be_nil
    end
  end

  context "application layout (non-settings page)" do
    before { get root_path }

    include_examples "shared layout chrome"
  end

  context "settings layout" do
    before { get edit_account_theme_preference_path }

    include_examples "shared layout chrome"
  end
end
