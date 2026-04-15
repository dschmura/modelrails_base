require "rails_helper"

RSpec.describe "Account profile — identity picker", type: :system do
  let(:user) { create(:user) }
  let(:avatar_fixture) { Rails.root.join("spec/fixtures/files/avatar.png") }

  before do
    sign_in_via_form(user)
    visit edit_account_profile_path
  end

  describe "photo upload flow" do
    it "uploads, crops, and saves a new avatar" do
      open_identity_picker

      # Select Photo source — since no image exists yet, this opens the file picker
      select_identity_source("Photo")

      attach_identity_picker_file(avatar_fixture)

      # File select triggers crop view automatically
      wait_for_crop_view

      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      # After save, modal returns to hub
      wait_for_hub_view

      # Server-side state: avatar and avatar_original both attached, source is upload
      user.reload
      expect(user.avatar).to be_attached
      expect(user.avatar_original).to be_attached
      expect(user.avatar_source).to eq("upload")
    end
  end
end
