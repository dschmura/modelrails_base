require "rails_helper"

RSpec.describe "Account settings layout is account-only", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "renders account settings with no workspace identity bar, announcer, or workspace-kind hook" do
    get edit_settings_profile_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#settings-aria-live")).to be_nil
    expect(doc.at_css("#workspace-name-heading")).to be_nil
    expect(doc.at_css("[data-workspace-kind]")).to be_nil
    # Identity sidebar items still render (Profile link present).
    aside = doc.at_css('aside[aria-label="' + I18n.t("settings.sidebar.aria_label") + '"]')
    expect(aside).not_to be_nil
    expect(aside.at_css('a[href="' + edit_settings_profile_path + '"]')).not_to be_nil
  end
end
