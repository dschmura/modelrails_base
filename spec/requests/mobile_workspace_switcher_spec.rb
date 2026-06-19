# frozen_string_literal: true

require "rails_helper"

# Request spec: verifies the mobile workspace switcher and /me link are present
# in the rendered HTML for authenticated users.
#
# The mobile switcher (`mobile: true` variant of _workspace_switcher.html.erb)
# lives inside the hamburger panel in _header.html.erb. Because it carries
# `md:hidden` it is always in the DOM on every authenticated page — we assert
# on the raw response body, not on visibility.
#
# The /me link is added to both the desktop dropdown and mobile accordion in
# _user_menu.html.erb.
RSpec.describe "Mobile workspace switcher", type: :request do
  let(:user) { create(:user) }
  let!(:second_workspace) do
    ws = create(:workspace)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  before { sign_in(user) }

  describe "user with 2+ workspaces" do
    it "includes mobile switcher links to both workspaces inside the mobile panel" do
      # Reload user so the personal workspace (created by onboarding callback)
      # and the second workspace are both visible to switcher_workspaces.
      user.reload
      personal = user.personal_workspace

      get me_path

      expect(response).to have_http_status(:ok)

      body = response.body

      # Both workspace links should appear in the body (the mobile list is always
      # in the DOM even when visually hidden at md+).
      expect(body).to include(workspace_path(personal))
      expect(body).to include(workspace_path(second_workspace))
    end

    it "includes a /me link in the user menu" do
      get me_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(me_path)
    end

    it "includes a /me link text matching the i18n key" do
      get me_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("navigation.user_menu.home"))
    end
  end

  describe "user with 1 workspace (no switcher)" do
    let(:solo_user) { create(:user) }

    before { sign_in(solo_user) }

    it "omits the mobile switcher list entirely (only one workspace)" do
      solo_user.reload
      personal = solo_user.personal_workspace

      get me_path

      expect(response).to have_http_status(:ok)

      # The switcher renders nothing when workspaces.size <= 1.
      # The workspace_path still appears in breadcrumbs/other nav but the
      # role="list" mobile switcher block should be absent.
      expect(response.body).not_to include('role="list"')
    end
  end
end
