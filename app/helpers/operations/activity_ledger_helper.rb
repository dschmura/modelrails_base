module Operations
  module ActivityLedgerHelper
    # The only query params a ledger link may carry forward. An allow-list, not
    # a denylist: pagy reads `limit` straight off the query string, so passing
    # the whole of query_parameters through put a foreign `limit` on every Rows
    # link — where it wins over `rows` and makes the aria-current="true" a lie.
    FILTER_KEYS = %i[person workspace kind range from to sort direction rows].freeze

    # The applied state as one sentence: "128 events · Acme Robotics · members · 3–17 Sep 2026".
    # Rendered as the results <h2>, the page title, and the status announcement —
    # three calls per request, so memoized.
    def ledger_summary
      @ledger_summary ||= build_ledger_summary
    end

    def build_ledger_summary
      parts = [ t("operations.activity_logs.index.summary.events", count: @pagy.count) ]
      parts << (@person ? @person.email_address : t("operations.activity_logs.index.summary.no_user")) if @person_email
      parts << (@workspace_param == "instance" ? t("operations.activity_logs.index.instance") : @workspace.name) if @workspace_param
      parts << t("activity.kinds.#{@kind}") if @kind
      parts << ledger_range_label
      parts.join(t("operations.activity_logs.index.summary.separator"))
    end

    def ledger_range_label
      return t("operations.activity_logs.index.ranges.all") if @range.all?
      return t("operations.activity_logs.index.ranges.#{@range.key}") unless @range.custom?

      t("operations.activity_logs.index.ranges.custom_trigger",
        from: l(@range.from_date, format: :ledger_short), to: l(@range.to_date, format: :ledger_day))
    end

    # The current filter params with overrides — every footer and pivot link
    # rebuilds the URL from this so no filter is lost, and nothing else rides
    # along (`page` and pagy's `limit` included).
    def ledger_filter_params(**overrides)
      request.query_parameters.symbolize_keys.slice(*FILTER_KEYS).merge(overrides).compact
    end

    def ledger_time(time)
      local = time.in_time_zone(@zone)
      tag.time(l(local, format: :ledger), datetime: time.iso8601, class: "tabular-nums whitespace-nowrap")
    end
  end
end
