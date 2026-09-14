require "rails_helper"

RSpec.describe "Operations activity feed", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  it "renders rows from several workspaces" do
    w1 = create(:workspace, name: "Alpha")
    w2 = create(:workspace, name: "Beta")
    create(:project, workspace: w1)
    create(:project, workspace: w2)

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    html = Capybara.string(response.body)
    expect(html).to have_text("Alpha")
    expect(html).to have_text("Beta")
  end

  # Re-derived after a session restart lost the reviewer's findings list, so it
  # carries no finding number. activity_logs/_activity_log renders a top-level
  # <li>, and this page wrapped each one in its own <ol> to give that <li> a
  # legal parent — making every entry a nested one-item list, which a screen
  # reader announces as "list, 1 item" on every row. Valid HTML, so axe passes
  # it: the structure has to be asserted directly.
  it "renders each row in one flat list, not a nested one-item list per row" do
    workspace = create(:workspace, name: "Alpha")
    create(:project, workspace: workspace)

    get operations_activity_logs_path
    html = Capybara.string(response.body)

    expect(html).to have_css("ol > li", text: "Alpha")
    expect(html).to have_no_css("li ol")
  end

  it "has an index that can serve a global created_at ordering" do
    indexes = ActiveRecord::Base.connection.indexes(:activity_logs).map(&:columns)
    expect(indexes).to include([ "created_at" ])
  end

  # Fix round 1, finding 5: 20 is Pagy::OPTIONS[:limit] (config/initializers/pagy.rb);
  # the original example created about 6 rows and was named for pagination
  # without ever crossing a page boundary, so the nav's locals contract went
  # unexercised. 25 distinct workspaces guarantees a real second page.
  it "paginates once rows cross a page boundary" do
    25.times { |i| create(:workspace, name: "WS #{i}") }

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    expect(Capybara.string(response.body)).to have_css("nav.series-nav")
  end

  # Fix round 1, finding 4: nothing previously bound the controller to the
  # privacy-bearing scope — swapping for_operations_feed for ActivityLog.all
  # left both other examples green, since neither creates a personal row.
  #
  # Not a bare name-absence check: create(:user) itself onboards a personal
  # workspace and writes a legitimate membership.created row naming that same
  # user (Trackable), so the new user's own name is already on the page for a
  # reason unrelated to the row under test — asserting its absence would pass
  # or fail for the wrong reason. Binding the rendered row count to the scope's
  # own count proves the view renders exactly what the privacy-excluding scope
  # returns, which is what actually needs proving at the request level.
  it "excludes personal-visibility security rows from the feed" do
    create(:workspace)
    private_user = create(:user)
    ActivityLog.record_security_event!(action: "user.password_changed", user: private_user)

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)

    rendered_rows = Capybara.string(response.body).all("li time").size
    expect(rendered_rows).to eq(ActivityLog.for_operations_feed.count)
  end

  # Fix round 1, finding 1: this page is the first surface to render
  # admin-visibility rows, and an operatorship grant's trackable is the
  # grantee User (not a Membership), so the row used to say "a member" instead
  # of naming anyone.
  #
  # Asserts the composed sentence, not a bare name-presence check: create(:user)
  # onboards its own workspace and writes a membership.created row that ALSO
  # names the grantee (as the member who joined) — a plain "page has text
  # 'Gale Grantee'" assertion would pass even with the bug unfixed, because
  # that unrelated row already supplies the name. The activity.actions.operatorship.granted
  # sentence ("granted %{member} operator access") is unique to this row.
  it "names the granted user on an operatorship row, not the neutral fallback" do
    grantee = create(:user, first_name: "Gale", last_name: "Grantee")
    Operatorship.grant!(user: grantee)

    get operations_activity_logs_path
    expect(Capybara.string(response.body)).to have_text("granted Gale Grantee operator access")
  end
end
