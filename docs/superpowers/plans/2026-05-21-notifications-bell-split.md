# Notifications Bell Split + User Menu Simplification (D1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Split the notifications bell out of the avatar dropdown into a standalone header button (sibling to the avatar on desktop, sibling to the hamburger on mobile). Simplify `_user_menu.html.erb`'s dropdown contents to exactly two items in both desktop and mobile contexts: a clickable identity block (avatar + name + email → links to `edit_account_profile_path`) and a sign-out button.

**Why:** User-driven design pivot D1, established after Path Y/Z stabilized the workspace navigation surface. The current user menu carries five items (text-only identity header, Profile link, Notifications link with bell+count, Notification preferences link, Sign out). The notifications affordance is buried in a dropdown; the bell is an overlay decoration on the avatar button, not independently clickable. D1 surfaces the bell as a top-level header affordance with its own click target (matches Linear/Notion/Slack), strips redundant items from the dropdown (Notification preferences is already accessible via the Settings sidebar), and turns the dropdown's identity row into a clickable shortcut to the user's personal-workspace profile.

**Architecture:**
- **Bell becomes a standalone link button** — own clickable element (`<a>`) routing to `account_notifications_path`, with the existing severity-color indicator frame (`notifications_bell_indicator_frame`) sitting inside it as a Turbo-broadcast target. Bell stays stable across broadcasts; only frame contents swap. Same pattern as the existing avatar/label split (button stable, label frame replaceable).
- **Identity block becomes a link** — avatar + name + email rendered as a single `<a>` row inside the dropdown, pointing to `edit_account_profile_path` (Settings hub's personal-context Profile destination). Setting `Current.workspace = user.personal_workspace` is already handled by the destination controller; sidebar switcher reflects the personal selection automatically.
- **Frame ID rename** — `notifications_avatar_button_label_frame` → `notifications_bell_label_frame` (semantically accurate now that the label lives on the bell, not the avatar). Three call sites in `NotificationBroadcaster` and the affected partials.
- **`notifications_menu_count_frame` broadcast deleted** — both consumer call sites in `_user_menu.html.erb` go away with dropdown simplification. Broadcaster loses one stream; `_notifications_menu_count_span.html.erb` partial is dead code.
- **Avatar button keeps `#user-menu-button` ID** — three system specs use this hook (`find("#user-menu-button")`); preserving it keeps suite stability.

**Tech stack:** Stimulus (existing `dropdown` controller, unchanged), TailwindCSS 4 (semantic tokens + AAA touch targets), RSpec system specs (Capybara + Playwright), axe-core WCAG 2.2 AAA. Server-side Turbo Streams via the existing `NotificationBroadcaster` lib.

**Out of scope:**
- Workspace-branded color header banner (the agent_os amber strip — separate design decision).
- About / Contact global-nav links (agent_os has them, we don't — separate IA decision).
- Chevron rotation animation on the workspace switcher (Path Y deferred drift, still deferred).
- Bell *behavior* changes — no new sound, no toast, no preview popover. Just relocation.
- Anything related to notification *content* — schema, severity logic, broadcast queue. The infrastructure is preserved.

**Branch:** `feat/notifications-bell-split` off `docs/settings-hub-spec`.

**Pre-task baseline:** 1898 examples, 0 failures, 0 pending. Coverage 94.77% line, 80.65% branch. (Verified after `6bc04f5` — the redundant Workspaces-header-link removal.)

**Definition of done:**
1. New `app/views/shared/_notifications_bell_link.html.erb` partial — standalone clickable bell with bell icon + severity-indicator frame + sr-only aria-labelledby span. Touch target 44×44. AAA focus ring.
2. `_header.html.erb` renders the new bell partial in both desktop block (between theme toggle and avatar) and mobile block (between theme toggle and hamburger — wait, actually mobile shows bell beside hamburger before it, since the hamburger lives on the right edge).
3. `_user_menu_avatar_button.html.erb` no longer renders the bell overlay (delete `render "shared/notifications_bell"`). Bell-related aria wiring removed from the avatar button; aria-label becomes a simple "Open user menu" label.
4. `_user_menu.html.erb` desktop dropdown contains exactly two items: clickable identity-block row (avatar+name+email → profile link) and sign-out button. Mobile context same shape.
5. `_user_menu_avatar_button_label.html.erb` deleted (its sr-only label moves into the new bell partial; avatar button gets a static aria-label).
6. `_notifications_menu_count_span.html.erb` deleted (no consumer after dropdown simplification).
7. `NotificationBroadcaster` no longer broadcasts to `notifications_menu_count_frame`. The `notifications_avatar_button_label_frame` target renamed to `notifications_bell_label_frame`.
8. `_notifications_bell.html.erb` partial kept as-is (the indicator frame still works; just renders inside the new bell button instead of overlaid on the avatar).
9. CHANGELOG entry under Changed describing D1.
10. Full suite green at 1898 / 0 / 0 (or new count after spec adjustments).

---

## File Map

**Create:**
- `app/views/shared/_notifications_bell_link.html.erb` — standalone clickable bell wrapping the existing `_notifications_bell` indicator partial

**Modify:**
- `app/views/shared/_header.html.erb` — render the new bell partial in both desktop + mobile right-side blocks
- `app/views/shared/_user_menu.html.erb` — simplify both contexts to 2-item dropdown
- `app/views/shared/_user_menu_avatar_button.html.erb` — remove bell overlay; simplify aria wiring
- `app/views/shared/_notifications_bell.html.erb` — rename frame `notifications_avatar_button_label_frame` references if any (verify; otherwise no change)
- `app/lib/notification_broadcaster.rb` — rename frame target; remove `notifications_menu_count_frame` broadcast block
- Specs that assert on Profile/Notifications/Preferences links inside the dropdown
- `CHANGELOG.md`

**Delete:**
- `app/views/shared/_user_menu_avatar_button_label.html.erb` — superseded by inline sr-only label in the new bell partial
- `app/views/shared/_notifications_menu_count_span.html.erb` — no consumer after dropdown simplification

---

## Task 1: Create the standalone bell partial (TDD-first)

**Why first:** Build the new affordance in isolation. No header wiring yet, so the suite stays green; the partial gets its own targeted spec.

**Files:** Create `app/views/shared/_notifications_bell_link.html.erb` and `spec/system/shared/notifications_bell_link_spec.rb`.

**Steps:**

- [x] **Step 1: Failing spec.** Write a system spec that signs in as a user with at least one unread notification (use the existing factory pattern from `spec/system/notifications/*` for setup), renders the partial directly via `render` in a request spec OR visits a page that includes the new bell (after Task 5), and asserts:
  - A `<a>` element with `href` matching `account_notifications_path`
  - An aria-label/labelledby with text describing unread count (e.g., "Notifications, 1 unread" or similar via the existing `avatar_button_aria_label` helper adapted for bell context)
  - `min-h-[44px] min-w-[44px]` touch target
  - The bell icon is rendered inside

  Since the partial isn't rendered anywhere yet, write the spec as a **view spec** or **partial render spec** to keep it focused: `spec/views/shared/_notifications_bell_link.html.erb_spec.rb` using `render partial: "shared/notifications_bell_link", locals: { user: user }`.

- [x] **Step 2: Run the spec.** Expected: FAILS because the partial doesn't exist.

- [x] **Step 3: Create the partial.**

```erb
<%# locals: (user:, summary: nil) -%>
<%# Standalone notifications bell button. Links directly to the
    notifications triage page. Severity indicator dot is rendered inside
    `notifications_bell_indicator_frame` (broadcast target) so the bell
    button itself stays stable across notification arrivals. The
    aria-labelledby sr-only span lives in `notifications_bell_label_frame`,
    swapped on broadcast so AT announces updated unread counts without
    detaching the focusable element. -%>
<% summary ||= unread_notification_summary(user) %>
<a href="<%= account_notifications_path %>"
   id="notifications-bell-link"
   aria-labelledby="notifications_bell_label"
   data-turbo-prefetch="true"
   class="btn-touch-target relative inline-flex items-center justify-center rounded-full
          text-text-body
          motion-safe:transition-colors motion-safe:duration-150
          hover:bg-surface-sunken hover:text-interactive
          focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus">
  <turbo-frame id="notifications_bell_label_frame">
    <span id="notifications_bell_label" class="sr-only">
      <%= bell_link_aria_label(user, summary) %>
    </span>
  </turbo-frame>
  <%= icon(:bell, size: :md, aria_label: nil) %>
  <%= render "shared/notifications_bell", user: user, summary: summary %>
</a>
```

`bell_link_aria_label(user, summary)` is a new helper (or rename `avatar_button_aria_label` to be bell-focused). Implementation parallels the existing helper but says "Notifications, N unread including 'subject'" instead of "User menu for Name. N unread...".

- [x] **Step 4: Add the helper** in `app/helpers/notification_helper.rb` (or wherever `avatar_button_aria_label` lives):

```ruby
def bell_link_aria_label(user, summary)
  if summary[:count].positive?
    if summary[:phrase].present?
      I18n.t("navigation.bell.label_with_unread", count: summary[:count], phrase: summary[:phrase])
    else
      I18n.t("navigation.bell.label_with_unread_count_only", count: summary[:count])
    end
  else
    I18n.t("navigation.bell.label")
  end
end
```

Add corresponding locale keys to `config/locales/en/application.en.yml` under `navigation`:

```yaml
bell:
  label: "Notifications"
  label_with_unread_count_only:
    one: "Notifications, 1 unread"
    other: "Notifications, %{count} unread"
  label_with_unread:
    one: "Notifications, 1 unread including %{phrase}"
    other: "Notifications, %{count} unread including %{phrase}"
```

- [x] **Step 5: Re-run the partial spec.** Expected: PASSES.

- [x] **Step 6: Run FULL suite.** Expected: 1898 / 0 / 0 (no behavior change — partial exists but no layout consumes it yet).

- [x] **Step 7: Commit.**

```bash
git add app/views/shared/_notifications_bell_link.html.erb app/helpers/notification_helper.rb config/locales/en/application.en.yml spec/views/shared/_notifications_bell_link.html.erb_spec.rb
git commit -m "feat(views): standalone notifications bell link partial (D1 prep)

New _notifications_bell_link partial renders the bell as a clickable
<a> linking to account_notifications_path, with the existing
notifications_bell indicator overlay wrapped inside. aria-labelledby
points to a sr-only span inside a renamed broadcast frame
(notifications_bell_label_frame). 44x44 touch target, AAA focus ring.

Adds bell_link_aria_label helper + navigation.bell.* locale keys.

Not yet wired into the header — see Task 5."
```

---

## Task 2: Rename broadcast frame + drop the menu-count broadcast

**Files:** Modify `app/lib/notification_broadcaster.rb`.

**Steps:**

- [x] **Step 1: Failing spec.** In `spec/lib/notification_broadcaster_spec.rb`, add an example asserting the broadcaster targets `notifications_bell_label_frame` (not `notifications_avatar_button_label_frame`) for the label broadcast, AND that it no longer issues a `notifications_menu_count_frame` broadcast. Run — expect failures.

- [x] **Step 2: Update broadcaster.** In `app/lib/notification_broadcaster.rb`:
  - Rename `target: "notifications_avatar_button_label_frame"` → `target: "notifications_bell_label_frame"`.
  - Update the `partial:` reference if it points to `_user_menu_avatar_button_label`; new target partial is `_notifications_bell_link` (or a new dedicated `_notifications_bell_label.html.erb` if the label needs to be broadcast standalone). Recommended: split the sr-only span into its own micro-partial `_notifications_bell_label.html.erb` so the broadcast replaces just that span, not the whole bell link.
  - Delete the entire broadcast block that targets `notifications_menu_count_frame` + renders `shared/notifications_menu_count_span`.

- [x] **Step 3: Create `_notifications_bell_label.html.erb`** (the micro-partial):

```erb
<%# locals: (user:, summary: nil) -%>
<% summary ||= unread_notification_summary(user) %>
<span id="notifications_bell_label" class="sr-only">
  <%= bell_link_aria_label(user, summary) %>
</span>
```

Update the `_notifications_bell_link.html.erb` partial from Task 1 to render this micro-partial inside the frame:

```erb
<turbo-frame id="notifications_bell_label_frame">
  <%= render "shared/notifications_bell_label", user: user, summary: summary %>
</turbo-frame>
```

This way the broadcaster targets a specific partial render, matching the existing pattern with `_notifications_menu_count_span`.

- [x] **Step 4: Re-run broadcaster spec.** Expected: PASSES.

- [x] **Step 5: Run FULL suite.** Expected: 1898 / 0 / 0 — broadcaster still works, just targets different frames.

- [x] **Step 6: Commit.**

```bash
git add app/lib/notification_broadcaster.rb app/views/shared/_notifications_bell_label.html.erb app/views/shared/_notifications_bell_link.html.erb spec/lib/notification_broadcaster_spec.rb
git commit -m "refactor(notifications): rename label frame; drop menu-count broadcast (D1)

Renames notifications_avatar_button_label_frame to
notifications_bell_label_frame to match its new home (Task 5 lands
the bell as a standalone header button). Splits the sr-only label
into its own micro-partial so the broadcast replaces only the span,
matching the existing _notifications_menu_count_span pattern.

Removes the notifications_menu_count_frame broadcast entirely — its
consumers (the menu count next to the dropdown's Notifications link)
go away in Task 3's user-menu simplification."
```

---

## Task 3: Simplify `_user_menu.html.erb` — both contexts, two items each

**Files:** Modify `app/views/shared/_user_menu.html.erb`.

**Steps:**

- [x] **Step 1: Failing spec.** In an existing user_menu spec (or new `spec/system/shared/user_menu_simplified_spec.rb`):
  - **Desktop:** sign in, click avatar, assert the dropdown contains exactly: a clickable identity block with avatar + full_name + email_address linking to `edit_account_profile_path`, and a sign-out button. Assert it does NOT contain a separate Profile link, Notifications link, or Notification preferences link.
  - **Mobile:** at 375×667 viewport, expand the header accordion, assert the user section inside contains the same 2-item shape.

- [x] **Step 2: Run the spec.** Expected: FAILS.

- [x] **Step 3: Rewrite the desktop branch** (lines 24-105 currently) to:

```erb
<% if context == :desktop %>
<div class="hidden md:flex items-center gap-2">
  <div data-controller="dropdown" class="relative">
    <%= render "shared/user_menu_avatar_button", user: Current.user %>

    <div data-dropdown-target="menu"
         id="user-menu"
         role="menu"
         aria-orientation="vertical"
         aria-labelledby="user-menu-button"
         class="hidden absolute right-0 mt-2 w-64 rounded-lg
                bg-surface-raised border border-border shadow-lg z-50">
      <%= link_to main_app.edit_account_profile_path,
            role: "menuitem", tabindex: "-1",
            data: { turbo_prefetch: "true" },
            class: "flex items-center gap-3 px-4 py-3
                    hover:bg-surface focus:outline-none focus:bg-surface
                    focus:ring-2 focus:ring-inset focus:ring-interactive-focus" do %>
        <div class="shrink-0 w-10 h-10 rounded-full overflow-hidden">
          <%= avatar_for(Current.user, size: :md) %>
        </div>
        <div class="min-w-0">
          <p class="text-sm font-semibold text-text-heading truncate"><%= Current.user.full_name %></p>
          <p class="text-xs text-text-muted truncate"><%= Current.user.email_address %></p>
        </div>
      <% end %>

      <div class="border-t border-border">
        <%= button_to t("navigation.sign_out"), main_app.session_path, method: :delete,
              role: "menuitem", tabindex: "-1",
              class: "w-full flex items-center min-h-[var(--form-input-height)] px-4 py-2
                      text-sm text-text-body
                      hover:bg-surface hover:text-interactive
                      focus:outline-none focus:ring-2 focus:ring-interactive-focus
                      cursor-pointer" %>
      </div>
    </div>
  </div>
</div>
<% end %>
```

- [x] **Step 4: Rewrite the mobile branch** (lines 107-143 currently) to the same 2-item shape, no `md:hidden` wrapper differences other than visibility class:

```erb
<% if context == :mobile %>
<div class="md:hidden">
  <%= link_to main_app.edit_account_profile_path,
        data: { turbo_prefetch: "true" },
        class: "flex items-center gap-3 px-3 py-3 rounded-md
                hover:bg-surface focus:outline-none focus:bg-surface
                focus:ring-2 focus:ring-inset focus:ring-interactive-focus" do %>
    <div class="shrink-0 w-10 h-10 rounded-full overflow-hidden">
      <%= avatar_for(Current.user, size: :md) %>
    </div>
    <div class="min-w-0">
      <p class="text-sm font-semibold text-text-heading truncate"><%= Current.user.full_name %></p>
      <p class="text-xs text-text-muted truncate"><%= Current.user.email_address %></p>
    </div>
  <% end %>
  <%= button_to t("navigation.sign_out"), main_app.session_path, method: :delete,
        class: "mt-1 w-full flex items-center min-h-[var(--form-input-height)] px-3 py-2
                text-sm text-text-body
                hover:text-interactive-hover rounded
                focus:outline-none focus:ring-2 focus:ring-interactive-focus cursor-pointer" %>
</div>
<% end %>
```

Delete the `summary = unread_notification_summary(Current.user)` line at the top of the partial — no longer needed since neither item uses summary state.

- [x] **Step 5: Re-run spec.** Expected: PASSES.

- [x] **Step 6: Update upstream specs** that assert on the old menu structure:
  - `spec/system/notifications/...` specs that click "Notifications" inside the user menu — they need a different path now. The bell partial will be where those interactions happen (after Task 5 wires the bell in). Mark them pending if needed; un-pend after Task 5.
  - Specs asserting `have_link(I18n.t("navigation.profile"))` inside the menu — update target/expectation.

- [x] **Step 7: Run FULL suite.** Some failures expected from Step 6 pendings. Net: confirm only expected breaks.

- [x] **Step 8: Commit.**

```bash
git add app/views/shared/_user_menu.html.erb spec/...
git commit -m "refactor(views): user menu dropdown is identity + sign out only (D1)

Desktop dropdown and mobile inline block both collapse from 5 items
(name+email header, Profile, Notifications, Notification preferences,
Sign out) to 2 items (clickable identity-block row linking to
edit_account_profile_path + sign-out button).

Notifications affordance moves to a standalone header bell button
(Task 5). Notification preferences is already reachable via the
Settings hub sidebar's personal-context Notifications item.

Per the D1 design call after Path Y/Z stabilized the workspace
navigation surface."
```

---

## Task 4: Simplify the avatar button — remove bell overlay

**Files:** Modify `app/views/shared/_user_menu_avatar_button.html.erb`. Delete `app/views/shared/_user_menu_avatar_button_label.html.erb`.

**Steps:**

- [x] **Step 1: Failing spec.** Assert in a system spec that:
  - The avatar button's aria-label is `t("navigation.user_menu_label_simple")` (a new static key — "Open user menu") or stays with the existing `user_menu_label` (parameterized by name but no notification info).
  - The avatar button does NOT contain a bell icon child (visually-rendered or otherwise).
  - The bell-indicator broadcast frame is NOT inside the avatar button anymore.

- [x] **Step 2: Run spec.** Expected: FAILS.

- [x] **Step 3: Simplify the avatar button:**

```erb
<%# locals: (user:) -%>
<button data-dropdown-target="button"
        data-action="click->dropdown#toggle"
        id="user-menu-button"
        aria-haspopup="true"
        aria-expanded="false"
        aria-controls="user-menu"
        aria-label="<%= t("navigation.user_menu_label_simple", name: user.full_name) %>"
        class="btn-touch-target relative rounded-full
               focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus
               cursor-pointer">
  <span id="user_avatar_header"><%= avatar_for(user, size: :md) %></span>
</button>
```

Add `navigation.user_menu_label_simple: "Open user menu for %{name}"` to the locale (or keep the existing `user_menu_label`).

- [x] **Step 4: Delete `_user_menu_avatar_button_label.html.erb`** — the sr-only label moved into the new bell partial.

- [x] **Step 5: Verify no orphaned references.**

```bash
grep -rn "_user_menu_avatar_button_label\|user_menu_avatar_button_label" app/ spec/
```

Expected: zero matches.

- [x] **Step 6: Re-run spec.** Expected: PASSES.

- [x] **Step 7: Full suite.** Expected: still has the Task 3 / Task 5 pending blocks, no new failures.

- [x] **Step 8: Commit.**

```bash
git add app/views/shared/_user_menu_avatar_button.html.erb app/views/shared/_user_menu_avatar_button_label.html.erb config/locales/en/application.en.yml
git commit -m "refactor(views): avatar button no longer carries bell overlay (D1)

Removes the bell overlay render + aria-labelledby wiring from the
avatar button. Bell is now a separate header affordance (Task 5).
aria-label simplifies to 'Open user menu for {name}' — no longer
needs to announce unread count since that lives on the bell now.

Deletes _user_menu_avatar_button_label partial (sr-only span moved
into the new _notifications_bell_link partial in Task 1)."
```

---

## Task 5: Wire the bell into `_header.html.erb`

**Files:** Modify `app/views/shared/_header.html.erb`.

**Steps:**

- [x] **Step 1: Failing spec.** Assert the header renders the bell partial at both viewports:
  - At ≥md (default desktop): bell button is visible to the left of the avatar, in the desktop right-side block.
  - At <md (375×667): bell button is visible to the left of the hamburger.

- [x] **Step 2: Add the bell render to both blocks:**

Desktop block:
```erb
<div class="hidden md:flex items-center gap-2">
  <% unless authenticated? %>
    <%= link_to t("navigation.sign_up"), main_app.new_registration_path, class: "..." %>
  <% end %>
  <%= render "shared/theme_toggle", style: :icon %>
  <% if authenticated? %>
    <%= render "shared/notifications_bell_link", user: Current.user %>
  <% end %>
  <%= render "shared/user_menu", context: :desktop %>
</div>
```

Mobile button area (between theme toggle area and hamburger):
```erb
<% if authenticated? %>
  <%= render "shared/notifications_bell_link", user: Current.user %>
<% end %>
<button data-action="click->mobile-menu#toggle" ...>
  <%# hamburger %>
</button>
```

Note: on mobile the bell sits in the top header row (always visible), NOT inside the accordion panel. The user can reach notifications from any mobile page without expanding the accordion.

- [x] **Step 3: Un-pend** any specs from Task 3 that were waiting on the bell wiring.

- [x] **Step 4: Run FULL suite.** Expected: green at 1898+ examples, 0 failures, 0 pending.

- [x] **Step 5: Manual smoke test (browser):**
  - `bin/dev`, sign in
  - Desktop (≥md): bell visible left of avatar. Click bell → routes to triage. Click avatar → dropdown opens with identity + sign-out only.
  - Mobile (<md, e.g. iPhone SE simulator): bell visible left of hamburger. Click bell → routes to triage. Click hamburger → accordion expands with workspace switcher + workspace nav + identity block + sign out.
  - Trigger an unread notification (use rails console: `user.notifications.create!(...)` or send via existing factory): bell shows severity dot, aria-label updates without re-render.

- [x] **Step 6: Commit.**

```bash
git add app/views/shared/_header.html.erb
git commit -m "feat(views): bell as standalone header affordance, both viewports (D1)

Mounts _notifications_bell_link in the header right-side block on
desktop (between theme toggle and avatar) and mobile (between theme
toggle and hamburger). Bell visible at all viewports, clickable
directly to triage page without traversing the user menu or the
mobile accordion.

Completes D1: avatar dropdown is identity + sign-out only; bell is
its own top-level affordance with severity state and unread count
broadcasted into stable frames inside the bell."
```

---

## Task 6: Dead-code sweep + CHANGELOG + final verification

**Files:** Delete `app/views/shared/_notifications_menu_count_span.html.erb`. Modify `CHANGELOG.md`.

**Steps:**

- [x] **Step 1: Verify orphaned partial.** `grep -rn "notifications_menu_count_span" app/ spec/`. Expected: zero matches (Task 2 dropped the broadcast; Task 3 dropped the in-menu renders).

- [x] **Step 2: Delete `_notifications_menu_count_span.html.erb`.**

- [x] **Step 3: Check for other orphans:**

```bash
grep -rn "notifications_menu_count_frame\|notifications_avatar_button_label_frame\|user_menu_avatar_button_label" app/ spec/ config/
```

Expected: zero matches.

- [x] **Step 4: CHANGELOG entry under Changed:**

```markdown
- Notifications bell is now a standalone header affordance (sibling to the avatar on desktop, sibling to the hamburger on mobile) routing directly to the triage page. The user-menu dropdown collapses to two items: a clickable identity block (avatar + name + email → personal-workspace profile) and sign-out. Notification preferences remains accessible via the Settings hub sidebar's personal-context Notifications item. Removes `notifications_menu_count_span` partial, `_user_menu_avatar_button_label` partial, and the `notifications_menu_count_frame` broadcast. Renames `notifications_avatar_button_label_frame` → `notifications_bell_label_frame` to match its new home.
```

- [x] **Step 5: Run FULL suite once more.** Expected: green.

- [x] **Step 6: Commit.**

```bash
git add CHANGELOG.md app/views/shared/_notifications_menu_count_span.html.erb
git commit -m "chore: dead-code sweep + changelog for D1 bell split"
```

- [x] **Step 7: Fast-forward into `docs/settings-hub-spec`.**

```bash
git checkout docs/settings-hub-spec
git merge --ff-only feat/notifications-bell-split
git branch -d feat/notifications-bell-split
git log --oneline -8
```

---

## Verification plan

After Task 6:

1. **Full RSpec suite** — `/opt/homebrew/bin/mise exec -- bundle exec rspec`. Expect green, count similar to 1898 (some new view/lib specs added, some old menu-internal specs deleted or updated).
2. **Lefthook pre-push** (runs on actual push) — same suite.
3. **Manual browser** at three viewports, two themes:
   - 375×667: bell + hamburger in top header row, both clickable. Bell routes to triage; hamburger expands accordion.
   - 1280×800: bell + avatar in top header row, both clickable. Bell routes to triage; avatar opens 2-item dropdown.
   - 768×1024: lands on which side of md? Verify both bell + avatar render correctly OR bell + hamburger render correctly per breakpoint.
4. **Broadcast smoke test** — trigger a notification via rails console (`Noticed::Notification` create OR via an existing factory in `bin/console`). Bell severity dot appears without page reload. aria-label updates (verify via DOM inspection or screen reader).
5. **axe-core both themes both states** — covered by the existing system specs + the new ones from Tasks 1, 3, 5. Local axe-core CAN miss CI-caught violations (per `feedback_ci_vs_local_axe.md`); push to remote before treating as fully shipped.

---

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Broadcaster rename breaks live notification updates | Medium | Spec coverage in Task 2 specifically asserts the frame target. Manual broadcast smoke test in Verification step 4. |
| Bell's severity color in light mode loses contrast at the new size/position | Medium | The existing `_notifications_bell` partial already passes AAA in its current position; reusing it (not rewriting) preserves coverage. axe-core will catch regressions. |
| Existing notification specs assert on dropdown-internal "Notifications" link | High | Task 3 Step 6 explicitly sweeps these. Pending-decorator strategy keeps the suite green between commits. |
| Avatar button `#user-menu-button` ID gets renamed by accident | Low | Task 4 Step 3 preserves the ID explicitly. Three system specs depend on it; loss would surface fast. |
| Bell + avatar visually crowded on desktop | Low | Both partials use icon-sized touch targets (44×44). `gap-2` in the parent flex layout spaces them. Verify in browser. |
| `bell_link_aria_label` helper duplicates work from `avatar_button_aria_label` | Medium | Acceptable for clarity (two affordances, two labels). If you'd prefer a single shared helper, refactor in a follow-up. |
| The personal-workspace selection on Profile click depends on existing controller behavior | Low | `edit_account_profile_path` already sets `Current.workspace = user.personal_workspace` (verified during Path Y). No new logic. |

---

## Rollback strategy

Path Z-style: all six tasks on a single feature branch off `docs/settings-hub-spec`. If issues surface:

- **Pre-merge:** delete the branch.
- **Post-merge to `docs/settings-hub-spec`:** revert the Task 1-6 commits as a contiguous range. Drop-zone partial files return; broadcaster targets restore; menu items reappear.
- **Post-merge to `main`:** any revert restores the bell-as-overlay + 5-item-dropdown state at `6bc04f5`.

---

## Out-of-scope (re-stated)

- Workspace-branded header banner (the agent_os amber strip — separate UX call).
- About / Contact global nav links at the top of the mobile accordion (separate IA decision).
- Chevron rotation animation on the workspace switcher (Path Y deferred).
- Notification UX changes (toasts, previews, sound) — D1 is relocation only.
- Splitting `avatar_button_aria_label` into shared helpers (acceptable duplication).
