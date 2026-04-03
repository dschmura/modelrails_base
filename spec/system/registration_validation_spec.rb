require "rails_helper"

RSpec.describe "Registration form validation", type: :system do
  describe "error display" do
    it "shows error summary and inline errors on invalid submission" do
      visit new_registration_path
      click_button I18n.t("registrations.new.submit")

      # Error summary should be visible
      expect(page).to have_css("[role='alert']")

      # Inline errors should appear next to fields
      expect(page).to have_css("#user_email_address-error[role='alert']")
      expect(page).to have_css("#user_first_name-error[role='alert']")
    end

    it "shows duplicate email error" do
      create(:user, email_address: "taken@example.com")
      visit new_registration_path

      fill_in I18n.t("registrations.new.email_label"), with: "taken@example.com"
      fill_in I18n.t("registrations.new.first_name_label"), with: "Jane"
      fill_in I18n.t("registrations.new.last_name_label"), with: "Doe"
      fill_in I18n.t("registrations.new.password_label"), with: "SecureP@ssw0rd123!"
      fill_in I18n.t("registrations.new.password_confirmation_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("registrations.new.submit")

      expect(page).to have_css("[role='alert']")
      expect(page).to have_text(/already been taken/i)
    end

    it "shows password too short error" do
      visit new_registration_path

      fill_in I18n.t("registrations.new.email_label"), with: "new@example.com"
      fill_in I18n.t("registrations.new.first_name_label"), with: "Jane"
      fill_in I18n.t("registrations.new.last_name_label"), with: "Doe"
      fill_in I18n.t("registrations.new.password_label"), with: "short"
      fill_in I18n.t("registrations.new.password_confirmation_label"), with: "short"
      click_button I18n.t("registrations.new.submit")

      expect(page).to have_css("[role='alert']")
      expect(page).to have_text(/too short/i)
    end

    it "escapes HTML in name fields (XSS prevention)" do
      visit new_registration_path

      fill_in I18n.t("registrations.new.first_name_label"), with: "<script>alert('xss')</script>"
      fill_in I18n.t("registrations.new.last_name_label"), with: "Doe"
      fill_in I18n.t("registrations.new.email_label"), with: "xss@example.com"
      fill_in I18n.t("registrations.new.password_label"), with: "SecureP@ssw0rd123!"
      fill_in I18n.t("registrations.new.password_confirmation_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("registrations.new.submit")

      # Should not execute script — the name should be escaped in the rendered page
      expect(page).not_to have_css("script")
    end
  end
end
