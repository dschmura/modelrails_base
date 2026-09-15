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
      # Item 7b (fix round 1): the title claimed "lock state" but nothing
      # asserted it — scoped to the Locked dt/dd pair, not a bare have_text,
      # since "No" also appears in the Operator row.
      locked_dd = html.find(:xpath, "//dt[normalize-space(text())='#{I18n.t('operations.users.show.locked')}']/following-sibling::dd[1]")
      expect(locked_dd.text).to eq(I18n.t("operations.negative"))
      expect(html).to have_no_button(I18n.t("operations.users.show.unlock"))
    end

    # Item 7b (fix round 1): the show page renders a lock-gated Unlock button
    # that nothing covered — the reviewer's mutation-provable gap.
    it "shows the Unlock button only for a locked account" do
      5.times { target.register_failed_login! }
      get operations_user_path(target)
      html = Capybara.string(response.body)
      locked_dd = html.find(:xpath, "//dt[normalize-space(text())='#{I18n.t('operations.users.show.locked')}']/following-sibling::dd[1]")
      expect(locked_dd.text).to eq(I18n.t("operations.affirmative"))
      expect(html).to have_button(I18n.t("operations.users.show.unlock"))
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

      # Scoped to the membership list, not the whole body: target's own
      # onboarding workspace is in this list under a Faker name, and a raw
      # body.index search matched it first whenever that name happened to
      # contain one of these tokens (deterministic failure on seed 58938).
      # Array#& keeps the receiver's order, so this reads the rendered order
      # and ignores the unrelated row.
      rendered = Capybara.string(response.body)
                         .find("section[aria-labelledby='ops-user-memberships']")
                         .all("li a").map(&:text)
      # Binary collation would read Acme, Delta, beta, zeta (uppercase first).
      # Case-insensitive alphabetical is Acme, beta, Delta, zeta.
      expect(rendered & %w[Acme beta Delta zeta]).to eq(%w[Acme beta Delta zeta])
    end
  end

  describe "DELETE /operations/users/:id/lock" do
    it "unlocks" do
      5.times { target.register_failed_login! }
      expect(target.reload).to be_locked
      delete operations_user_lock_path(target)
      expect(target.reload).not_to be_locked
      expect(response).to redirect_to(operations_user_path(target))
      expect(flash[:notice]).to eq(I18n.t("operations.users.locks.destroy.success"))
    end
  end

  describe "POST /operations/users/:id/suspension" do
    it "suspends access" do
      workspace = create(:workspace)
      create(:membership, :owner, user: target, workspace: workspace)
      create(:membership, :owner, workspace: workspace)
      post operations_user_suspension_path(target)
      expect(target.reload.memberships.kept).to be_empty
      expect(flash[:notice]).to eq(I18n.t("operations.users.suspensions.create.success"))
    end
  end
end
