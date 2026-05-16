# Avatar-Overlaid Notification Indicator — Design Spec

**Goal:** Replace the standalone header bell + dropdown with a small solid bell glyph that sits at the bottom-right of the user avatar (per Tailwind Plus's "circular avatars with bottom notification" pattern). Color reflects the highest-severity unread notification (severity is now declared by each notifier). The avatar continues to open the user menu; the menu's "Notifications" link shows the count and is the only path to the notifications page.

**Scope:** UI compression of the header notification surface. Removes one full dropdown panel + Stimulus controller. Introduces a `severity` DSL on `ApplicationNotifier` (parallel to existing `category`), a single grouped query on User, and a slim helper for view-token mapping. ~4 files deleted, ~14 modified (mostly +1 line per notifier), ~3 added.

**Revision history:** v2 reflects panel review feedback (DHH, Jorge Manrubia, Adam Wathan, Léonie Watson, Steve Schoger, Dave Thomas) and incorporates all previously-deferred items.

---

## Problem

The current header reserves two side-by-side 44×44 affordances:

1. A standalone bell (notifications dropdown trigger).
2. The avatar (user-menu trigger).

The bell consumes ~52px of horizontal space on every page even when there are zero unread notifications. The dropdown panel duplicates a path that already exists (`/account/notifications`), and the two adjacent triggers add visual weight in a header that should be quiet.

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

### Severity is declared per-notifier

Severity is **declared by each notifier**, alongside its existing `category`. The two concerns are orthogonal:

- `category` answers "what kind of thing is this for opt-in/opt-out purposes?" (drives preferences UI)
- `severity` answers "how alarming is this?" (drives bell color)

```ruby
class PasswordChangedNotifier < ApplicationNotifier
  category :security
  severity :danger
end
```

Default severity (when a notifier doesn't declare one) is `:info`. The mapping no longer lives in a central constant in the helper; the notifier itself is the source of truth.

### Severity → color tokens

|Severity|Bell `bg-*`|Bell icon `text-*`|
|---|---|---|
|`danger`|`bg-danger`|`text-danger-icon`|
|`warning`|`bg-warning`|`text-warning-icon`|
|`info`|`bg-info`|`text-info-icon`|
|`success`|`bg-success`|`text-success-icon`|

These match the toast severity tokens already registered in `app/assets/tailwind/tokens/_signals.css` and used by `config/initializers/toasts.rb`. Already AAA-validated.

### Severity assignments per concrete notifier

|Notifier|Category|Severity|
|---|---|---|
|`PasswordChangedNotifier`|`security`|`danger`|
|`SignInFromNewDeviceNotifier`|`security`|`danger`|
|`WorkspaceCapacityApproachingNotifier`|`billing`|`warning`|
|`WorkspaceInvitationExpiringSoonNotifier`|`account_access`|`warning`|
|`WorkspaceInvitationReceivedNotifier`|`account_access`|`info`|
|`WorkspaceInvitationResentNotifier`|`account_access`|`info`|
|`WorkspaceRoleChangedNotifier`|`account_access`|`info`|
|`WorkspaceMemberAddedNotifier`|`workspace_activity`|`success`|
|`WorkspaceInvitationAcceptedNotifier`|`workspace_activity`|`success`|
|`WorkspaceInvitationDeclinedNotifier`|`workspace_activity`|`info`|
|`ProjectMembershipChangedNotifier`|`project_activity`|`info`|

When multiple severities are present in the unread set, **highest wins**. Rank: `danger > warning > info > success`.

---

## Architecture

### New files

- `app/helpers/notification_bell_helper.rb` — view-token mapping and aria-label composition.
- `app/views/shared/_user_menu_avatar_button.html.erb` — slim partial: just the `<button>` element. Used inline AND as a broadcast target.
- `app/views/shared/_notifications_menu_count_span.html.erb` — slim partial: just the count `<span>` (empty when zero). Used inline AND as a broadcast target.

### Modified files

#### `app/notifiers/application_notifier.rb`

Add a `severity` DSL parallel to the existing `category`. Default `:info`.

```ruby
class ApplicationNotifier < Noticed::Event
  class_attribute :category_name, instance_accessor: false
  class_attribute :severity_name, instance_accessor: false, default: :info

  def self.category(name)
    self.category_name = name.to_s
  end

  def self.severity(name)
    self.severity_name = name.to_sym
  end

  # ...rest unchanged
end
```

#### Each of the 11 concrete notifiers (one added line each)

```ruby
class PasswordChangedNotifier < ApplicationNotifier
  category :security
  severity :danger
  # ...
end
```

Full assignments listed in the "Severity assignments" table above.

#### `app/models/user.rb`

A grouped query that returns both count and severity-source data in one DB hit.

```ruby
# Returns { notifier_class_name => unread_count, ... }
# Used by the bell indicator and user-menu count.
def unread_notification_breakdown
  notifications
    .where(read_at: nil)
    .joins("INNER JOIN noticed_events ON noticed_events.id = noticed_notifications.event_id")
    .group("noticed_events.type")
    .count
end
```

One indexed grouped query replaces today's two separate queries (the bell's COUNT and a separate distinct-types lookup).

#### `app/helpers/notification_bell_helper.rb`

The helper now owns **only view concerns**: rank, class tokens, and orchestration that resolves user-menu state from the User-owned breakdown.

```ruby
module NotificationBellHelper
  SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }.freeze

  SEVERITY_CLASSES = {
    danger:  { bg: "bg-danger",  icon: "text-danger-icon"  },
    warning: { bg: "bg-warning", icon: "text-warning-icon" },
    info:    { bg: "bg-info",    icon: "text-info-icon"    },
    success: { bg: "bg-success", icon: "text-success-icon" }
  }.freeze

  # Returns { count:, severity: }. severity is nil when count is zero.
  def unread_notification_summary(user)
    breakdown = user.unread_notification_breakdown
    return { count: 0, severity: nil } if breakdown.empty?

    count = breakdown.values.sum
    severity = breakdown.keys
      .map { resolve_severity_for(_1) }
      .max_by { SEVERITY_RANK.fetch(_1) }

    { count: count, severity: severity }
  end

  def notification_bell_classes(severity)
    SEVERITY_CLASSES.fetch(severity, SEVERITY_CLASSES[:info])
  end

  def avatar_button_aria_label(user, summary = unread_notification_summary(user))
    if summary[:count].zero?
      t("navigation.user_menu_label", name: user.full_name)
    else
      t("navigation.user_menu_label_with_unread",
        name: user.full_name,
        count: summary[:count],
        phrase: t("notifications.severity_phrase.#{summary[:severity]}"))
    end
  end

  private

  def resolve_severity_for(notifier_class_name)
    case notifier_class_name.safe_constantize
    in nil
      Rails.logger.warn("Stale notifier class in unread notifications: #{notifier_class_name}")
      :info
    in notifier_class
      notifier_class.severity_name || :info
    end
  end
end
```

Pattern-matched fallback explicitly handles the three states: deleted class (logs + degrades), missing severity (defaults), declared severity.

#### `app/views/shared/_notifications_bell.html.erb`

The overlay partial. Renders empty when severity is nil.

```erb
<%# locals: (user: Current.user) -%>
<% bell_user = local_assigns.fetch(:user) { Current.user } %>
<% summary = unread_notification_summary(bell_user) %>
<turbo-frame id="notifications_bell_indicator_frame">
  <% if summary[:severity] %>
    <% colors = notification_bell_classes(summary[:severity]) %>
    <span class="absolute -bottom-0.5 -right-0.5
                 flex size-4 items-center justify-center
                 rounded-full ring-2 ring-surface-raised
                 motion-safe:transition-opacity motion-safe:duration-150
                 <%= colors[:bg] %>
                 <%= "motion-safe:animate-pulse-danger" if summary[:severity] == :danger %>"
          data-bell-severity="<%= summary[:severity] %>"
          aria-hidden="true">
      <%= icon(:bell, style: :solid, class: "size-2.5 #{colors[:icon]}") %>
    </span>
  <% end %>
</turbo-frame>
```

The `motion-safe:animate-pulse-danger` is a subtle attention signal restricted to `:danger`. A 3-second opacity cycle (100% → 70% → 100%). Suppressed under `prefers-reduced-motion: reduce`.

Custom animation registered via `@theme` (the canonical v4 pattern Tailwind itself uses for `animate-pulse`, `animate-spin`, etc.). Lives in `app/assets/tailwind/application.css`:

```css
@theme {
  --animate-pulse-danger: pulse-danger 3s ease-in-out infinite;
}

@keyframes pulse-danger {
  0%, 100% { opacity: 1; }
  50%      { opacity: 0.7; }
}
```

Tailwind auto-generates the `animate-pulse-danger` utility from the `--animate-*` theme variable. No separate `@utility` declaration needed.

#### `app/views/shared/_user_menu_avatar_button.html.erb` (new slim partial)

Just the avatar button. Used both inline in `_user_menu.html.erb` (initial render) and as the broadcaster's `partial:` target.

```erb
<%# locals: (user:) -%>
<button data-dropdown-target="button"
        data-action="click->dropdown#toggle"
        id="user-menu-button"
        aria-haspopup="true"
        aria-expanded="false"
        aria-controls="user-menu"
        aria-label="<%= avatar_button_aria_label(user) %>"
        class="btn-touch-target relative rounded-full
               focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus
               cursor-pointer">
  <span id="user_avatar_header"><%= avatar_for(user, size: :md) %></span>
  <%= render "shared/notifications_bell", user: user %>
</button>
```

#### `app/views/shared/_notifications_menu_count_span.html.erb` (new slim partial)

Just the count span. Empty when zero. Used inline AND as a broadcast target.

```erb
<%# locals: (user:) -%>
<% summary = unread_notification_summary(user) %>
<% if summary[:count].positive? %>
  <span class="ml-1 text-text-muted">
    (<%= summary[:count] > 9 ? "10+" : summary[:count] %>)
  </span>
<% end %>
```

#### `app/views/shared/_user_menu.html.erb`

The avatar button is now wrapped in a turbo-frame for fresh aria-label broadcasts. The Notifications link wraps just its count span in a frame.

```erb
<%# desktop avatar trigger %>
<turbo-frame id="notifications_avatar_button_frame">
  <%= render "shared/user_menu_avatar_button", user: Current.user %>
</turbo-frame>

<%# inside the dropdown menu %>
<%= link_to main_app.account_notifications_path,
      role: "menuitem", tabindex: "-1",
      class: "..." do %>
  <%= t("navigation.notifications") %>
  <turbo-frame id="notifications_menu_count_frame">
    <%= render "shared/notifications_menu_count_span", user: Current.user %>
  </turbo-frame>
<% end %>
```

The mobile (hamburger) Notifications link gets the same count span inline (without the frame — broadcasts don't reach mobile since the menu is closed-by-default and reloads on open).

#### `app/lib/notification_broadcaster.rb`

The trio becomes a quartet — avatar button gets its own broadcast so its `aria-label` stays fresh.

```ruby
def refresh_for(user, announcement_key:)
  stream_key = [user, :notifications]

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_avatar_button_frame",
    partial: "shared/user_menu_avatar_button",
    locals: { user: user }
  )

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_bell_indicator_frame",
    partial: "shared/notifications_bell",
    locals: { user: user }
  )

  Turbo::StreamsChannel.broadcast_replace_to(
    stream_key,
    target: "notifications_menu_count_frame",
    partial: "shared/notifications_menu_count_span",
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

#### I18n keys (`config/locales/*.yml`)

**Remove:**

- `notifications.bell.see_all`
- `notifications.bell.unread_count`
- `notifications.bell.unread_with_dnd`

**Add (sensible English defaults; per-locale overrides as needed):**

```yaml
en:
  navigation:
    user_menu_label_with_unread: "User menu for %{name}. %{count} unread notifications, including %{phrase}."
  notifications:
    severity_phrase:
      danger: "a security alert"
      warning: "an important update"
      info: "an account update"
      success: "a workspace update"
```

Phrase reads naturally: *"User menu for Dave. 3 unread notifications, including a security alert."* Localizers can override per-locale without code changes.

**Keep:** `notifications.bell.arrival_announcement`, `notifications.bell.read_state_announcement`, `notifications.bell.label`, `navigation.user_menu_label`, `navigation.notifications`.

### Deleted files

- `app/views/shared/_notifications_dropdown.html.erb`
- `app/views/shared/_notifications_dropdown_list.html.erb`
- `app/views/shared/_notifications_bell_button.html.erb`
- `app/javascript/controllers/notification_dropdown_controller.js`
- `spec/system/notifications_dropdown_spec.rb`

---

## Accessibility (WCAG 2.2 Level AAA)

1. **Contrast.** Bell circle uses `bg-{severity}` + `text-{severity}-icon` — same tokens toasts use, already AAA-validated in `_signals.css`. `ring-2 ring-surface-raised` separates the chip from the avatar against the header background.

2. **Single accessible name, broadcast-fresh.** The avatar button's `aria-label` carries unread state. The button is wrapped in `notifications_avatar_button_frame`, so on every broadcast the label re-renders with the current count + severity phrase. AT users hear the live-region announcement immediately AND find a freshly-named button on their next focus traversal — no narrative lag.

3. **Live region preserved.** `NotificationBroadcaster` still updates `#notifications-live` polite region on every broadcast. Polite queue handles bursty arrivals gracefully (no debounce needed).

4. **Touch target.** One 44×44 button. The bell overlay (`size-4` = 16px) sits inside it; the entire avatar area remains hittable.

5. **Reduced motion.** Both the fade transition and the danger pulse use `motion-safe:` prefixes — users with `prefers-reduced-motion: reduce` get static behavior (correct semantically; just no animation).

6. **Focus indicator.** Avatar button keeps `focus:ring-2 focus:ring-interactive-focus focus:ring-offset-2` — already AAA.

7. **Severity phrasing is i18n-driven.** The aria-label uses natural-language phrases (`"a security alert"`) rather than developer-facing tokens (`"danger"`). Defaults ship in English; localizers override per-locale.

8. **DND is not surfaced on the bell.** Do Not Disturb governs *delivery channels* (email, push) — it does not suppress in-app bell appearance, severity color, count, or live-region announcement. Since DND doesn't change what the bell does, the bell doesn't mention it. The notification preferences page is the canonical home for DND state. (See "Resolved decisions" below.)

---

## Known limitations

### aria-live coalescing under burst

The notifications live region is `aria-live="polite" aria-atomic="true"`.
Under rapid arrival (e.g., 5 notifications in 2 seconds), the polite queue
does NOT enqueue each `broadcast_update_to` call separately — the
attribute change rapidly overwrites itself, and AT will read only the
final state when it next gets a chance.

Practical effect: a burst of 5 arrivals likely produces 1–2 SR
announcements ("New notification"), not 5. The visual surfaces (bell
color, count text) and the avatar's `aria-label` still reflect all 5
events, so users with sight still see the accurate count and severity.

If precise per-event SR signaling becomes important, coalesce into a
counted announcement ("5 new notifications") instead of repeating
"New notification" verbatim — or move to `aria-live="assertive"` with a
debounced message (more interruptive but more reliable for high
volumes). Today's tradeoff favors the non-disruptive polite queue
because the visual surfaces already convey volume.

## Edge cases

|Case|Behavior|
|---|---|
|Notifier missing `severity` declaration|Defaults to `:info` via `class_attribute` default|
|All-security + other categories|Highest rank wins (`:danger`)|
|Mark-all-as-read while user menu is open|Overlay fades out + count span empties; menu stays open; avatar button re-renders with zero-state aria-label|
|New notification arrives while menu open|Count span updates; overlay fades back in if hidden; avatar button aria-label refreshes|
|`Noticed::Notification` references a deleted notifier class|`safe_constantize` returns nil → logs warning → `:info` (graceful degrade)|
|Multiple unread of same notifier class|`GROUP BY type` collapses to single row with count; severity unchanged|
|Burst of 5 notifications in 2 seconds|Each broadcast replaces frames atomically; polite live-region queue paces announcements naturally|

---

## Testing strategy

### New tests

|File|Coverage|
|---|---|
|`spec/helpers/notification_bell_helper_spec.rb`|`unread_notification_summary` returns zero/nil with no unread; highest-severity-wins for mixed severities; defaults to `:info` when notifier severity is unset; `resolve_severity_for` logs warning and returns `:info` when class missing; `notification_bell_classes` returns correct token strings; `avatar_button_aria_label` composes the i18n phrase correctly for each severity|
|`spec/models/user_spec.rb` (additions)|`unread_notification_breakdown` returns `{ notifier_type => count }` grouped correctly; empty hash with zero unread; respects `read_at IS NULL`; collapses duplicates from same notifier class|
|`spec/notifiers/application_notifier_spec.rb` (additions)|`severity :danger` sets `severity_name`; default is `:info`; each subclass owns its declaration (no leakage)|
|`spec/notifiers/<each notifier>_spec.rb` (additions)|Verify the declared severity for each of the 11 notifiers matches the assignment table|
|`spec/views/shared/_notifications_bell.html.erb_spec.rb`|Empty markup when zero; `<span>` with correct `bg-*` + `text-{severity}-icon` per severity; `aria-hidden="true"`; `animate-pulse-danger` class only on `:danger`; turbo-frame wraps output|
|`spec/views/shared/_user_menu_avatar_button.html.erb_spec.rb`|Renders button with state-aware aria-label; includes nested bell partial; sole content of the avatar frame|
|`spec/system/notifications_avatar_indicator_spec.rb`|Overlay appears with correct severity color; avatar click opens user menu (verify no dropdown panel in DOM); "Notifications (3)" text in menu; broadcast via `perform_enqueued_jobs`: overlay appears AND avatar button aria-label updates AND count span updates without reload; mark-all-as-read → overlay disappears AND aria-label drops unread phrase; rapid-fire burst handled without DOM corruption|

### Updated tests

|File|Change|
|---|---|
|`spec/system/notifications_a11y_spec.rb`|Replace dropdown-aria expectations with avatar-button aria-label state; verify aria-label refreshes via broadcast and matches the i18n severity phrase; verify stale notifier class doesn't crash render|
|`spec/lib/notification_broadcaster_spec.rb`|Targets change to `notifications_avatar_button_frame`, `notifications_bell_indicator_frame`, `notifications_menu_count_frame`, `notifications-live` (now 4 broadcasts)|
|`spec/models/notification_broadcasts_spec.rb`|Same target rename|
|`spec/requests/account/notifications_spec.rb`|Drop dropdown-specific response assertions; mark-all-as-read page behavior remains|

### Deleted tests

- `spec/system/notifications_dropdown_spec.rb`

---

## Resolved decisions

### DND is not surfaced on the bell

The current bell shows a `title=` tooltip when DND is active and there are unread. **That behavior does not carry over.**

Rationale: DND governs delivery channels (email, push), not in-app bell appearance. The bell still shows severity, count, and live-region announcement under DND. Since DND doesn't change what the bell does in the new design, adding a "DND is on" surface to the bell would be noise about a preference the user already set. The notification preferences page is the canonical home.

If a future change makes DND actually suppress something on the bell (e.g., silencing the live-region announcement for non-security categories), revisit this decision.

Removed from i18n: `notifications.bell.unread_with_dnd` (already listed in the I18n removal section).

---

## What this does NOT cover

- **Mobile hamburger button decoration.** Mobile collapses everything into the hamburger menu which already includes "Notifications". Adding a severity dot to the hamburger button is a possible parity extension but is **out of scope**.
- **Animation on severities below danger.** The 3-second pulse is restricted to `:danger`. Lower severities use the 150ms fade-in on appearance and nothing else.
- **Reworking `/account/notifications`.** That page is the only path now but its UX is unchanged.

---

## Verification

1. Run the full RSpec suite — 0 failures. (Lefthook pre-push enforces this.)
2. Run axe diagnostic on the header for zero-unread plus each of the four severity states — 0 AAA violations.
3. Visual check in light + dark mode: zero-state plus each severity color.
4. Live-broadcast check: open two browser tabs, dispatch a notification, confirm overlay + aria-label + menu count all update without reload.
5. Reduced-motion check: enable OS-level reduced motion, confirm no fade and no pulse, but overlay still appears correctly.
6. **Severity declaration audit:** in `rails console`, `ApplicationNotifier.descendants.each { |c| puts "#{c.name}: #{c.severity_name}" }` and verify all 11 notifiers match the assignment table.
7. **Stale-class graceful degrade:** rename a notifier class, leave `Noticed::Notification` rows pointing at the old name, confirm bell renders as `:info` and a warning lands in logs.
