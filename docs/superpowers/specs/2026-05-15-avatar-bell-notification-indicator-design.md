# Avatar-Overlaid Notification Indicator — Design Spec

**Goal:** Replace the standalone header bell + dropdown with a small solid bell glyph that sits at the bottom-right of the user avatar (per Tailwind Plus's "circular avatars with bottom notification" pattern). Color reflects the highest-severity unread category. The avatar continues to open the user menu; the menu's "Notifications" link shows the count and is the only path to the notifications page.

**Scope:** UI compression of the header notification surface. Removes one full dropdown panel + Stimulus controller. Adds one helper, repurposes one partial, updates one broadcaster module. ~3 files deleted, ~4 modified, ~3 added (including specs).

---

## Problem

The current header reserves two side-by-side 44×44 affordances:

1. A standalone bell (notifications dropdown trigger).
2. The avatar (user-menu trigger).

The bell consumes ~52px of horizontal space (button + `gap-2`) on every page even when there are zero unread notifications. The dropdown panel it triggers duplicates a path that already exists (`/account/notifications`), and the two adjacent triggers add visual weight in a header that should be quiet.

## Solution

### Visual

The avatar becomes the only notification-aware element in the header. When there are unread notifications, a small colored circle containing a **solid bell icon** appears at the avatar's bottom-right corner. The circle's background color encodes the highest unread severity.

```text
Zero unread:                 With unread (security present):
  ┌─────────┐                  ┌─────────┐
  │         │                  │         │
  │  D 👤   │                  │  D 👤   │
  │         │                  │       ╳ │ ◀── solid bell, danger color
  └─────────┘                  └────[🔔]─┘
                                        ▲
                          ring-2 ring-surface-raised
```

The bell overlay is `aria-hidden="true"`; the avatar button's `aria-label` carries the state.

### Interaction

- Clicking the avatar opens the **user menu** (today's behavior, unchanged).
- The user menu's "Notifications" link shows count: `Notifications (3)` or `Notifications (10+)`.
- The link navigates to `/account/notifications` (the existing index page).
- There is **no inline notifications dropdown** anymore.

### Severity mapping

|Category|Severity|Bell `bg-*`|Bell icon `text-*`|
|---|---|---|---|
|`security`|`danger`|`bg-danger`|`text-text-on-danger`|
|`billing`|`warning`|`bg-warning`|`text-text-on-warning`|
|`account_access`|`info`|`bg-info`|`text-text-on-info`|
|`workspace_activity`|`success`|`bg-success`|`text-text-on-success`|
|`project_activity`|`success`|`bg-success`|`text-text-on-success`|
|_unknown / missing category_|`info` (fallback)|`bg-info`|`text-text-on-info`|

When multiple categories are present in the unread set, **the highest severity wins**. Rank: `danger > warning > info > success`.

---

## Architecture

### New files

- `app/helpers/notification_bell_helper.rb` — severity logic + `avatar_button_aria_label`. Defined below.
- `app/views/shared/_notifications_menu_count.html.erb` — slim partial used by `NotificationBroadcaster` to update the "Notifications (N)" link text inside the user menu without re-rendering the whole menu.

#### `app/helpers/notification_bell_helper.rb`

Single source of truth for severity computation.

```ruby
module NotificationBellHelper
  CATEGORY_TO_SEVERITY = {
    security:           :danger,
    billing:            :warning,
    account_access:     :info,
    workspace_activity: :success,
    project_activity:   :success
  }.freeze

  SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }.freeze

  SEVERITY_CLASSES = {
    danger:  { bg: "bg-danger",  icon: "text-text-on-danger"  },
    warning: { bg: "bg-warning", icon: "text-text-on-warning" },
    info:    { bg: "bg-info",    icon: "text-text-on-info"    },
    success: { bg: "bg-success", icon: "text-text-on-success" }
  }.freeze

  def notification_bell_severity(user)
    notifier_classes = unread_notifier_class_names(user)
    return nil if notifier_classes.empty?

    severities = notifier_classes.filter_map do |class_name|
      category = class_name.safe_constantize&.category_name&.to_sym
      CATEGORY_TO_SEVERITY[category] || :info
    end

    severities.max_by { |s| SEVERITY_RANK[s] }
  end

  def notification_bell_classes(severity)
    SEVERITY_CLASSES.fetch(severity, SEVERITY_CLASSES[:info])
  end

  private

  def unread_notifier_class_names(user)
    user.notifications
        .where(read_at: nil)
        .joins("INNER JOIN noticed_events ON noticed_events.id = noticed_notifications.event_id")
        .distinct
        .pluck("noticed_events.type")
  end
end
```

**Query cost:** one `SELECT DISTINCT noticed_events.type ...` joining noticed_notifications → noticed_events. Indexed by the existing FK and `read_at IS NULL` partial index. Same order of magnitude as the current bell `COUNT(*)`. Runs once per render of the user menu.

### Modified files

#### `app/views/shared/_notifications_bell.html.erb`

Repurposed from "wrapper + Stimulus root + frame + dropdown panel" to a slim overlay wrapped in a turbo-frame. Renders empty when zero unread.

```erb
<%# locals: (user: Current.user) -%>
<% bell_user = local_assigns.fetch(:user) { Current.user } %>
<turbo-frame id="notifications_bell_indicator_frame">
  <% severity = notification_bell_severity(bell_user) %>
  <% if severity %>
    <% colors = notification_bell_classes(severity) %>
    <span class="absolute -bottom-0.5 -right-0.5
                 flex size-4 items-center justify-center
                 rounded-full ring-2 ring-surface-raised
                 motion-safe:transition-opacity motion-safe:duration-150
                 <%= colors[:bg] %>"
          data-bell-severity="<%= severity %>"
          aria-hidden="true">
      <%= icon(:bell, style: :solid, class: "size-2.5 #{colors[:icon]}") %>
    </span>
  <% end %>
</turbo-frame>
```

#### `app/views/shared/_user_menu.html.erb`

The avatar button nests both the avatar image and the bell overlay so there's one focus target and one touch target. The "Notifications" link is wrapped in a turbo-frame and shows count when unread > 0. The button's `aria-label` becomes state-aware.

```erb
<button data-dropdown-target="button"
        data-action="click->dropdown#toggle"
        id="user-menu-button"
        aria-haspopup="true"
        aria-expanded="false"
        aria-controls="user-menu"
        aria-label="<%= avatar_button_aria_label(Current.user) %>"
        class="btn-touch-target relative rounded-full
               focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus
               cursor-pointer">
  <span id="user_avatar_header"><%= avatar_for(Current.user, size: :md) %></span>
  <%= render "shared/notifications_bell" %>
</button>
```

The Notifications menu item:

```erb
<turbo-frame id="notifications_menu_count_frame">
  <% unread = Current.user.notifications.where(read_at: nil).count %>
  <% label = unread.positive? ?
       t("navigation.notifications_with_count", count: (unread > 9 ? "10+" : unread)) :
       t("navigation.notifications") %>
  <%= link_to label, main_app.account_notifications_path,
        role: "menuitem", tabindex: "-1",
        class: "..." %>
</turbo-frame>
```

A new helper method (lives in `notification_bell_helper.rb` for cohesion with severity logic):

```ruby
def avatar_button_aria_label(user)
  unread = user.notifications.where(read_at: nil).count
  severity = notification_bell_severity(user)

  if unread.zero?
    t("navigation.user_menu_label", name: user.full_name)
  else
    t("navigation.user_menu_label_with_unread",
      name: user.full_name,
      count: unread,
      severity: t("notifications.severity.#{severity}"))
  end
end
```

#### `app/lib/notification_broadcaster.rb`

Broadcast targets change. Trio shape preserved (3 broadcasts, same rescue posture).

```ruby
def refresh_for(user, announcement_key:)
  stream_key = [user, :notifications]

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_bell_indicator_frame",
    partial: "shared/notifications_bell",
    locals: { user: user }
  )

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_menu_count_frame",
    partial: "shared/notifications_menu_count",
    locals: { user: user }
  )

  Turbo::StreamsChannel.broadcast_update_to(
    stream_key,
    target: "notifications-live",
    content: I18n.t(announcement_key)
  )
rescue StandardError => e
  Rails.logger.warn("notification broadcast failed: #{e.class}: #{e.message}")
  Rails.error.report(e, handled: true, severity: :warning,
    context: { source: "NotificationBroadcaster.refresh_for", announcement_key: announcement_key })
end
```

The count-link block is extracted to its own partial `_notifications_menu_count.html.erb` so the broadcaster has a clean `partial:` target.

#### I18n keys (`config/locales/*.yml`)

**Remove:**

- `notifications.bell.see_all`
- `notifications.bell.unread_count` (was used in dropdown header)
- `notifications.bell.unread_with_dnd` (DND tooltip surface — see open question below)

**Add:**

- `navigation.notifications_with_count: "Notifications (%{count})"`
- `navigation.user_menu_label_with_unread: "User menu for %{name}. %{count} unread notifications, highest priority: %{severity}."`
- `notifications.severity.danger`, `notifications.severity.warning`, `notifications.severity.info`, `notifications.severity.success` (human-readable severity names for the aria-label)

**Keep:** `notifications.bell.arrival_announcement`, `notifications.bell.read_state_announcement`, `notifications.bell.label`.

### Deleted files

- `app/views/shared/_notifications_dropdown.html.erb`
- `app/views/shared/_notifications_dropdown_list.html.erb`
- `app/views/shared/_notifications_bell_button.html.erb`
- `app/javascript/controllers/notification_dropdown_controller.js`
- `spec/system/notifications_dropdown_spec.rb`

---

## Accessibility (WCAG 2.2 Level AAA)

1. **Contrast.** Bell circle uses `bg-{severity}` + `text-text-on-{severity}` — same tokens toasts use, already AAA-validated in the design system. `ring-2 ring-surface-raised` separates the chip from the avatar against the header background.

2. **Single accessible name.** The avatar button's `aria-label` carries unread state. The bell overlay is `aria-hidden="true"` (default in `icon_helper.rb` when no `aria_label:` is passed) so no double-announcement.

3. **Live region preserved.** `NotificationBroadcaster` still updates `#notifications-live` polite region on every broadcast. Users who miss the visual update still hear the announcement.

4. **Touch target.** One 44×44 button. The bell overlay (`size-4` = 16px) sits inside it; the entire avatar area remains hittable.

5. **Reduced motion.** Fade transition uses the `motion-safe:` Tailwind variant — users with `prefers-reduced-motion: reduce` get no animation (snap behavior, still semantically correct).

6. **Focus indicator.** Avatar button keeps `focus:ring-2 focus:ring-interactive-focus focus:ring-offset-2` — already AAA.

---

## Edge cases

|Case|Behavior|
|---|---|
|Notifier class missing or no category set|`safe_constantize` returns nil → `:info` fallback|
|All-security + other categories|Highest rank wins (`:danger`)|
|Mark-all-as-read while user menu is open|Overlay fades out + count text updates; menu stays open|
|New notification arrives while menu open|Count link updates in place; overlay fades back in if was hidden|
|User has unread but `Noticed::Notification` row references a deleted event|`safe_constantize` returns nil → `:info` (graceful degrade, no 500)|

---

## Testing strategy

### New tests

|File|Coverage|
|---|---|
|`spec/helpers/notification_bell_helper_spec.rb`|nil with zero unread; `:info` fallback for unknown category; highest-severity-wins for mixed categories; explicit verification of each category mapping; `notification_bell_classes` returns correct token strings for every severity|
|`spec/views/shared/_notifications_bell.html.erb_spec.rb`|Empty markup when zero; `<span>` with correct `bg-*` + icon `text-*` per severity; `aria-hidden="true"` on overlay; turbo-frame wraps output|
|`spec/system/notifications_avatar_indicator_spec.rb`|Overlay appears with severity color when unread arrives; avatar click opens user menu (no dropdown panel exists in DOM); "Notifications (3)" text in menu; broadcast: dispatch a notifier via `perform_enqueued_jobs`, overlay appears without reload; mark-all-as-read → overlay disappears|

### Updated tests

|File|Change|
|---|---|
|`spec/system/notifications_a11y_spec.rb`|Replace dropdown-aria expectations with avatar-button aria-label state. Verify `aria-hidden="true"` on overlay; verify live-region still fires.|
|`spec/lib/notification_broadcaster_spec.rb`|Targets change from `notifications_bell_frame` + `notifications_dropdown_frame` to `notifications_bell_indicator_frame` + `notifications_menu_count_frame`.|
|`spec/models/notification_broadcasts_spec.rb`|Same target rename.|
|`spec/notifiers/application_notifier_spec.rb`|Update if it asserts broadcaster targets.|
|`spec/requests/account/notifications_spec.rb`|Drop any assertions about dropdown-specific responses; mark-all-as-read page behavior remains.|

### Deleted tests

- `spec/system/notifications_dropdown_spec.rb` (panel no longer exists)

---

## Open questions

### DND surface

The current bell shows a `title=` tooltip when DND is active and there are unread. With the bell collapsing into an overlay, the tooltip surface goes away. Three candidate resolutions:

1. **Include DND in the avatar `aria-label`** — `"User menu for Dave. 3 unread, do not disturb is active."` Screen-reader users get the info; sighted users discover via the preferences page.
2. **Add a DND row inside the user menu** — Visible affordance when active; takes a small permanent slot of menu height when shown.
3. **Drop the bell-side DND surface entirely** — The preferences page is the canonical home; the bell overlay doesn't need to communicate DND.

**Tentative default: option 1.** Lowest scope; preserves DND signal for AT users; doesn't pollute the menu. Confirm before implementation.

---

## What this does NOT cover

- Mobile hamburger button decoration. Mobile already collapses everything into the hamburger menu and includes "Notifications" as a link. Adding a severity dot to the hamburger button is a possible parity extension but is **out of scope** for this spec.
- Per-category color customization. Severity mapping is fixed by category at the helper level.
- Animation beyond a 150ms fade. No spring physics, no bouncy attention-grab. Subtle by design.
- Reworking the `/account/notifications` page itself. That page is the only path now but its layout/UX is unchanged.

---

## Verification

1. Run the full RSpec suite — 0 failures. (Lefthook pre-push enforces this.)
2. Run axe diagnostic on the header for both zero-unread and 3-unread-with-security states — 0 AAA violations.
3. Visual check in light + dark mode: avatar with no bell, avatar with each of the four severity colors.
4. Live-broadcast check: open two browser tabs, dispatch a notification from the console, confirm overlay appears in both tabs without reload.
5. Reduced-motion check: enable OS-level reduced motion, dispatch notification, confirm snap behavior (no fade) but overlay still appears correctly.
