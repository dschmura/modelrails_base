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

  # The filter band lives OUTSIDE the results frame, so a frame-local swap
  # cannot re-render it. Every link inside the frame therefore navigates the
  # whole page; only control CHANGES stay frame-local (for focus).
  it "points every link inside the results frame at _top" do
    workspace = create(:workspace, name: "Alpha")
    plan_named(workspace, "Alpha plan")

    get operations_activity_logs_path(kind: "project")
    frame = Capybara.string(response.body).find("turbo-frame#activity_results", visible: :all)
    links = frame.all("a", visible: :all)

    expect(links.size).to be >= 3 # Clear, the sort header, four Rows links
    expect(links.map { |link| link[:"data-turbo-frame"] }.uniq).to eq([ "_top" ])
  end

  # A submit without a submitter (any control's change) carries these forward.
  # Seeded from the resolved ivars, not raw params, so a custom window survives
  # a Person/Workspace/Kind change.
  it "seeds the band's hidden fields from the resolved filter state" do
    create(:workspace, name: "Alpha")

    get operations_activity_logs_path(range: "custom", from: "2026-09-03", to: "2026-09-17",
                                      direction: "asc", rows: "100")
    hidden = Capybara.string(response.body)
      .all("form input[type=hidden]", visible: :all)
      .to_h { |field| [ field[:name], field[:value] ] }

    expect(hidden).to include("range" => "custom", "from" => "2026-09-03", "to" => "2026-09-17",
                              "direction" => "asc", "rows" => "100")

    # The default window and direction seed nothing — a bare URL stays bare.
    get operations_activity_logs_path
    names = Capybara.string(response.body).all("form input[type=hidden]", visible: :all).map { |f| f[:name] }
    expect(names).to include("range")
    expect(names).not_to include("direction", "rows", "from", "to")
  end

  # Without a blank option the combobox can be set but never un-set: once a
  # workspace is chosen there is no option that clears it.
  it "offers a blank option that clears the workspace filter" do
    alpha = create(:workspace, name: "Alpha")

    get operations_activity_logs_path(workspace: alpha.slug)
    options = Capybara.string(response.body)
      .all("[role=listbox] [role=option]", visible: :all)
      .map { |option| [ option[:"data-combobox-value"], option.text ] }

    expect(options.first).to eq([ "", I18n.t("operations.activity_logs.index.filters.workspace_any") ])
    expect(options[1]).to eq([ "instance", I18n.t("operations.activity_logs.index.instance") ])
  end

  # pagy reads `limit` off the query string, so a foreign `limit` riding along
  # on a Rows link wins over `rows` and makes that link's aria-current="true" a
  # lie. ledger_filter_params allow-lists the filter keys for that reason.
  it "keeps foreign query params out of the links it builds" do
    workspace = create(:workspace)
    create(:project, workspace: workspace, name: "Alpha plan")

    get operations_activity_logs_path(limit: "10", foo: "bar", kind: "project")
    rows_links = Capybara.string(response.body)
      .all("nav[aria-label='#{I18n.t('operations.activity_logs.index.rows.label')}'] a")
      .map { |link| link[:href] }

    expect(rows_links.size).to eq(Operations::ActivityLogsController::ROWS.size)
    expect(rows_links).to all(include("kind=project"))
    expect(rows_links.join(" ")).not_to include("limit=")
    expect(rows_links.join(" ")).not_to include("foo=")
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
