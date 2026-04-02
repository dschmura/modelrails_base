require "rails_helper"

RSpec.describe "User menu", type: :request do
  describe "authenticated user" do
    let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }
    before { sign_in(user) }

    it "renders the user menu trigger with avatar initials" do
      get root_path
      expect(response.body).to include("JD")
      expect(response.body).to include('aria-haspopup="true"')
    end

    it "includes a profile link in the user menu" do
      get root_path
      expect(response.body).to include(edit_account_profile_path)
    end

    it "includes a sign out form in the user menu" do
      get root_path
      expect(response.body).to include('action="/session"')
    end

    it "displays user name and email in the menu" do
      get root_path
      expect(response.body).to include(CGI.escapeHTML(user.full_name))
      expect(response.body).to include(CGI.escapeHTML(user.email_address))
    end

    it "does not render inline sign-out link in desktop nav" do
      get root_path
      doc = Nokogiri::HTML(response.body)
      desktop_nav = doc.at_css(".hidden.md\\:flex")
      sign_out_buttons = desktop_nav.css('input[value="' + I18n.t("navigation.sign_out") + '"]')
      expect(sign_out_buttons.length).to eq(0)
    end
  end

  describe "unauthenticated user" do
    it "shows sign in link instead of user menu" do
      get root_path
      expect(response.body).to include(I18n.t("navigation.sign_in"))
      expect(response.body).not_to include('id="user-menu"')
    end
  end
end
