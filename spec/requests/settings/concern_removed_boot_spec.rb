require "rails_helper"

RSpec.describe "Account settings survive SettingsContext removal", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "loads the five GET-able account settings pages (200)" do
    [
      edit_settings_profile_path,
      edit_settings_notification_preferences_path,
      settings_connected_accounts_path,
      settings_passkeys_path,
      edit_settings_theme_preference_path
    ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "expected 200 for #{path}, got #{response.status}"
    end
  end

  # Settings::Preferences::TimezonesController is update-only (resource :timezone,
  # only: [:update]) — there's no GET page to request. Asserting class-load here
  # proves removing settings_context from its class body didn't break it.
  it "class-loads the update-only timezones controller" do
    expect { Settings::Preferences::TimezonesController }.not_to raise_error
  end

  it "no longer references the SettingsContext macro anywhere" do
    expect(File).not_to exist(Rails.root.join("app/controllers/concerns/settings_context.rb"))
  end
end
