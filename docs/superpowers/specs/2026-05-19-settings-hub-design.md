# Settings Hub Design Spec

**Status:** Approved 2026-05-19 — unanimous 8/8 sign-off across frontend (Adam Wathan, Marcy Sutton, Steve Schoger, Jorge Manrubia) and backend (DHH, Chris Oliver, Dave Thomas, Joël Quenneville) panel reviews. Round 1 surfaced concerns; round 2 confirmed they were resolved.

**Implementation phasing:**

| Phase | Scope | Status |
|---|---|---|
| **1: Foundation** (data model) | `workspaces.personal` boolean column + `User#after_create :create_personal_workspace` auto-creating a real Owner Membership | **Done — discovered pre-existing in codebase** |
| **Deferred: Route consolidation** | Move identity from `settings/edit` to `workspaces#edit` per DHH's panel call; delete `BrandingController`; narrow `settings/edit` to operational config | **Deferred to future PR** — current architecture intentionally consolidates identity in `settings/edit` (~12 files would change). Hub UI in Phase 2 routes "Profile" to existing `settings/edit` URL until this refactor lands. |
| **2: Settings hub shell** | Settings hub layout, workspace switcher component (sidebar variant), context-adaptive sidebar with Pundit-gated items, aria-live region, full Turbo visit + morph wiring | **In progress** |
| **3: Sidebar destinations** | Each sidebar item's destination page working (Profile in both contexts, Notifications, Security, Appearance, Limits & Plan) with shared page skeleton and H1/aria-label disambiguation | Pending |
| **4: Polish** | OKLCH personal-context token ramp; switcher visual differentiation (avatar shape, role badge, chroma boost for chip); transition animations; prefetch on hover | Pending |

---

## Tenant model

modelrails_base is a **multi-tenant SaaS template**. The tenant unit is a **Workspace**. A single User can belong to multiple Workspaces with distinct roles in each.

Every user automatically gets a personal Workspace on signup. Personal workspaces exist in the data model but are currently hidden from the workspace-switcher in the main header (solo users feel single-tenant by default). The Settings hub described below intentionally *surfaces* the personal workspace as a distinct context — this is a deliberate divergence from the hide-it-everywhere pattern, scoped to the Settings surface.

## Data model truth (verified against code, not just convention)

There is **no `Account` model**. `/account/...` is purely a URL namespace for user-tier pages.

```
User ──┬── has_many :sessions
       ├── has_many :authentications     (OAuth providers per row, with pending/verified state)
       ├── has_one  :preferences         (UserPreferences: timezone, DND, retention, notification matrix)
       ├── has_many :memberships ──┬── workspace
       │                            ├── role           (Owner/Admin/Member/Viewer; permissions JSON)
       │                            └── (joins User ↔ Workspace)
       ├── has_many :workspaces, through: :memberships
       ├── has_many :project_memberships
       └── has_many :projects, through: :project_memberships

Workspace ──┬── has_many :memberships
            ├── has_many :users, through: :memberships
            ├── has_many :roles                (workspace-scoped custom roles supported)
            ├── has_many :invitations
            └── has_many :projects
```

User and Workspace are **peer entities**, joined by Membership (which carries the role).

User-tier fields: `User.name`, `User.email_address`, `User.avatar`, `Authentication.*`, `UserPreferences.*`. These are **one-per-User** — changing them affects you in every workspace. There is no per-workspace identity override today.

### Personal workspace is a real Membership row, not a special case

On signup, the auto-created personal workspace gets a normal `Membership` row with role `:owner` for that user. This means:

- `Current.workspace` works uniformly across personal and org contexts
- Pundit policies don't need `if personal?` branches
- `Tenanted` default scope just works

The `Workspace#personal?` predicate is implemented as a **column** (`workspaces.personal` boolean with a partial unique index scoped to the owning user) — not a query against `User.personal_workspace_id`. This keeps the predicate cheap (called on every switcher render).

### Future per-workspace identity

When per-workspace identity is introduced (preferred names, Slack-style nicknames), the data model will be designed *then*. The IA below absorbs either shape without navigation changes. **The brief does not commit to a specific future model.**

## Roles & permissions

- **Workspace roles**: Owner, Admin, Member, Viewer (system-seeded; custom workspace-scoped roles supported via permission JSON on `Role` model)
- **Project roles** (within a workspace): creator, editor, viewer (enum)

A User who is Owner in Workspace A and Viewer in Workspace B sees materially different UI in each — owner/admin affordances are gated at the **workspace level**, not the user level. Pundit policies enforce server-side; the UI mirrors.

### Sidebar items call the same Pundit policies as their controllers

Do not introduce a `SidebarPolicy`. Each sidebar link is wrapped in the policy method its destination controller's `authorize` call uses:

```erb
<%= nav_item_if_permitted(@workspace, action: :edit?) do %>
  <%= link_to "Profile", edit_workspace_path(@workspace) %>
<% end %>

<%= nav_item_if_permitted(Membership, action: :index?) do %>
  <%= link_to "Members", workspace_members_path(@workspace) %>
<% end %>
```

One source of truth for visibility — drift between sidebar and controller is impossible because they call the same code.

### Demotion-while-viewing handling

When a user's role changes mid-session (admin demoted to member while viewing Members), they must not get a half-rendered Turbo Frame state. Required pattern:

- `before_action :verify_workspace_membership` runs after `set_current_workspace`
- `rescue_from Pundit::NotAuthorizedError` redirects to workspace home with *"Your role changed"* flash, or to personal workspace if kicked out entirely
- Turbo Stream broadcast on Membership changes forces a sidebar re-render in any open tab

## Header structure (two distinct entry points to settings)

The app header carries **two top-level identity/navigation surfaces**, each a distinct entry point to the Settings hub:

| Header element | Entry point | Lands you in |
|---|---|---|
| **Avatar / username dropdown** | Click avatar → "Settings" | **Personal workspace context** in the Settings hub |
| **Workspaces link** (or workspace switcher) | Click → workspace list → select an org workspace | **That org workspace's context** in the Settings hub |

These are **not** redundant. Avatar = "settings about me." Workspaces link = "settings about a team I'm in." The user picks the entry point that matches their intent; the resulting sidebar shows context-appropriate items.

## Settings hub: context-adaptive sidebar

The Settings hub is a single navigational frame with a **workspace switcher at the top of its sidebar** and **a list of items that adapts based on the type of workspace currently selected**.

Critically: **"Profile" is a context-adaptive label**. Same word, different meaning depending on workspace type:

- In **personal workspace** context: Profile = the User's identity (name, email, avatar)
- In **org workspace** context: Profile = the Workspace's identity (name, description, logo, primary color)

This teaches users a generalizable rule: *"Profile = the identity of the workspace I'm currently in."*

### Disambiguation rules (so the polymorphic label doesn't confuse)

The label parallelism is a UX teaching tool. To prevent users from inferring wrong scope, three disambiguation layers are required:

| Layer | What it does | Audience |
|---|---|---|
| **Sidebar label** | Stays "Profile" (polymorphic) | Sighted users learning the generalizable rule |
| **Page `<h1>`** | Explicit: *"Your personal profile — visible in every workspace"* (personal) vs *"Acme Corp's profile"* (org) | Anyone reading the page, especially screen-reader users on page-load |
| **`aria-label` on sidebar link** | *"Profile, personal workspace"* vs *"Profile, Acme Corp"* | SR users navigating by links-list rotor (WCAG 2.4.4 / 2.4.9) |
| **Visual page skeleton** | Both Profile pages share the same layout grid (avatar/logo slot top-left, identity fields center, color/theme slot below) | All users — reinforces the polymorphism rule |

### Sidebar in personal workspace context

```
[DS] Davey Schmura (Personal) ▼          ← Workspace switcher

  Profile             →  edits User.name, User.email_address, User.avatar
  Notifications       →  edits UserPreferences (DND, channels, digest, retention)
  Security            →  password + Connected OAuth accounts (+ future sessions/2FA)
  Appearance          →  theme (light/dark/system) + timezone
```

### Sidebar in org workspace context (e.g., Acme Corp)

```
[AC] Acme Corp (Owner) ▼

  Profile             →  edits Workspace.name, description, logo, primary_color
  Members             →  workspace memberships + role management
  Invitations         →  pending invitations + invite link
  Limits & Plan       →  max_members, max_projects (future: plan/billing)
  (future) Notifications  →  per-workspace notification overrides
  (future) Integrations   →  workspace-scoped integrations
  (future) Billing
```

### Profile item anchors sidebar transitions

When the workspace switcher changes context and the sidebar items mutate, **Profile keeps its position** — same row, same icon slot. Other items animate in around it. This visual anchor reinforces the polymorphism rule rather than letting it read like a UI glitch.

### Rules the sidebar enforces

1. **Items appear only when they apply to the selected workspace's type.** A personal workspace has no Members, Invitations, or Limits. An org workspace has no Notifications/Security/Appearance — those are accessed by switching to personal context via the workspace switcher.

2. **Owner/admin gating applied within org sidebar.** A Viewer in Acme sees Profile (read-only) but does not see Members management, Invitations actions, or Limits & Plan. Pundit decides; the sidebar mirrors.

3. **The workspace switcher is the only way to change context.** Sidebar items never change context — only the switcher does.

4. **Personal workspace appears in the switcher.** Styled distinctly: avatar shape (circle = person, rounded-square = org — Slack/Linear/GitHub convention), distinct role badge slot, deliberate visual treatment for personal that doesn't read as "unstyled org" (see OKLCH guidance below).

## URL strategy

Personal context keeps existing `/account/...` URLs unchanged. The "personal workspace" is a *visual/navigational frame*, not a URL contract. Existing controllers, deep links from emails, and OAuth callbacks all continue to work.

| Sidebar item (personal context) | URL |
|---|---|
| Profile | `/account/profile/edit` (existing) |
| Notifications | `/account/notification_preferences/edit` (existing) |
| Security | `/account/connected_accounts` (existing) + future password/sessions |
| Appearance | `/account/theme_preference` (existing) + timezone |

Org context uses canonical Rails routes — the sidebar label "Profile" routes to `workspaces#edit`, *not* a fake `profile/edit` resource:

| Sidebar item (org context) | URL |
|---|---|
| Profile | `/workspaces/:slug/edit` (existing — `workspaces#edit`; gains logo + primary_color fields, currently in `BrandingController`) |
| Members | `/workspaces/:slug/members` (existing) |
| Invitations | `/workspaces/:slug/invitations` (existing) |
| Limits & Plan | `/workspaces/:slug/settings/edit` (existing — repurposed for non-identity config: max_members, max_projects, future plan/billing) |

### Route consolidation: `BrandingController` deleted

The current `/workspaces/:slug/branding/edit` route is removed entirely. Logo upload and primary_color picker move into `WorkspacesController#edit`. Existing branding view templates fold into the workspace edit form.

The current `/workspaces/:slug/settings/edit` page **drops** the identity fields (name, description) — they move to `workspaces#edit` — and retains operational config (limits, plan).

**Sidebar label "Profile" → URL `/workspaces/:slug/edit` is deliberate.** The IA teaches users a parallel concept; the URL honors Rails REST. Different audiences, different layers. Both are clean.

## Implementation guidance from panel review

### Workspace switcher

- **Single component, two visual variants.** Header dropdown (compact, closed-state-dominant) and sidebar inline-expanded list (always-open, current-item highlight) share data but not layout. Build them as two components consuming a shared `WorkspaceChip` atom (avatar/initials + name + role badge + kind indicator).
- **Personal workspace differentiation must not rely on color alone** (WCAG 1.4.1). Use avatar shape (circle vs rounded-square), explicit role badge, or icon affordance.
- **Visual differentiation must scale across the OKLCH primary_color spectrum.** Five workspaces side-by-side in the switcher all sitting at AAA-compliant lightness can look similar in yellow-green hues. Consider workspace initials over neutral background with primary_color as accent stripe, or a chroma-boosted swatch reserved for switcher-list contexts.

### OKLCH personal-context token set

Personal context cannot just "unset" `--color-primary-*` — that produces a workspace that looks like an org that forgot to pick a color. Define an explicit personal-context token ramp in `@theme`:

```css
[data-workspace-kind="personal"] {
  --color-primary-50: oklch(...);
  --color-primary-700: oklch(...);
  /* deliberate desaturated slate/zinc ramp, AAA-compliant */
}
```

Solo users spend most of their time in personal context. It should feel like *their* workspace, not "unstyled."

### Turbo / Hotwire architecture

- **Workspace switcher triggers a full Turbo visit with morph**, NOT a Turbo Frame swap. The switcher changes URL namespace AND the entire information scent. A frame swap creates "sidebar out of sync with URL" bugs and breaks `<html>`-level OKLCH variable updates.
- **Sidebar lives in the layout, keyed off `Current.workspace`.** No `<turbo-frame>` wrapping the sidebar. Morph keeps focus/scroll across navigation.
- **Use `<%= turbo_refreshes_with method: :morph %>` site-wide** + `broadcast_refresh_to current_user` on Membership changes. When an admin demotes someone, the demoted user's open tabs re-render automatically.
- **Prefetch on hover** with `data-turbo-prefetch` — hovering the avatar dropdown can prefetch `/account/profile/edit`; hovering a workspace prefetches its edit page.

### Accessibility (WCAG 2.2 AAA baseline maintained)

- **`aria-live="polite"` region in the layout** announces context changes. On workspace switch: one coherent announcement — *"Switched to Acme Corp, Owner. Settings menu updated: Profile, Members, Invitations, Limits and Plan."* (WCAG 4.1.3)
- **Focus stays on the workspace switcher** after selection. Sidebar update is announced via live region; focus does not jump to main panel.
- **Page `<h1>` and `<title>` always name the current context** — *"Settings — Acme Corp"* vs *"Settings — Your account"*. Turbo updates `document.title` by default on navigation; verify this isn't suppressed by frame-only updates (it isn't, because the sidebar isn't a frame).

### Query performance

The workspace switcher renders in BOTH the main header AND the Settings hub sidebar. Without care, this doubles the query cost per Settings-hub page.

- **Single `WorkspaceSwitcherComponent`** with a required preloaded scope as a local. Never re-query internally.
- **Preload pattern:**

```ruby
Current.user_workspaces ||=
  Workspace
    .joins(:memberships)
    .where(memberships: { user_id: current_user.id })
    .includes(:roles, logo_attachment: { blob: { variant_records: :image_attachment } })
    .preload(memberships: :role)
    .merge(Membership.where(user_id: current_user.id))
```

- **Bullet regression spec** asserting ≤ 2 workspace queries per Settings-hub page render.
- **`Workspace#personal?` is a column read**, not a query — backed by `workspaces.personal` boolean.

### Authorization defense

- **`Current.workspace` re-validated on every request** against `current_user.workspaces`. Never trust a session/cookie/param for which workspace is active. Cheap (one index hit).
- **Controller-level `authorize` is the source of truth**, not sidebar visibility. A Viewer hitting `/workspaces/:slug/members` directly must get a 403 — the sidebar hiding the link is decoration, not security.

### Testing strategy

- **Parameterized role-gate matrix:** 4 roles × 2 workspace types × ~7 sidebar items. One request-spec table covers visibility; per-resource Pundit specs cover authorization.
- **One happy-path system spec per workspace type** (personal + org) + one Viewer-in-org case for read-only Profile / no-Members.
- **Demotion-while-viewing system spec**: user is on Members page, role changes mid-session, next action redirects gracefully.

## Design constraints (template-wide)

- **WCAG 2.2 Level AAA** is the project baseline. 7:1 contrast on all foreground/background pairs, 44×44px minimum touch targets, visible focus indicators, full keyboard navigation, screen-reader-narrated transitions.
- **TailwindCSS 4 with OKLCH dynamic theming.** Workspace `primary_color` cascades into the UI via CSS variables when in org-workspace context. Personal context has its own explicit token ramp (see implementation guidance above).
- **Light + dark mode parity** required for every surface. axe-core CI runs at wcag2aaa in both modes.
- **Stimulus actions only** for interactivity. Strict CSP — no inline `onclick`/`onchange`/etc.
- **Turbo / Hotwire** is the navigation model. Full Turbo visits with morph for context changes; Turbo Streams for real-time updates.

## What this means for adapting single-tenant designs

1. **Single-tenant settings designs (Lumina-style) translate the *component patterns*, not the *navigation structure*.** Notification-type cards, delivery-method tiles, quiet-hours UX, two-column section/preview layouts can be lifted directly. Top-level sidebar that mixes "Team Members" with "Profile" under one undifferentiated list does NOT translate — those are different workspace-type contexts in this template.
2. **There is no single "Account Settings" surface in this template.** Don't design one. Settings live in workspace contexts, with the personal workspace serving as the home for user-level settings.
3. **The Profile label is intentionally polymorphic across contexts.** Resist the urge to differentiate it in the sidebar — the parallel naming is teaching users a generalizable rule. Disambiguation lives at the H1, aria-label, and page-skeleton layers, not the sidebar.
4. **Workspace switcher is the load-bearing context-control.** Single component, two visual variants (header dropdown + sidebar inline-expanded). Personal-vs-org distinction expressed via avatar shape, role badge, and explicit OKLCH token differentiation — never color alone.
5. **Two entry points are deliberate, not redundant.** Avatar dropdown → personal. Workspaces link → org workspace selection. The IA respects user intent at the entry point.

## Existing User-tier pages (reference)

- `/account/profile/edit` — name, email, avatar
- `/account/avatar/hub` — avatar/identity management hub (subsumed by Profile in the new design)
- `/account/connected_accounts` — OAuth providers + verification state
- `/account/notifications` — notification triage (received items, distinct from preferences)
- `/account/notification_preferences/edit` — DND, category × channel matrix, digest cadence, retention
- `/account/theme_preference` — light/dark/system toggle
- `/account/preferences/timezone` — IANA timezone

## Existing Workspace-tier pages (reference)

- `/workspaces/:slug` — workspace home/dashboard
- `/workspaces/:slug/edit` — **workspaces#edit, will become the canonical workspace identity page** (Phase 1 lands logo + primary_color)
- `/workspaces/:slug/settings/edit` — workspace operational config (limits, plan) — identity fields removed by Phase 1
- `/workspaces/:slug/branding/edit` — **deleted by Phase 1** (folded into `workspaces#edit`)
- `/workspaces/:slug/members` — workspace memberships + role management
- `/workspaces/:slug/invitations` — invitation management
- `/workspaces/:slug/projects/...` — project-level resources

## Panel review (cross-references)

Both panels signed off unanimously after two rounds:

- **Frontend / UX / User flows:** Adam Wathan (CSS/OKLCH), Marcy Sutton (a11y), Steve Schoger (visual/IA), Jorge Manrubia (Hotwire)
- **Backend / Architecture / Permissions / Performance:** DHH (Rails conventions), Chris Oliver (practical Rails/Pundit), Dave Thomas (software design), Joël Quenneville (queries/testing)

Cross-panel facilitators throughout: Sandi Metz (cost of change), Jim Weirich (does this bring joy?), Charity Majors (what fails at 3am?).
