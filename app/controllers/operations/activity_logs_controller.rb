module Operations
  class ActivityLogsController < BaseController
    def index
      authorize [ :operations, ActivityLog ]
      # pagy(:offset, relation) hands back an ActiveRecord::Relation (only a
      # plain Array gets sliced in Ruby), so `page.for_feed` delegates through
      # Rails' relation scoping back to ActivityLog.for_feed scoped to this
      # page — not a class-method call on an Array.
      @pagy, page = pagy(:offset, ActivityLog.for_operations_feed.includes(:workspace))
      @activities = page.for_feed
    end
  end
end
