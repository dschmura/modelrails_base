module Settings
  class SessionsController < ApplicationController
    layout "settings"

    def index
      @sessions = Current.user.sessions.active.order(last_active_at: :desc)
      # Personal-visibility rows only — the security audit rows written by the
      # credential callbacks (password/passkey changes, new-device sign-in).
      # The workspace feed's "visible" scope is the wrong shape here, it
      # excludes personal rows entirely. Capped at 10: this is a
      # security-context aid on the devices page, not a full audit log.
      # `.load` avoids the view's `.any?` issuing a separate EXISTS query
      # ahead of the `.each` SELECT — this page renders on every visit.
      @recent_activity = ActivityLog.where(trackable: Current.user, visibility: :personal)
                                     .order(created_at: :desc).limit(10).load
    end

    def destroy
      session = Current.user.sessions.find(params[:id])

      if session.id == Current.session.id
        terminate_session
        redirect_to new_session_path, status: :see_other, notice: t(".signed_out_current")
      else
        session.destroy
        redirect_to settings_sessions_path, notice: t(".signed_out", device: session.device_label)
      end
    end
  end
end
