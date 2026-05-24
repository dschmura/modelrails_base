# Avatar Notification Indicator v2 — Design

**Status:** Approved (2026-05-23)
**Phase name:** Avatar Notification Indicator v2 (working title)
**Branch (planned):** `feat/avatar-notification-indicator-v2` off `main`
**Supersedes:** the standalone-header-bell decision from [2026-05-15 D1 design](2026-05-15-avatar-bell-notification-indicator-design.md). Brings the bell-indicator-on-avatar pattern back, refined to address D1's original concerns.
**Informed by:** UI/UX panel review (Wroblewski, Krug, Wathan, Pickering, Frost) — 2026-05-23.

## Why

D1 (2026-05-15) split the notifications surface off the avatar because of broadcast-frame-inside-focusable-button accessibility concerns. The split fixed those concerns but introduced three new UX issues, surfaced in the 2026-05-23 panel review:

1. Standalone bell + avatar trigger crowd each other in mobile chrome (next to the hamburger).
2. The compact "all your account-related signal in one place" mental model that the badge-on-avatar pattern naturally affords got fractured into two adjacent surfaces.
3. The standalone bell adds chrome real estate without adding meaningful information once a discoverable in-menu Notifications link exists.

The right answer isn't "undo D1" — it's "restore the badge pattern with the engineering lessons D1 taught us."

## Goal

A single notification signal in chrome that:

- **Lives on the identity surface** (avatar on desktop, hamburger on mobile) — co-locates "you and your state" rather than splitting them.
- **Carries severity** — red/amber/blue per highest unread, so users can decide-before-acting.
- **Is calm** — small indicator dot, not a full bell glyph; pulses only on danger-severity (motion-safe).
- **Stays accessible** — the broadcast-frame issue D1 fixed stays fixed (indicator renders as a positioned sibling of the focusable button, not inside its accessible name).
- **Doesn't fragment chrome** — the standalone header bell is removed; the in-menu Notifications link is the single triage entry point.

## Scope summary

| Decision | Choice |
| --- | --- |
| Indicator visual | Small colored dot (≈8px), not a bell glyph |
| Color model | Severity-tiered (danger / warning / info) per `unread_notification_summary` |
| Animation | `motion-safe:animate-pulse` on danger severity only; static otherwise |
| Position on avatar | Bottom-right of the avatar bounding box (matches D1 precedent; no conflict with the chevron, which sits outside the avatar wrapper) |
| Desktop chrome | Standalone bell link **removed**; user menu gains a Notifications item |
| Mobile chrome | Standalone bell link **removed**; hamburger button gets the same severity dot |
| Mobile panel | Avatar inside the expanded panel also carries the dot (consistency) |
| In-menu link position | "Notifications" sits between the identity block and "All workspaces" in the user menu dropdown |
| Triage entry point | The `Notifications` link inside the user menu (single canonical path) |
| Broadcast frames | Two turbo-frames sharing a single rendered partial — one over the avatar, one over the hamburger — both updated by the same broadcast stream |
| A11y model | Dot itself has `aria-hidden="true"`. Avatar / hamburger button accessible names stay static. Unread state is announced via a separate `aria-live="polite"` region inside the user menu next to the Notifications link |
| Severity → color tokens | Reuse `notification_bell_classes(severity)` helper; only the `:dot` variant gets new tokens (the existing `:icon` variant is unused after this change and can be retired) |

## UX / Visual design

### Desktop chrome

```text
┌──────────────────────────────────────────────────────────────────────┐
│ [LOGO]                  [theme] [DC•  v]                             │
│                                       ↑                              │
│                                       └─ chevron stays               │
│                                  ↑                                   │
│                                  └─ severity-colored dot,            │
│                                     bottom-right of avatar           │
└──────────────────────────────────────────────────────────────────────┘
```

### Mobile chrome (collapsed)

```text
┌──────────────────────────────────────────────────────────────────────┐
│ [LOGO]                                              [☰•]             │
│                                                       ↑              │
│                                                       └─ severity    │
│                                                          dot on the  │
│                                                          hamburger   │
└──────────────────────────────────────────────────────────────────────┘
```

### User menu dropdown (desktop) — new item added

```text
┌───────────────────────────────────────────┐
│ ┌─────┐                                   │
│ │ DC• │  Dave Chmura                     │
│ │     │  dschmura@humbledaisy.com         │  → profile
│ └─────┘                                   │
├───────────────────────────────────────────┤
│  🔔  Notifications              [3 new]   │  ← NEW
├───────────────────────────────────────────┤
│  All workspaces                           │  → workspaces#index
├───────────────────────────────────────────┤
│  Sign out                                 │
└───────────────────────────────────────────┘
```

The `[3 new]` badge inside the menu carries the count (which the indicator dot does not). This is where the count surfaces — same broadcast frame can update it.

### Dot anatomy

- Diameter: `w-2 h-2` (8px). Small enough to read as decoration; large enough to perceive at AAA luminance.
- Position: `absolute -bottom-0.5 -right-0.5` on the avatar wrapper / hamburger button.
- Halo: `[filter:drop-shadow(0_0_2px_var(--color-surface-raised))]` so the dot stays visible on any avatar background.
- Forced-colors mode: `forced-colors:bg-[Highlight]` so high-contrast users see something even when severity colors collapse to system colors.
- Pulse: `motion-safe:animate-pulse` only when severity = danger.

## Component contracts

### What gets added

- **`app/views/shared/_notifications_indicator.html.erb`** — new shared partial. Renders the dot when `summary[:severity]` is present; renders an empty placeholder otherwise. Takes a `surface:` local (`:avatar` | `:hamburger`) to pick the positioning class.
- **Notifications row inside `_user_menu.html.erb`** — new menuitem between identity block and "All workspaces." Renders the unread count via a dedicated `notifications_menu_count_frame` (preserves the live-update pattern that already exists for the count span).
- **Hamburger button positioning** — gains `relative` + the `_notifications_indicator` render inside it (sibling of the icon, not wrapping).

### What gets modified

- **`_user_menu_avatar_button.html.erb`** — avatar `<span id="user_avatar_header">` gains `relative inline-flex` and the `_notifications_indicator` render inside it (sibling of the avatar image, not wrapping). The button's accessible name stays as the static identity-only `aria-label` D1 introduced.
- **`_header.html.erb`** — removes the `render "shared/notifications_bell_link"` call.
- **`notification_bell_helper.rb`** — `notification_bell_classes` gains a `:dot` variant returning `{ bg: ... }` color tokens; the `:icon` variant retires.

### What gets removed

- **`app/views/shared/_notifications_bell_link.html.erb`** — the standalone bell link partial.
- **`app/views/shared/_notifications_bell.html.erb`** — the overlay partial (was rendered inside the bell link). Logic moves into `_notifications_indicator`.
- **`app/views/shared/_notifications_bell_label.html.erb`** — the sr-only aria-labelledby span. No longer needed since the avatar button uses a static aria-label.
- **`spec/views/shared/_notifications_bell_link.html.erb_spec.rb`** — and any related broadcast tests targeting `notifications_bell_indicator_frame` or `notifications_bell_label_frame`.

## Broadcast architecture

D1's frame structure:

```text
notifications_bell_label_frame  → swaps the sr-only aria-labelledby span
notifications_bell_indicator_frame → swaps the bell overlay
```

v2's frame structure:

```text
notifications_indicator_avatar    → renders _notifications_indicator partial (surface: :avatar)
notifications_indicator_hamburger → renders _notifications_indicator partial (surface: :hamburger)
notifications_menu_count_frame    → renders the [N new] badge inside the user menu
```

All three frames update on the same broadcast (the existing notification-event broadcast). The Stimulus / Turbo broadcast wiring stays unchanged — only the frame IDs and rendered partials change.

## A11y considerations

D1's original concern was: aria-labelledby pointing into a broadcast-replaceable frame mid-click can cause AT to lose track of the button's accessible name. v2 avoids this by:

1. Avatar button keeps the static `aria-label="Open user menu for [Name]"` from D1.
2. Hamburger button keeps its static "Open menu" / "Close menu" aria-label.
3. The indicator dot itself is `aria-hidden="true"` — it's visual-only.
4. Unread state is exposed verbally through the **Notifications menuitem inside the dropdown**, which carries the live count via `aria-live="polite"`. Screen reader users hear "Notifications, 3 new" when they open the menu, which is functionally equivalent to the dot's visual signal.
5. The dot's color is decorative, not the sole carrier of meaning — `forced-colors:bg-[Highlight]` ensures high-contrast users still see *something*, and the in-menu Notifications link provides the actual content path.

## Test plan

### View specs

- **`_notifications_indicator.html.erb_spec.rb`** — new file
  - Renders nothing when `summary[:severity]` is nil
  - Renders a `w-2 h-2 rounded-full` element with the correct severity background class for each of `:danger`, `:warning`, `:info`
  - Adds `motion-safe:animate-pulse` only when severity = `:danger`
  - Adds `aria-hidden="true"` regardless of severity
  - Picks `-bottom-0.5 -right-0.5` for `surface: :avatar`, differs for `surface: :hamburger`

- **`_user_menu_avatar_button.html.erb_spec.rb`** — existing, augment
  - Avatar wrapper has `relative` (anchors the dot)
  - Indicator partial renders inside the wrapper when authenticated user has unread
  - Indicator renders nothing when user has no unread
  - Avatar button's static `aria-label` is unchanged

- **`_user_menu.html.erb_spec.rb`** — augment (or new if absent)
  - Notifications menuitem renders between identity block and All workspaces
  - Count badge inside the Notifications row shows the unread count and lives in `notifications_menu_count_frame`
  - Notifications menuitem links to `account_notifications_path`

- **`_header.html.erb_spec.rb`** — augment
  - Standalone bell link is **not** rendered (regression guard against D1 reintroduction)
  - Hamburger button has `relative` (anchors the dot)
  - Indicator partial renders inside the hamburger when authenticated user has unread

### System specs

- **`notifications_avatar_indicator_v2_spec.rb`** — new system spec covering
  - Unauthenticated: no indicator, no hamburger dot
  - Authenticated, no unread: no indicator, no hamburger dot
  - Authenticated, 1 info-severity unread: indicator + hamburger dot, both info-blue
  - Authenticated, danger unread: indicator pulses (motion-safe)
  - Live: a new notification arrives via broadcast → both indicator frames update without page reload
  - Live: marking all as read clears both indicators in lockstep

### A11y specs (axe + manual)

- AAA contrast: dot color vs `bg-surface-raised` (light mode) and `bg-surface-raised dark` (dark mode) at each severity level
- AAA target size: dot doesn't reduce the avatar button's 44×44px target (it's decorative overlay, not a separate target)
- forced-colors: dot is visible in Windows High Contrast / forced-colors mode
- AT verification: user-menu Notifications row announces "Notifications, 3 new" via aria-live

## Out of scope

- Notification preferences UI changes (lives in Settings → Notifications, unchanged here)
- Mobile-specific gesture (long-press to open notifications directly, etc.) — keep the model simple
- Multi-account notification routing — irrelevant to chrome
- The other two concerns from the 2026-05-23 panel review (theme toggle hidden in mobile; "All workspaces" redundancy alongside switcher) — separate specs

## Implementation phases

1. **New shared partial + helpers** — `_notifications_indicator.html.erb`, `:dot` variant in `notification_bell_classes`. View spec.
2. **Avatar integration** — wrap avatar in `relative inline-flex` span, render indicator inside, augment view spec.
3. **Hamburger integration** — relative button, render indicator inside, augment header spec.
4. **User menu Notifications item** — add menuitem, count frame, augment user menu spec.
5. **Broadcast frame renames** — `notifications_indicator_avatar`, `notifications_indicator_hamburger`, `notifications_menu_count_frame`. Update the broadcasting code path.
6. **Removal pass** — delete `_notifications_bell_link.html.erb`, `_notifications_bell.html.erb`, `_notifications_bell_label.html.erb`, and their specs. Remove the render from `_header.html.erb`.
7. **System spec + axe coverage** — new file covering live update + AAA contrast.

Each phase is its own commit; phase 6 (removal) lands last so intermediate commits stay green.

## Decisions resolved at draft review (2026-05-23)

- **Dot visibility on `/notifications` itself:** show always. The indicator reflects unread state regardless of which page is rendering; hiding on a single page would introduce a state machine for marginal gain.
- **Mark-all-as-read transition:** motion-safe fade-out (≈150ms) when count drops to zero. Costs ~3 lines of CSS, feels more intentional than an instant blank, and respects `prefers-reduced-motion` (collapses to instant via `motion-safe:`).
