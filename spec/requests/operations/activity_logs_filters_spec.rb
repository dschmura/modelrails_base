require "rails_helper"

RSpec.describe "Operations activity ledger filters", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  def rows(body) = Capybara.string(body).all("tbody tr")

  # A `project.created` row names nothing the page can show: Trackable writes
  # no metadata for a creation and the sentence is "created the <project>".
  # A RENAME does — its `changes` metadata carries the name, which the details
  # row renders — so these examples label a row by renaming its project, the
  # one per-record handle the ledger actually puts on the page. Returns the
  # rename's own activity row.
  def plan_named(workspace, name)
    project = create(:project, workspace: workspace)
    project.update!(name: name)
    project.activities.order(:created_at, :id).last
  end

  # ActivityLog#readonly? blocks instance-level update_column too (it is
  # persisted?-gated, not save-path-specific) — go relation-level, the same
  # door spec/models/activity_log_filters_spec.rb uses.
  def backdate(activity_log, to)
    ActivityLog.where(id: activity_log.id).update_all(created_at: to)
  end

  # Acting AS someone is a session, not an assignment: Current.user delegates
  # to Current.session (spec/models/activity_log_filters_spec.rb's pattern).
  def acting_as(user)
    Current.session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    yield
  ensure
    Current.session = nil
  end

  it "applies the 30-day window by default and widens on range=all" do
    workspace = create(:workspace, name: "Alpha")
    backdate(plan_named(workspace, "Old plan"), 40.days.ago)

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Old plan")

    get operations_activity_logs_path(range: "all")
    expect(response.body).to include("Old plan")
  end

  it "filters by workspace slug and by the instance level" do
    alpha = create(:workspace, name: "Alpha")
    beta  = create(:workspace, name: "Beta")
    plan_named(alpha, "Alpha plan")
    plan_named(beta, "Beta plan")
    Operatorship.grant!(user: create(:user, first_name: "Gale", last_name: "Grantee"))

    get operations_activity_logs_path(workspace: alpha.slug)
    expect(response.body).to include("Alpha plan")
    expect(response.body).not_to include("Beta plan")

    get operations_activity_logs_path(workspace: "instance")
    expect(response.body).to include("granted Gale Grantee operator access")
    expect(response.body).not_to include("Alpha plan")
  end

  it "filters by kind on the stored action prefix and ignores unknown kinds" do
    workspace = create(:workspace, name: "Alpha")
    plan_named(workspace, "Alpha plan")
    joined = I18n.t("activity.actions.membership.created")

    # Positive control: the sentence the kind filter must remove is on the
    # unfiltered page, so its absence below can only mean the filter ran.
    get operations_activity_logs_path
    expect(Capybara.string(response.body)).to have_text(joined)

    get operations_activity_logs_path(kind: "project")
    expect(response.body).to include("Alpha plan")
    expect(Capybara.string(response.body)).to have_no_text(joined)

    get operations_activity_logs_path(kind: "bogus")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Alpha plan")
    expect(Capybara.string(response.body)).to have_text(joined)
  end

  it "filters by an exact email and says so when no user has it" do
    person = create(:user, first_name: "Priya", last_name: "Nair")
    workspace = create(:workspace, name: "Alpha")
    acting_as(person) { plan_named(workspace, "Priya plan") }
    plan_named(workspace, "Other plan")

    get operations_activity_logs_path(person: person.email_address.upcase)
    expect(response.body).to include("Priya plan")
    expect(response.body).not_to include("Other plan")

    get operations_activity_logs_path(person: "nobody@example.com")
    expect(rows(response.body)).to be_empty
    expect(Capybara.string(response.body)).to have_text(I18n.t("operations.activity_logs.index.summary.no_user"))
  end

  it "sorts oldest first on direction=asc" do
    workspace = create(:workspace, name: "Alpha")
    first = plan_named(workspace, "First plan")
    plan_named(workspace, "Second plan")
    backdate(first, 2.days.ago)

    get operations_activity_logs_path(sort: "created_at", direction: "asc")
    body = response.body
    expect(body.index("First plan")).to be < body.index("Second plan")
  end

  it "caps rows=all at 500 and says so" do
    stub_const("Operations::ActivityLogsController::ALL_ROWS", 3)
    5.times { create(:workspace) }

    get operations_activity_logs_path(rows: "all")
    expect(rows(response.body).size).to eq(3)
    expect(Capybara.string(response.body)).to have_text(
      I18n.t("operations.activity_logs.index.rows.capped", limit: 3, count: ActivityLog.for_operations_feed.count)
    )
  end

  it "paginates through countish so the page param carries the memoized count" do
    workspace = create(:workspace)
    3.times { |i| create(:project, workspace: workspace, name: "Plan #{i}") }

    get operations_activity_logs_path(rows: "25")
    html = Capybara.string(response.body)
    expect(html).to have_css("nav[aria-label='#{I18n.t('operations.activity_logs.index.rows.label')}'] a[aria-current='true']", text: "25")
    expect(html).to have_text(I18n.t("operations.activity_logs.index.rows.showing", from: 1, to: ActivityLog.for_operations_feed.count, count: ActivityLog.for_operations_feed.count))
  end
end
