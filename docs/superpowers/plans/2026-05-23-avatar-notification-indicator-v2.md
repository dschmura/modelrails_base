# Avatar Notification Indicator v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the bell-on-avatar pattern (lost in D1) as a calm severity-colored *indicator dot* (not a bell glyph), co-located with the identity surface on both desktop (avatar bottom-right) and mobile (hamburger button). Remove the standalone header bell. Single canonical triage entry point: a new "Notifications" item inside the user menu dropdown.

**Architecture:** New `_notifications_indicator.html.erb` shared partial renders the dot as a *positioned sibling* of the focusable button's image content (not inside its accessible-name path) — this is the engineering pattern that preserves D1's accessibility fix while restoring the badge UX. Two turbo-frames (`notifications_indicator_avatar`, `notifications_indicator_hamburger`) carry the same partial render and update together on every notification broadcast. A third frame (`notifications_menu_count_frame`) updates the `[N new]` count badge inside the user menu Notifications row, which is the in-menu live-region that AT users hear when they open the menu.

**Tech Stack:** Rails 8.1, Ruby 4.0.4, TailwindCSS 4 with semantic tokens (`--color-danger-*`, `--color-warning-*`, `--color-info-*`), Stimulus (no new controllers — the existing dropdown + theme-toggle controllers cover this), Turbo Streams for the broadcast, RSpec + Capybara/Playwright, axe-core WCAG 2.2 AAA.

**Spec:** `docs/superpowers/specs/2026-05-23-avatar-notification-indicator-v2-design.md` (Approved 2026-05-23).

**Supersedes (engineering posture):** `2026-05-15-avatar-bell-notification-indicator-design.md` (D1). D1's a11y lesson is preserved by the positioned-sibling pattern; D1's broadcast-frame-inside-button trap is avoided.

**Branch:** `feat/avatar-notification-indicator-v2` off `main`.

**Pre-task baseline:** Verify 1945 / 0 on `main` before starting (this is post-#165 / post-chevron-merge).

**Tasks (8):**

1. Locale keys — Notifications menuitem label + count strings
2. `:dot` variant on `notification_bell_classes` helper + helper spec
3. `_notifications_indicator.html.erb` shared partial + view spec
4. Integrate indicator into avatar wrapper (`_user_menu_avatar_button.html.erb`)
5. Integrate indicator into hamburger button (`_header.html.erb`)
6. User menu Notifications menuitem + `notifications_menu_count_frame`
7. Broadcast frame rename + broadcasting code path update
8. Removal pass — delete `_notifications_bell_link.html.erb`, `_notifications_bell.html.erb`, `_notifications_bell_label.html.erb` and their specs; remove the header render; final system + axe coverage

---

## File Structure

**Create:**

- `app/views/shared/_notifications_indicator.html.erb` — the shared dot partial (locals: `summary:, surface:`)
- `spec/views/shared/_notifications_indicator.html.erb_spec.rb` — view spec
- `spec/system/notifications/avatar_indicator_v2_spec.rb` — end-to-end coverage (live updates + axe AAA both themes)

**Modify:**

- `app/helpers/notification_bell_helper.rb` — add `:dot` variant to `notification_bell_classes`
- `app/views/shared/_user_menu_avatar_button.html.erb` — avatar span becomes `relative inline-flex`, indicator renders inside
- `app/views/shared/_header.html.erb` — hamburger button becomes `relative`, indicator renders inside; remove `notifications_bell_link` render
- `app/views/shared/_user_menu.html.erb` — new Notifications menuitem between identity block and "All workspaces" (both desktop + mobile contexts)
- `app/lib/notification_broadcaster.rb` — broadcast targets renamed (`notifications_indicator_avatar`, `notifications_indicator_hamburger`, `notifications_menu_count_frame`)
- `config/locales/en/application.en.yml` — Notifications menuitem labels + count i18n keys
- `CHANGELOG.md` — Changed entry

**Delete (final task):**

- `app/views/shared/_notifications_bell_link.html.erb`
- `app/views/shared/_notifications_bell.html.erb`
- `app/views/shared/_notifications_bell_label.html.erb`
- `spec/views/shared/_notifications_bell_link.html.erb_spec.rb`
- Any `notifications_bell_*_frame` references in remaining specs

---

## Task 1: Locale keys — Notifications menuitem label + count strings

**Files:**

- `config/locales/en/application.en.yml` — add
  - `navigation.notifications` → "Notifications"
  - `navigation.notifications_count.zero` → ""
  - `navigation.notifications_count.one` → "1 new"
  - `navigation.notifications_count.other` → "%{count} new"
  - `navigation.notifications_count_aria.one` → "1 unread notification"
  - `navigation.notifications_count_aria.other` → "%{count} unread notifications"

**Steps:**

- [ ] Add keys to `config/locales/en/application.en.yml` under existing `navigation:` namespace
- [ ] Verify with `rails t i18n.t("navigation.notifications")` — returns "Notifications", no MissingTranslationException
- [ ] Run full suite; expect 1945 / 0 (locale additions should not affect existing specs)
- [ ] Commit: `feat(i18n): locale keys for avatar notification indicator v2 (Task 1)`

**Acceptance:** Keys present and Rails returns the right values for each pluralization.

---

## Task 2: `:dot` variant on `notification_bell_classes` helper

**Files:**

- `app/helpers/notification_bell_helper.rb` — add `:dot` variant
- `spec/helpers/notification_bell_helper_spec.rb` — augment

**Implementation contract (from spec):**

```ruby
notification_bell_classes(severity, variant: :dot)
# returns { bg: "<bg color class>", pulse: <true/false> }
# severity ∈ [:danger, :warning, :info]
```

**Steps:**

- [ ] Add a failing helper spec for each severity → expected `bg:` token + `pulse:` bool
  - `:danger` → `bg: "bg-danger-strong"`, `pulse: true`
  - `:warning` → `bg: "bg-warning-strong"`, `pulse: false`
  - `:info` → `bg: "bg-info-strong"`, `pulse: false`
- [ ] Add the `:dot` variant branch in `notification_bell_classes`
- [ ] Run the helper spec — green
- [ ] Run full suite; expect 1945+ / 0
- [ ] Commit: `feat(helpers): add :dot variant to notification_bell_classes (Task 2)`

**Acceptance:** Helper returns the right tokens for all three severities under `:dot` variant. Existing `:icon` variant still works (we retire it in Task 8, not now).

---

## Task 3: `_notifications_indicator.html.erb` shared partial

**Files:**

- `app/views/shared/_notifications_indicator.html.erb` — new
- `spec/views/shared/_notifications_indicator.html.erb_spec.rb` — new

**Partial contract:**

```erb
<%# locals: (summary:, surface: :avatar) -%>
<%# Severity-colored indicator dot. surface picks the position class.
    Renders an empty placeholder when summary[:severity] is nil so the
    surrounding turbo-frame still has stable content. %>
```

**Steps:**

- [ ] Write failing view spec covering:
  - Renders nothing visible when `summary[:severity]` is nil
  - Renders a `w-2 h-2 rounded-full` span with the correct severity bg class for each of `:danger` / `:warning` / `:info`
  - Adds `motion-safe:animate-pulse` only when severity = `:danger`
  - Has `aria-hidden="true"` regardless of severity
  - Picks `absolute -bottom-0.5 -right-0.5` for `surface: :avatar`
  - Picks `absolute top-0.5 right-0.5` for `surface: :hamburger` (matches the hamburger icon's visual centroid)
  - Includes the drop-shadow halo for visibility on arbitrary backgrounds
  - Includes the `forced-colors:bg-[Highlight]` fallback for HCM
  - Includes the `motion-safe:transition-opacity motion-safe:duration-150` for fade-out
- [ ] Implement the partial
- [ ] Run view spec — green
- [ ] Run full suite — green
- [ ] Commit: `feat(views): shared notifications indicator partial (Task 3)`

**Acceptance:** All view-spec assertions pass; partial renders correctly for both surfaces and both severity-present / severity-absent states.

---

## Task 4: Integrate indicator into avatar wrapper

**Files:**

- `app/views/shared/_user_menu_avatar_button.html.erb` — wrap avatar in `relative inline-flex` span, render indicator inside
- `spec/views/shared/_user_menu_avatar_button.html.erb_spec.rb` — augment

**Steps:**

- [ ] Add failing assertion to the view spec:
  - Avatar wrapper (`#user_avatar_header`) has `relative` class (anchors the absolutely-positioned dot)
  - Indicator partial is rendered inside the wrapper as a sibling of the avatar image (not wrapping it, not inside its accessible-name path)
  - When `Current.user` has unread danger-severity notifications, the indicator renders with the danger bg class
  - When `Current.user` has no unread notifications, the wrapper still has `relative` but the indicator renders empty
  - Avatar button's static `aria-label` is unchanged from chevron-merge state
- [ ] Modify the partial: avatar `<span id="user_avatar_header">` gains `relative inline-flex`; render `_notifications_indicator` as a sibling of the avatar image inside the span
- [ ] Run the partial's view spec — green (7 existing + new assertions all pass)
- [ ] Run system specs that touch the avatar trigger:
  - `spec/system/user_menu_spec.rb`
  - `spec/system/notifications_a11y_spec.rb`
  - `spec/requests/user_menu_spec.rb`
- [ ] Run full suite — green
- [ ] Commit: `feat(views): notifications indicator on avatar (Task 4)`

**Acceptance:** Avatar carries the dot when unread, dropdown still opens correctly, dot doesn't affect the avatar's 44×44px touch target.

---

## Task 5: Integrate indicator into hamburger button

**Files:**

- `app/views/shared/_header.html.erb` — hamburger button becomes `relative`, indicator renders inside
- `spec/views/shared/_header.html.erb_spec.rb` — new if absent, augment if present

**Steps:**

- [ ] Confirm whether `spec/views/shared/_header.html.erb_spec.rb` exists. If not, create with baseline assertions (logo, right-cluster structure, hamburger button presence + aria-label).
- [ ] Add failing assertion:
  - Hamburger button class list contains `relative`
  - Indicator partial (`surface: :hamburger`) renders inside the hamburger button
  - When `Current.user` has unread, the dot renders with severity bg class
- [ ] Modify the hamburger button in `_header.html.erb`: add `relative` to class, render `_notifications_indicator, summary:, surface: :hamburger` as a sibling of the bars icon
- [ ] Run view spec — green
- [ ] Run system spec for mobile menu (search for `data-mobile-menu-target="button"` system specs) to confirm hamburger toggle still works
- [ ] Run full suite — green
- [ ] Commit: `feat(views): notifications indicator on hamburger button (Task 5)`

**Acceptance:** Hamburger carries the dot when unread. Mobile menu toggles correctly. Dot positioned at the hamburger's top-right per the partial.

---

## Task 6: User menu Notifications menuitem

**Files:**

- `app/views/shared/_user_menu.html.erb` — add Notifications menuitem between identity block and "All workspaces" (both desktop + mobile contexts)
- `spec/views/shared/_user_menu_spec.rb` — augment (or `spec/system/user_menu_spec.rb` if view spec doesn't exist)

**Markup contract (desktop context):**

```erb
<%# Inside the dropdown menu, between identity block and "All workspaces": %>
<turbo-frame id="notifications_menu_count_frame">
  <%= link_to main_app.account_notifications_path,
        role: "menuitem", tabindex: "-1",
        data: { turbo_prefetch: "true" },
        class: "flex items-center justify-between gap-3 px-4 py-3
                hover:bg-surface focus:outline-none focus:bg-surface
                focus:ring-2 focus:ring-inset focus:ring-interactive-focus" do %>
    <span class="flex items-center gap-3">
      <%= icon(:bell, size: :sm) %>
      <span class="text-sm text-text-body"><%= t("navigation.notifications") %></span>
    </span>
    <% if summary[:total]&.positive? %>
      <span class="text-xs font-medium text-text-muted"
            aria-live="polite"
            aria-label="<%= t("navigation.notifications_count_aria", count: summary[:total]) %>">
        <%= t("navigation.notifications_count", count: summary[:total]) %>
      </span>
    <% end %>
  <% end %>
</turbo-frame>
```

**Steps:**

- [ ] Add failing assertion to user-menu spec:
  - Notifications menuitem rendered between identity block and "All workspaces" in the dropdown
  - Menuitem links to `account_notifications_path`
  - Menuitem icon is the `:bell` glyph
  - Count badge inside the menuitem reads `[N new]` when unread > 0 and is absent when unread = 0
  - Count span has `aria-live="polite"` and the full `aria-label` (so AT announces "Notifications, 3 unread notifications")
  - The menuitem is wrapped in `notifications_menu_count_frame` so broadcasts can swap the count without re-rendering the whole menu
- [ ] Implement in `_user_menu.html.erb` for both desktop + mobile contexts
- [ ] Run user-menu specs — green
- [ ] Run full suite — green
- [ ] Commit: `feat(views): notifications menuitem in user menu (Task 6)`

**Acceptance:** Users open the user menu and see a Notifications row with the count badge. AT announces the count via the live region. Hovering / focusing the menuitem works correctly within keyboard nav.

---

## Task 7: Broadcast frame rename + broadcasting code path update

**Files:**

- `app/lib/notification_broadcaster.rb` — update broadcast targets
- `spec/lib/notification_broadcaster_spec.rb` — update
- `spec/models/notification_broadcasts_spec.rb` — update (broadcast frame ID assertions)

**Frame ID migration:**

| D1 frame ID | v2 frame ID | Renders |
| --- | --- | --- |
| `notifications_bell_indicator_frame` | `notifications_indicator_avatar` | `_notifications_indicator, surface: :avatar` |
| (none — new) | `notifications_indicator_hamburger` | `_notifications_indicator, surface: :hamburger` |
| `notifications_bell_label_frame` | (retired — static aria-label on buttons) | — |
| (existing) | `notifications_menu_count_frame` | the user-menu Notifications row |

**Steps:**

- [ ] Update broadcasting code to target all three v2 frames in a single broadcast pass (one `broadcast_replace` per frame; cheap, same data)
- [ ] Update broadcaster specs to assert on the v2 frame IDs
- [ ] Update notification-arrival broadcast tests to confirm both indicator frames update in lockstep
- [ ] Run broadcaster + model specs — green
- [ ] Run full suite — green
- [ ] Commit: `feat(broadcasts): rename notification frames + dual indicator targets (Task 7)`

**Acceptance:** A new notification event fires → both indicator frames update simultaneously (avatar dot + hamburger dot) + the user-menu count updates. No reload required.

---

## Task 8: Removal pass + system spec + axe AAA coverage

**Files (delete):**

- `app/views/shared/_notifications_bell_link.html.erb`
- `app/views/shared/_notifications_bell.html.erb`
- `app/views/shared/_notifications_bell_label.html.erb`
- `spec/views/shared/_notifications_bell_link.html.erb_spec.rb`

**Files (modify):**

- `app/views/shared/_header.html.erb` — remove the `render "shared/notifications_bell_link"` call
- `app/helpers/notification_bell_helper.rb` — retire `:icon` variant (now unused) **only if no other call sites remain**; otherwise leave for follow-up

**Files (create):**

- `spec/system/notifications/avatar_indicator_v2_spec.rb` — new

**System spec coverage:**

- Unauthenticated: no indicator on either surface, no hamburger dot
- Authenticated + 0 unread: no indicator on either surface
- Authenticated + 1 info-severity unread: both indicators visible, info-colored
- Authenticated + 1 danger-severity unread: both indicators visible, pulsing (motion-safe), danger-colored
- Live broadcast: a new notification arrives → both frames update without page reload
- Mark all read: both indicators fade-out (motion-safe) when count → 0
- AAA contrast verification via axe at each severity, both themes (light + dark), both indicators
- Regression guard: no `notifications_bell_indicator_frame`, no `notifications_bell_label_frame`, no standalone bell link anywhere in the rendered page

**Steps:**

- [ ] Write the new system spec; expect it to fail initially because the old bell partials are still referenced
- [ ] Remove the standalone bell render from `_header.html.erb`
- [ ] Delete the three old partials
- [ ] Delete the old bell-link view spec
- [ ] Grep for any remaining `notifications_bell_indicator_frame` / `notifications_bell_label_frame` / `_notifications_bell_link` / `_notifications_bell` references; update or remove
- [ ] Run new system spec — green
- [ ] Run full suite — expect ~1955 / 0 (new partial + helper + system specs added, old bell-link specs removed)
- [ ] Run `bundle exec rake erb:check` — 0 offenses
- [ ] CHANGELOG entry under `[Unreleased]` / Changed: "Avatar notification indicator restored as severity-colored dot; standalone header bell removed; in-menu Notifications link is the canonical triage entry point."
- [ ] Commit: `feat(views): remove standalone bell, ship indicator v2 + system coverage (Task 8)`

**Acceptance:**

- Both indicators (avatar + hamburger) work end-to-end
- Old bell partials are gone; no orphan references
- System spec confirms AAA contrast on every severity / theme combination
- Lefthook pre-push gauntlet is clean (brakeman + erb_lint + rspec + rubocop + tailwind_build)

---

## Verification (final, post-Task 8)

Before opening the PR:

- [ ] `mise exec -- bundle exec rspec` → 0 failures
- [ ] `mise exec -- bundle exec rake erb:check` → 0 offenses (1 intentional disable on the cropper carries forward; nothing new)
- [ ] Manual browser check on `bin/dev`:
  - Desktop: avatar shows dot at each severity color (red/amber/blue), pulses on danger only
  - Desktop: standalone bell is gone; clicking the avatar opens the menu; Notifications row inside opens the index
  - Mobile: hamburger shows dot at each severity color; opening the panel reveals the avatar (also with dot) and the Notifications menuitem
  - Live update: trigger a new notification → both dots appear without reloading
  - Mark all read on `/notifications` → both dots fade-out simultaneously
- [ ] Cross-viewport: 375 / 768 / 1280 widths, both light + dark themes — indicator stays visible and positioned correctly
- [ ] AT spot-check (VoiceOver / NVDA): avatar button announces only identity, hamburger announces "Open menu" / "Close menu"; Notifications menuitem inside the menu announces "Notifications, N unread notifications"

## Out of scope (cross-reference)

The other two panel-review concerns (theme toggle hidden in mobile; "All workspaces" redundancy alongside switcher) get their own specs. This phase touches **only** the notifications surface.
