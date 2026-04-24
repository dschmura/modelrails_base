module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    # Inverse guard: pages only useful when signed out (registration, sign-in,
    # magic-link request, password-reset request). Authenticated visitors get
    # redirected to root so they don't see a confusing "Create your account"
    # form while they're already signed in.
    def require_unauthenticated_access(**options)
      before_action :redirect_if_authenticated, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def redirect_if_authenticated
      redirect_to root_path, notice: t("authentication.already_signed_in") if resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
        sync_theme_cookie_to_preferences(user)
      end
    end

    def sync_theme_cookie_to_preferences(user)
      cookie_theme = cookies[:theme]
      return unless cookie_theme.present? && %w[light dark system].include?(cookie_theme)

      preferences = user.preferences || user.create_preferences!
      preferences.update!(theme: cookie_theme) if preferences.theme != cookie_theme
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
