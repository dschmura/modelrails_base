module Operations
  module ActivityLedgerHelper
    # The applied state as one sentence: "128 events · Acme Robotics · members · 3–17 Sep 2026".
    # Rendered as the results <h2>, the page title, and the status announcement.
    def ledger_summary
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

    # Current filter params with overrides, page dropped — every footer and
    # pivot link rebuilds the URL from this so no filter is lost.
    def ledger_filter_params(**overrides)
      request.query_parameters.symbolize_keys.except(:page).merge(overrides).compact
    end

    def ledger_time(time)
      local = time.in_time_zone(@zone)
      tag.time(l(local, format: :ledger), datetime: time.iso8601, class: "tabular-nums whitespace-nowrap")
    end
  end
end
