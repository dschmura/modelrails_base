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

    # Fix round 2, item 8: SQLite's BINARY collation sorts uppercase before
    # lowercase, so a plain `.order("workspaces.name")` reads as alphabetical
    # but isn't. workspaces.name is a plain column (unlike User#first_name/
    # #last_name, which are non-deterministically encrypted and can be
    # neither searched nor ORDER BY'd in SQL — R21), so this can be fixed in
    # SQL rather than sorted in Ruby.
    it "orders memberships by workspace name case-insensitively" do
      create(:membership, user: target, workspace: create(:workspace, name: "zeta"))
      create(:membership, user: target, workspace: create(:workspace, name: "Acme"))
      create(:membership, user: target, workspace: create(:workspace, name: "beta"))
      create(:membership, user: target, workspace: create(:workspace, name: "Delta"))

      get operations_user_path(target)
      body = response.body
      # Binary collation would read Acme, Delta, beta, zeta (uppercase first).
      # Case-insensitive alphabetical is Acme, beta, Delta, zeta.
      positions = %w[Acme beta Delta zeta].map { |name| body.index(name) }
      expect(positions).to all(be_present)
      expect(positions).to eq(positions.sort)
    end
  end
end
