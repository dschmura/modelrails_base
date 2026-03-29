module ApplicationHelper
  def current_user_theme
    Current.user&.preferences&.theme || "system"
  end
end
