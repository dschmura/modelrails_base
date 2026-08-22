# frozen_string_literal: true

require "rails_helper"

# W1-2 (2026-08-22 view-layer audit (internal)): at phone widths the
# project-show nav row overflowed (scrollWidth 385 > clientWidth 375) because
# its links laid out in a single non-wrapping flex row. The nav must wrap.
RSpec.describe "Project nav at narrow viewports", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }

  before do
    create(:project_membership, :creator, project: project, user: user)
    sign_in_via_form(user)
  end

  it "keeps all project nav links on-screen at 375px" do
    with_viewport(375) do
      visit workspace_project_path(workspace, project)

      no_horizontal_overflow = page.evaluate_script(
        "document.documentElement.scrollWidth <= document.documentElement.clientWidth"
      )
      expect(no_horizontal_overflow).to be(true), "page overflows the 375px viewport"

      # The page renders several nav[aria-label] landmarks (tool tabs,
      # breadcrumbs, ...) — scope to this one by its aria-label value, which
      # also exercises the i18n'd label (was a hardcoded string pre-fix).
      within("nav[aria-label='#{I18n.t('workspaces.projects.show.nav_label')}']") do
        # Owner (project creator) sees members/edit/tools/client access.
        expect(page).to have_link(count: 4)
      end
    end
  end
end
