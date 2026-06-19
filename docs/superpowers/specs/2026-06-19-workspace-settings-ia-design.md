# Workspace Settings IA — decouple identity from the personal workspace (Design)

> **Source:** a 5-expert review panel (Jason Fried, Chris Oliver, Steve Schoger, Léonie Watson, DHH) on the sidebar-settings confusion, 2026-06-19. Follow-up to the identity-account-model-clarity arc (`docs/superpowers/specs/2026-06-18-identity-account-model-clarity-design.md`, §9 "Settings bifurcation").

## 1. Problem

Under the `:personal` posture a new user gets an auto-created **personal workspace** ("Dave's workspace"). The workspace sidebar (`app/views/shared/_workspace_sidebar_items.html.erb`) shows **Overview · Projects · Settings**. Clicking **Settings** routes to `edit_workspace_path` = `/workspaces/:slug/edit` (`WorkspacesController#edit` — the workspace *profile*: name, logo, primary_color), rendered with `layout "settings"`.

But the settings layout's sidebar (`app/views/shared/_settings_sidebar_items.html.erb`) branches on `SettingsNavigationHelper#settings_context_kind`, which returns `:personal` whenever `Current.workspace.personal?`. So for a personal workspace it renders the user's **identity** settings — Profile (→ `/settings/profile/edit`, the *account* profile), Notifications, Security, Appearance — and the entire left sidebar **wholesale-swaps** from the workspace nav to the account nav.

The result: **the page is about the workspace; the sidebar is about you**, and "Profile" links *away* to your account, not the workspace you clicked into. Identity settings now have **two doors** (this link + the avatar menu). On an *org* workspace the same flow is coherent (Settings = Members/Invitations/Limits admin); the personal case is where the code's "personal workspace ≈ you" assumption — the exact conflation the identity arc set out to kill — surfaces in the nav.

## 2. Decision

Identity settings belong to the **user** (avatar menu → `/settings`, account-independent). Workspace settings belong to the **workspace**. No workspace nav routes into identity settings, and the shared settings layout's `personal?` branching is deleted. Sequenced in two phases by cost.

## 3. Panel findings (rationale)

All five reviewers named the same root cause (the identity/tenant conflation) and **rejected all three** initially-floated fixes:

- **Tabs** — "solves the wrong problem"; tabs imply the items are co-equal siblings, cementing the false equivalence (4 of 5). The right *component* only if account settings move out first (Schoger); more navigable for AT *only* with managed focus, and doesn't fix the silent swap (Watson).
- **Identity settings in the Overview** — unanimous no; mixes scopes, buries the account door inside a workspace view.
- **Different link origin** — unanimous "band-aid"; doesn't change where it lands.

They **converged**: remove the personal-workspace door into identity settings; identity = the avatar menu (one door); org unchanged. DHH added the structural fix — a shared layout serving two masters off `personal?` is the disease; split it and **delete `settings_context_kind`** ("deletion over abstraction"). Watson flagged the personal context-switch as silent (`current_workspace_announcement_for_aria_live` returns `nil` for personal) — but on verification this did **not** hold: the announcer reads a separate **static** personal value (`app/views/layouts/settings.html.erb:26`), so personal is already announced. No a11y change is needed (see §4).

## 4. The design

### Phase 1 — decouple the nav + a11y

- **Personal-workspace sidebar → Overview · Projects** (drop the "Settings" item in `_workspace_sidebar_items.html.erb`, ~L44–48). The Settings item stays for **org** workspaces.
- **Personal workspace name/logo → a "Customize" affordance on the Overview** (workspace context — rename + logo; color stays desaturated per the 2c-2 ramp). *(maintainer decision)*
- **Identity settings → avatar-menu name row → `/settings`, unchanged.** No new avatar-menu item. *(maintainer decision)*
- **a11y (investigated → no change needed):** the announcer already wires a static `data-settings-announcer-personal-value` (`app/views/layouts/settings.html.erb:26`) that `settings_announcer_controller.js` reads for `kind="personal"`, so the personal context-switch is announced. `current_workspace_announcement_for_aria_live`'s `nil` feeds the *org* value only and is correct. Watson's proposed fix is dropped (see §3).

### Phase 2 — split the shared settings layout

- Split `layout "settings"` into an **identity-settings** context (`/settings/*`, Profile/Notifications/Security/Appearance, account-independent) and a **workspace-settings** context (`/workspaces/:slug/*`, Profile/Members/Invitations/Limits, org admin). Shared visual chrome (header/footer/a11y scaffolding) stays DRY.
- **Delete `settings_context_kind`** + the personal/org branching in `_settings_sidebar_items.html.erb` → two focused sidebars; routing decides which renders, no conditional.
- `WorkspacesController#edit` renders the workspace profile in the *workspace* context — for a personal workspace it's reached from the Overview "Customize" affordance, so it never wears the identity sidebar.

## 5. Before / after (the personal-workspace experience)

**Before:** workspace sidebar [Overview · Projects · **Settings**] → click Settings → page = workspace profile, sidebar = [Profile→account · Notifications · Security · Appearance]. Two doors to identity; silent swap.

**After:** workspace sidebar [Overview · Projects]; the Overview carries a small "Customize" (rename/logo). Identity settings only via the avatar menu → `/settings`. The workspace-profile edit, when reached, stays in the workspace context. One door to identity; announced context-switch.

Org workspaces are unchanged: [Overview · Projects · Settings] → workspace admin.

## 6. Phased scope (sequenced by cost)

- **Phase 1 (cheap; resolves the reported jarring):** the nav decouple (drop personal Settings) + the Overview "Customize" affordance + the a11y announcement. Mostly view/helper changes; no routing/layout restructure.
- **Phase 2 (structural; the proper fix):** the layout split + deleting `settings_context_kind`. Touches routing/layout; execute after Phase 1 lands.

## 7. Non-goals

- Not redesigning the identity-settings pages themselves.
- Not changing org-workspace settings (coherent today).
- Not adding a new avatar-menu "Settings" item (the name row already opens Settings; maintainer chose leave-as-is).
- Not capping or re-architecting the personal workspace — it stays a real, growable tenant.

## 8. Open edges (decide at plan time, not blocking)

- Whether the personal workspace's profile-edit stays a small workspace-context page (reached from "Customize") or folds inline into the Overview as a rename field + logo control.
- The exact placement/label of the Overview "Customize" affordance (a header action vs a card).
- Whether Phase 2's two contexts share one layout file with two sidebar partials, or two layout files — an implementation call for the plan.

## 9. Files in play

- `app/views/shared/_workspace_sidebar_items.html.erb` — (P1) drop the personal Settings item.
- The workspace Overview view (`app/views/workspaces/show.html.erb` or equivalent) — (P1) the "Customize" affordance.
- `app/helpers/settings_navigation_helper.rb` — (P1) the a11y announcement; (P2) delete `settings_context_kind`.
- `app/views/shared/_settings_sidebar_items.html.erb` — (P2) remove the personal/org branching.
- `app/controllers/workspaces_controller.rb` — (P2) the edit layout/context.
- `app/views/layouts/settings.html.erb` (+ a new workspace-settings layout/sidebar) — (P2) the split.
- Specs: settings-sidebar visibility/context specs, the workspace-sidebar spec, the a11y announcer spec.
