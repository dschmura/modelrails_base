module Operations
  class ActivityLogsController < BaseController
    ROWS         = %w[25 50 100 all].freeze
    # The two columns the ledger can order in SQL. Who is not among them: actor
    # names are encrypted (operations.md, "What it deliberately does not do").
    SORTS = %w[created_at workspace].freeze
    DEFAULT_SORT = "created_at"
    DEFAULT_ROWS = "50"
    # "All" is all of the current filter and window, up to this many rows.
    # The cost is the page, not the decrypt (0.012 ms a row, ActivityLog::Search):
    # 500 rows of <details> is already a long document, and an uncapped All on
    # "All time" is one that never finishes rendering.
    ALL_ROWS = 500

    def index
      authorize [ :operations, ActivityLog ]
      resolve_filters
      @pagy, page = pagy(:countish, filtered_scope, limit: row_limit, max_limit: ALL_ROWS)
      @activities = page.for_feed
      # Page 1 only: "the first 500 of N" is true of the first page and false of
      # every one after it, which shows the ordinary Showing 501–1000 copy.
      @capped = @rows == "all" && @pagy.count > ALL_ROWS && @pagy.page == 1
    end

    private

    def resolve_filters
      @zone = Current.user.preferences&.time_zone || Time.zone
      @range = ActivityLog::Range.resolve(key: params[:range], from: params[:from], to: params[:to], zone: @zone)
      # `person` was the exact-email control this box replaces; it stays an
      # alias for one release so existing links and bookmarks keep filtering.
      @search = ActivityLog::Search.resolve(params[:q].presence || params[:person].presence,
                                            reach: operated_workspaces)
      # The NORMALIZED needle, so the box, the summary and every link the page
      # builds all say the one thing that was actually searched.
      @query = @search.query
      @workspace_param = params[:workspace].presence
      @workspace = @workspace_param && @workspace_param != "instance" ? operated_workspaces.find_by(slug: @workspace_param) : nil
      @workspace_param = nil if @workspace_param && @workspace_param != "instance" && @workspace.nil?
      @kind = ActivityLog::KINDS.include?(params[:kind]) ? params[:kind] : nil
      @sort = SORTS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
      @direction = params[:direction] == "asc" ? "asc" : "desc"
      @rows = ROWS.include?(params[:rows]) ? params[:rows] : DEFAULT_ROWS
      # The Workspace filter's options. Built here, not in the partial:
      # `operated_workspaces` is BaseController's private reach relation and
      # never a helper — a view has no door to it.
      @workspace_options = operated_workspaces.order(Arel.sql("LOWER(workspaces.name)"))
                             .map { |workspace| { value: workspace.slug, label: workspace.name } }
    end

    def filtered_scope
      scope = ActivityLog.for_operations_feed.includes(:workspace)
      # A query that named nobody and nothing is a filter that matched, not an
      # absent filter — `none` is the honest answer, and it still responds to
      # `for_feed` (an empty Array) and to countish (count 0).
      if @query
        scope = @search.matched? ? scope.merge(search_scope) : scope.none
      end
      scope = scope.at_instance_level if @workspace_param == "instance"
      scope = scope.for_workspace(@workspace) if @workspace
      scope = scope.of_kind(@kind) if @kind
      scope = scope.within(@range.from, @range.to) if @range.bounded?
      scope = scope.by_workspace_name(@direction) if @sort == "workspace"
      scope = scope.oldest_first if @sort == DEFAULT_SORT && @direction == "asc"
      scope
    end

    def search_scope
      ActivityLog.matching_any(users: @search.users, workspaces: @search.workspaces,
                               projects: @search.projects)
    end

    def row_limit
      @rows == "all" ? ALL_ROWS : @rows.to_i
    end
  end
end
