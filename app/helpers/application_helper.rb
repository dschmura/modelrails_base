module ApplicationHelper
  include Pagy::Method

  def current_user_theme
    cookies[:theme].presence || Current.user&.preferences&.theme || "system"
  end

  # The sidebar's remembered collapse state, for rendering the rail in the right shape on
  # the first paint rather than letting JS collapse it after. Written by the `sidebar`
  # Stimulus controller. Treated as a necessary cookie on the same footing as `theme`: it
  # stores a UI choice the visitor made explicitly, not a personalisation signal.
  def sidebar_collapsed?
    cookies[:sidebar_collapsed] == "true"
  end

  # Names trusted-HTML output explicitly so herb-lint's `erb-no-unsafe-raw`
  # rule does not flag every callsite. Use only with content the app itself
  # produced and rendered (e.g. markdown rendered server-side by the
  # markdowndocs gem). Never pass user-supplied raw HTML.
  def safe_html(content)
    content&.html_safe
  end
end
