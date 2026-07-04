module SettingsNavigationHelper
  # Renders a sidebar nav block only when the given Pundit policy permits the
  # action. By consulting the *same* policy/action the destination controller
  # authorizes against, we keep sidebar visibility and controller authorization
  # in lockstep — no separate SidebarPolicy to drift from the source of truth.
  #
  # Pass policy_class: when the record has more than one scoped policy and the
  # convention-inferred one isn't the gate to consult — e.g. a Workspace is
  # authorized by Workspaces::SettingsPolicy / Workspaces::ProfilePolicy rather
  # than the default WorkspacePolicy for those destinations.
  def render_nav_item_if_permitted(record, action:, policy_class: nil, &block)
    return nil unless block_given?

    policy = policy_class ? policy_class.new(Current.user, record) : Pundit.policy(Current.user, record)
    return nil unless policy.public_send(action)

    capture(&block)
  end

  # Returns a localized announcement string for the polite aria-live region
  # when a workspace context is active. The string interpolates the workspace
  # name, the viewer's role, and the list of sidebar items they can actually
  # see (so the announcement matches what's rendered). Returns nil for the
  # identity context and unauthenticated cases — the layout uses the
  # static identity template instead.
  def current_workspace_announcement_for_aria_live
    workspace = Current.workspace
    return nil if workspace.nil? || workspace.personal?

    membership = workspace.memberships.detect { |m| m.user_id == Current.user&.id }
    role_name = membership&.role&.name || Role.find_by(slug: "member", workspace_id: nil)&.name || "Member"

    I18n.t("settings.sidebar.aria_live_template.workspace",
           name: workspace.name,
           role: role_name,
           items: workspace_settings_nav_items.map { |i| i[:label] }.join(", "))
  end

  # Ordered workspace-settings nav items the current user is authorized to see.
  # Single source of truth for the desktop <aside>, the mobile strip, AND the
  # aria-live announcer — the gating lives here once (was duplicated in a
  # hand-synced list). Each item's :active is computed against the current URL.
  def workspace_settings_nav_items
    workspace = Current.workspace
    items = []

    if Workspaces::ProfilePolicy.new(Current.user, workspace).update?
      items << { label: t("settings.sidebar.items.profile"),
                 href: edit_workspace_path(workspace),
                 icon: :user_circle,
                 aria_label: t("settings.sidebar.aria_labels.profile_org", workspace_name: workspace.name),
                 active: current_page?(edit_workspace_path(workspace)) }
    end
    if Pundit.policy(Current.user, Membership.new(workspace: workspace)).index?
      items << { label: t("settings.sidebar.items.members"),
                 href: workspace_members_path(workspace),
                 icon: :user_group,
                 aria_label: t("settings.sidebar.aria_labels.members", workspace_name: workspace.name),
                 active: current_page?(workspace_members_path(workspace)) }
    end
    if Workspaces::SettingsPolicy.new(Current.user, workspace).update?
      items << { label: t("settings.sidebar.items.limits_and_plan"),
                 href: edit_workspace_settings_path(workspace),
                 icon: :chart_bar,
                 aria_label: t("settings.sidebar.aria_labels.limits_and_plan", workspace_name: workspace.name),
                 active: current_page?(edit_workspace_settings_path(workspace)) }
    end

    items
  end
end
