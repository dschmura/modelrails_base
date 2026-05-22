# Strong Workspaces Index — Path AA Design

**Status:** Approved (2026-05-22)
**Phase name:** Path AA — Strong Workspaces Index
**Branch (planned):** `feat/path-aa-strong-workspaces-index` off `docs/settings-hub-spec`
**Supersedes:** the existing `app/views/workspaces/index.html.erb` (36-line phonebook)

## Why

Jason Fried's "weak index" critique applied to `workspaces#index` of this project surfaced five failing criteria:

1. Treats every row identically (no current marker, no metadata)
2. No "you are here" — current workspace indistinguishable from others
3. Directory not workbench — pure navigation, zero in-place verbs
4. Thin metadata — only name + plan label
5. Two satellite affordances (sidebar switcher + new "All workspaces" link) point at this destination; a third would signal the destination is failing

The "All workspaces" link in the user-menu dropdown (shipped earlier in `2036ffb`) is the right affordance — but it currently delivers users to a phonebook. Per Fried: "fix the destination; the chrome gets quiet on its own." This phase strengthens the destination.

## Goal

Convert `workspaces#index` into a workbench that:

- **Orients** — pinned current (most-recently-accessed) workspace with CURRENT badge, last-accessed timestamp on every row.
- **Acts** — Switch verb on every row, Leave verb on every row where the user isn't the last owner and the workspace isn't their personal.
- **Scales gracefully** — handles 1 / 5 / 30 workspaces without redesign. Search is held until real usage (N ≥ 7) demands it.

## Scope summary

| Decision | Choice |
| --- | --- |
| "Current" semantics | Most-recently-accessed membership (membership with highest `last_accessed_at`) |
| Sort order | `memberships.last_accessed_at DESC NULLS LAST, workspaces.name ASC` |
| Pinned section | First row by sort; rest below in "Other workspaces" |
| Inline verbs | **Switch** (every row, including current) + **Leave** (when policy permits) |
| Rename | Out of scope — stays in `workspaces#edit` (Profile page) |
| Set-as-default | Out of scope (YAGNI; no new state required) |
| Last-accessed column | New `memberships.last_accessed_at` (datetime, indexed) |
| Touch mechanism | Single `UPDATE` per workspace-scoped request via `WorkspaceScoped` concern |
| Member count source | Preloaded `workspace.memberships.kept.size` off existing eager-load |
| Mobile breakpoint | `<md` stacks action buttons below metadata |
| Empty/degenerate states | Existing `shared/_empty_state` for zero; suppress "Other workspaces" heading for single membership |
| Search / filter | Out of scope until N ≥ 7 demand surfaces |

## UX / Visual design

### Layout

```text
─────────────────────────────────────────────────────────
                  Your workspaces       [+ New workspace]
─────────────────────────────────────────────────────────

┌──────────────────────────────────────────────────────────────────┐
│ [icon]  Davey's Workspace                              CURRENT   │
│         Free · Owner · 1 member                                  │
│         Last accessed 2 minutes ago                  [Switch →]  │
└──────────────────────────────────────────────────────────────────┘

Other workspaces

┌──────────────────────────────────────────────────────────────────┐
│ [icon]  Acme Corporation                                         │
│         Pro · Admin · 24 members                                 │
│         Last accessed 3 days ago              [Switch →] [Leave] │
├──────────────────────────────────────────────────────────────────┤
│ [icon]  Acme Collaboration                                       │
│         Pro · Member · 8 members                                 │
│         Last accessed 2 weeks ago             [Switch →] [Leave] │
├──────────────────────────────────────────────────────────────────┤
│ [icon]  Empty Workspace                                          │
│         Free · Member · 1 member                                 │
│         Never accessed                        [Switch →] [Leave] │
└──────────────────────────────────────────────────────────────────┘

                  [+ Create workspace]   ← modest CTA at bottom
```

### Row anatomy

Each workspace row contains, in order:

- **Workspace icon** — via existing `workspace_icon_for(workspace, size: :md)` helper. Shape per WCAG 1.4.1: circle for personal, rounded-square for org (already enforced by the helper).
- **Workspace name** — heading-weight, `text-text-heading`, truncated at long widths with `title=` attribute for full name.
- **Metadata row** (smaller, `text-text-muted`):
  - Plan badge (using existing `t("workspaces.plans.#{workspace.plan}")` keys: "Free" / "Pro" / "Enterprise")
  - Role badge (the user's role in that workspace): "Owner" / "Admin" / "Member"
  - Member count: `pluralize(workspace.memberships.kept.size, t("workspaces.index.row.member"))`
- **Last accessed** (smaller, `text-text-muted`):
  - "Last accessed 2 minutes ago" via `time_ago_in_words(membership.last_accessed_at)`
  - "Never accessed" when `last_accessed_at` is nil
- **Action area** (right side, `<md` stacks below):
  - **Switch** button (or whole-row link) → `workspace_path(workspace)`
  - **Leave** button (when `policy(membership).destroy?` permits) → `DELETE /workspaces/:slug/memberships/:id`
- **Current row only**: CURRENT badge at the top-right of the row (semantic tokens `bg-interactive text-text-on-interactive`).

### Current-row treatment

The first row in the sort order (most-recently-accessed) is rendered inside its own bordered section labeled "Your workspaces" implicitly (no heading on the section — the CURRENT badge + visual distinction does the work). The current row:

- Has the CURRENT badge in the top-right.
- Has the SAME Switch button as other rows (visual rhythm; navigates to the workspace overview the user was last in).
- Does NOT show a Leave button (leaving the most-recent workspace from this page is a foot-gun; require them to navigate into the workspace first, then use the leave flow from the workspace's own settings).

The "Other workspaces" section header is rendered only when there are ≥ 2 memberships total. With a single membership, only the pinned section + "Create workspace" CTA appears.

### Responsive behavior

- **≥md**: action buttons right-aligned in their own column, metadata in the middle, icon on the left. Whole row is a flex container with `gap-4`.
- **<md**: same flex but `flex-col` — icon + name + metadata stack vertically; action buttons stack horizontally as a row below the metadata. Touch targets remain `min-h-[44px]`.

### Accessibility (WCAG 2.2 AAA)

- Each row's whole area is a navigable element (clickable + keyboard-focusable). Implementation: outer `<li>` contains the row; the Switch button is the primary tab target. Whole-row click is implemented via a JS-free pattern (link wrapping content + buttons positioned over it with `relative + z-10`).
- CURRENT badge uses both color AND text ("CURRENT") — no color-only encoding (SC 1.4.1).
- All action buttons are `min-h-[44px] min-w-[44px]` (SC 2.5.5 Enhanced Target Size).
- Focus rings on `interactive-focus` (cyan-700) — SC 2.4.7.
- All visible strings via `t(...)` — no hardcoded English.
- Leave button uses the project's `safe-destructive` confirm pattern (existing — used elsewhere for deactivate / discard flows).
- The page's `<h1>` is the "Your workspaces" title (existing). The CURRENT badge and section labels are NOT headings (would conflict with the document outline).

## Data model changes

### Migration 1: Add `last_accessed_at` to memberships

```ruby
class AddLastAccessedAtToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :last_accessed_at, :datetime
    add_index  :memberships, [:user_id, :last_accessed_at]
  end
end
```

The index supports the `Current.user.workspaces.kept.joins(:memberships).order("memberships.last_accessed_at DESC NULLS LAST")` query pattern in the controller. Composite index includes `user_id` because we always scope by the current user.

**Backfill**: the migration intentionally does NOT backfill `last_accessed_at` for existing memberships. Existing rows have `NULL`, sort to the bottom of the list under "alphabetical NULLS LAST" rules, and get the "Never accessed" label until they receive their first touch. This is honest — we don't have historical access data to fabricate.

### Touch mechanism

`app/controllers/concerns/workspace_scoped.rb` already exists and is included by every workspace-scoped controller (workspaces#show, workspaces/projects#*, workspaces/members#*, etc.). Add a `before_action :touch_membership_last_accessed`:

```ruby
private

def touch_membership_last_accessed
  return unless Current.user && Current.workspace

  Membership
    .where(user_id: Current.user.id, workspace_id: Current.workspace.id, discarded_at: nil)
    .update_all(last_accessed_at: Time.current)
end
```

Properties:

- **Single UPDATE per request** — no callback cascade, no validation, no broadcast. Sub-millisecond.
- **No throttling in v1** — if hot-path latency suffers (e.g., from Turbo Frame requests touching the membership on every fragment refresh), throttle via `session[:last_membership_touch_at]` checked against `1.minute.ago`. Tracking item, not a v1 requirement.
- **Discarded memberships are skipped** — leaving a workspace ends the touch trail.
- **Failing the touch silently** — wrapped in `rescue StandardError => e; Rails.error.report(e)` so a connection blip on the touch doesn't 500 the user's page request. Same posture as `NotificationBroadcaster#safe_broadcast`.

### No other schema changes

- No `users.default_workspace_id` (YAGNI).
- No `workspaces.memberships_count` counter cache (Discardable adds maintenance burden; preloaded count is correct and free).
- No `users.last_visited_workspace_id` (the membership row IS the source of truth).

## Routes / controller changes

### New route: `DELETE /workspaces/:slug/memberships/:id`

The "leave" action. Add to `routes.rb`:

```ruby
resources :workspaces, param: :slug do
  resources :memberships, only: [:destroy], controller: "workspaces/memberships"
end
```

If `Workspaces::MembersController#destroy` already exists for the admin-deactivates-a-member case, reuse it. The action's policy gate handles both cases:

- Admin deactivating someone else's membership → `MembershipPolicy#destroy?` checks admin role on workspace
- User leaving (deactivating their own membership) → `MembershipPolicy#destroy?` checks `record.user == user` AND not-last-owner AND not-personal-workspace

Implementation: `Membership#deactivate!` (already exists; handles last-owner protection). The controller wraps the call, redirects to `/workspaces` with a success toast, and responds to `turbo_stream` by removing the row.

### `WorkspacesController#index` updates

```ruby
def index
  authorize Workspace

  scope = Current.user.memberships.kept
    .includes(workspace: [:logo_attachment, memberships: [:role, { user: :avatar_attachment }]])
    .joins(:workspace)
    .merge(Workspace.kept)
    .order(Arel.sql("memberships.last_accessed_at DESC NULLS LAST, workspaces.name ASC"))

  @current_membership = scope.first
  @other_memberships  = scope.drop(1)
end
```

Note the shape change: we now iterate `@current_membership` (singular) + `@other_memberships` (rest) rather than a flat `@workspaces`. This makes the view's "pinned current + others" split explicit.

The eager-load includes `memberships` on each workspace (already present for owner-detection) so `workspace.memberships.kept.size` in the view is N+0 queries.

### View: rewrite `app/views/workspaces/index.html.erb`

Replace the existing 36 lines with the structure shown above. Extract sub-partials:

- `app/views/workspaces/index/_row.html.erb` — single workspace row. Locals: `(membership:, current: false)`. Renders icon, name, metadata, last-accessed, action buttons.
- `app/views/workspaces/index/_leave_button.html.erb` — Leave button + safe-destructive confirm. Locals: `(membership:)`. Gated on Pundit policy.

Index file becomes ~50 lines orchestrating the pinned/others split + the empty/single-membership branches.

## Authorization

| Verb | Policy | Visibility rule |
| --- | --- | --- |
| Switch (the link/button itself) | None required — every workspace in `Current.user.workspaces.kept` is by definition allowed | Always shown |
| Leave (Leave button) | `MembershipPolicy#destroy?` | Shown only when policy permits |

### `MembershipPolicy#destroy?` amendment

The existing policy at `app/policies/membership_policy.rb:10-12` is currently:

```ruby
def destroy?
  can?("manage_members") && record.user != user
end
```

That `record.user != user` clause explicitly EXCLUDES self-deactivation, so the leave case must be added. The amended policy permits two distinct paths:

```ruby
def destroy?
  return false if record.workspace.discarded?

  if record.user == user
    # Leave case: user deactivating their own membership.
    return false if record.workspace.id == user.personal_workspace_id
    return false if record.role.slug == "owner" && record.workspace.owners.size == 1
    true
  else
    # Admin-deactivates-someone-else case (existing).
    can?("manage_members")
  end
end
```

**Why the explicit personal-workspace check**: a user's personal workspace is created on signup (`User#create_personal_workspace`) and stored as `users.personal_workspace_id`. Letting a user leave their own personal workspace would orphan that data and break the "every user has a personal workspace" invariant the rest of the codebase assumes. The model layer doesn't enforce this today; the policy must.

**Why the explicit last-owner check at the policy layer**: `Membership#deactivate!` already raises on last-owner via `validate_not_last_owner!`. Mirroring that at the policy layer means the UI is honest — we hide the Leave button when leaving is genuinely impossible rather than showing it and producing a 422 on submit.

The Pundit policy is the authoritative gate for visibility; `Membership#deactivate!` is the model-level safety net for direct DELETE requests.

## Empty / degenerate states

| Membership count | Render |
| --- | --- |
| 0 (impossible in practice — every user has a personal workspace) | Existing `shared/_empty_state` partial as defensive fallback |
| 1 (only personal workspace) | Pinned current section + "Create workspace" CTA at bottom. NO "Other workspaces" heading. |
| 2+ | Pinned current + "Other workspaces" heading + N−1 rows + "Create workspace" CTA |

For `last_accessed_at` nil: render `t("workspaces.index.row.never_accessed")` ("Never accessed") instead of `time_ago_in_words`.

For the membership-count rendering: if `memberships.kept.size == 1` (the user is the only member), render `t("workspaces.index.row.member", count: 1)` ("1 member"); if more, use pluralization (`count: N`).

## Out of scope (explicit)

- **`workspaces#show` redesign** — the workspace overview page is unchanged.
- **Sidebar workspace switcher** — unchanged; remains the in-workspace switching affordance.
- **Inline rename** — rejected by Fried & Oliver review. Rename stays at `workspaces#edit` (the Profile page).
- **"Set as default" workspace concept** — YAGNI; not added.
- **Sign-in redirect to a workspace** — unchanged; signed-in users still land on `/`.
- **Search / filter** — held until real usage demands (N ≥ 7 average user threshold per Fried).
- **Counter cache on `memberships_count`** — preloaded count is correct and Discardable-safe.
- **Transfer-ownership flow** — unchanged; lives in workspace settings.
- **Avatar trigger chevron** — separate deferred item from the prior panel review.
- **Identity-picker herb-lint warnings** — separate pre-existing tech debt.

## Testing strategy

### System specs

- `spec/system/workspaces/index_spec.rb` (rewrite):
  - **Pinned current**: visit workspaces#index after touching workspace A; expect A in the "current" section with the CURRENT badge; expect B and C in "Other workspaces."
  - **Sort order**: touch B last, then A; visit `/workspaces`; expect A pinned (most recent), B second.
  - **Never-accessed sorting**: a workspace with `last_accessed_at: nil` sorts after touched workspaces, alphabetically among unvisited peers.
  - **Metadata presence**: each row shows plan / role / member count / last-accessed text.
  - **Switch action**: clicking Switch on a non-current row navigates to that workspace's overview.
  - **Leave flow**: click Leave on a non-personal, non-last-owner workspace; confirm dialog appears; confirm; row disappears via turbo_stream; success toast.
  - **Personal workspace has no Leave button**: the user's personal workspace never shows Leave.
  - **Last-owner has no Leave button**: a sole-owner workspace doesn't show Leave for the owner.
  - **Single workspace**: only personal workspace exists; "Other workspaces" heading is absent.
  - **axe-AAA**: passes in both themes.

### Request specs

- `spec/requests/workspaces/memberships_spec.rb` — `DELETE /workspaces/:slug/memberships/:id`:
  - Owner of a non-personal workspace can leave (if not last owner) — 303 redirect to `/workspaces`, membership discarded.
  - Last owner cannot leave — 403 forbidden, membership not discarded.
  - Personal workspace owner cannot leave their own personal — 403, membership not discarded.
  - Non-member cannot delete someone else's membership — 403.
  - Admin can deactivate another member — 303, that membership discarded.

### Model specs

- `spec/models/membership_spec.rb` (add):
  - `last_accessed_at` accepts datetime values.
  - Index exists on `[user_id, last_accessed_at]` (via `db/schema.rb` assertion or migration spec).

### Controller / concern specs

- `spec/controllers/concerns/workspace_scoped_spec.rb` (add or extend):
  - `touch_membership_last_accessed` updates the row when both `Current.user` and `Current.workspace` are set.
  - No-op when either is nil.
  - No-op when the membership is discarded.
  - Failure to UPDATE is reported via `Rails.error.report` and does not raise.

### Integration spec

- `spec/system/workspaces/membership_touch_spec.rb`:
  - Visit workspace A's overview → membership for A's `last_accessed_at` updates.
  - Visit workspace B's overview → membership for B's `last_accessed_at` updates; A's stays as previously set.
  - Visit `/workspaces` → A and B both appear with correct relative timestamps.

## Phase naming + branch

- **Phase name**: Path AA — Strong Workspaces Index
- **Branch**: `feat/path-aa-strong-workspaces-index` off `docs/settings-hub-spec`
- **Spec**: `docs/superpowers/specs/2026-05-22-strong-workspaces-index-design.md` (this file)
- **Plan**: `docs/superpowers/plans/2026-05-22-path-aa-strong-workspaces-index.md` (next, via writing-plans skill)

## Acceptance criteria

When this phase is complete, all five of Jason Fried's weak-index criteria flip to passing:

| Criterion | Pre-AA | Post-AA |
| --- | --- | --- |
| Treats every row identically | ❌ | ✓ Current row visually distinct (own section + CURRENT badge) |
| No "you are here" | ❌ | ✓ CURRENT badge + pinned-at-top placement |
| Directory not workbench | ❌ | ✓ Switch + Leave inline verbs |
| Thin metadata | ⚠ (only name + plan) | ✓ Plan + role + member count + last-accessed |
| Chrome compensating with mini-switchers | ⚠ (at threshold) | ✓ Index is now strong enough that the user-menu "All workspaces" link and the sidebar switcher are both pointing at a destination worth landing on |

Also: full RSpec suite green (current baseline: 1910/0/0); GitHub Actions CI green; manual cross-viewport browser verification at 375/768/1280 in both themes.
