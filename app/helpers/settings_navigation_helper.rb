module SettingsNavigationHelper
  # Returns the kind of settings context the sidebar should render.
  #
  # The Settings hub has two sibling sections — personal account settings and
  # organization (workspace) settings. We never present both at once; the active
  # Current.workspace decides which sidebar to render. When no workspace is
  # active (an unauthenticated edge), default to :personal so the layout still
  # has something coherent to render.
  def settings_context_kind
    return :personal if Current.workspace.nil?

    Current.workspace.personal? ? :personal : :org
  end

  # Renders a sidebar nav block only when the given Pundit policy permits the
  # action. By consulting the *same* policy/action the destination controller
  # authorizes against, we keep sidebar visibility and controller authorization
  # in lockstep — no separate SidebarPolicy to drift from the source of truth.
  def nav_item_if_permitted(record, action:, &block)
    return nil unless block_given?

    policy = Pundit.policy(current_user, record)
    return nil unless policy.public_send(action)

    capture(&block)
  end

  private

  # ActionController exposes #current_user as a private controller method, not
  # a view helper. Define a thin shim here so the helper is callable from any
  # rendering context (and stubbable in helper specs) without depending on
  # whether the controller exposed current_user via helper_method.
  def current_user
    Current.user
  end
end
