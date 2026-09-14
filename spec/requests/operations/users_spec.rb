require "rails_helper"

RSpec.describe "Operations users", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let!(:target) { create(:user, email_address: "target@example.com", first_name: "Tess", last_name: "Target") }
  let!(:other) { create(:user, email_address: "other@example.com", first_name: "Otto", last_name: "Other") }

  before { sign_in(operator) }

  describe "GET /operations/users" do
    it "renders no user rows without a query" do
      get operations_users_path
      expect(response).to have_http_status(:ok)
      html = Capybara.string(response.body)
      expect(html).to have_no_text("Tess Target")
      expect(html).to have_no_text("Otto Other")
    end

    it "finds a user by exact email" do
      get operations_users_path(q: "Target@Example.com")
      html = Capybara.string(response.body)
      expect(html).to have_text("Tess Target")
      expect(html).to have_no_text("Otto Other")
    end

    it "says so when nothing matches" do
      get operations_users_path(q: "nobody@example.com")
      expect(Capybara.string(response.body)).to have_text(I18n.t("operations.users.index.no_match"))
    end
  end

  describe "GET /operations/users/:id" do
    it "shows memberships with roles and lock state" do
      workspace = create(:workspace, name: "Acme")
      create(:membership, :admin, user: target, workspace: workspace)
      get operations_user_path(target)
      html = Capybara.string(response.body)
      expect(html).to have_text("Acme")
      expect(html).to have_text("Admin")
    end
  end
end
