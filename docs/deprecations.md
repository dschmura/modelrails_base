# Deprecations

Tracked items that are intentionally kept but labeled for future removal.
Each entry names the **removal trigger** — the event that unblocks the cleanup.
Until that trigger fires, the branches stay in place and are not considered bugs.

---

## `Workspace#personal?` — presentation-layer call-sites

### Current call-sites (as of 2026-06-18)

The `personal?` predicate is read directly in two presentation-layer locations:

- **`settings_navigation_helper#settings_context_kind`** — returns `:personal` or `:org` to drive which sidebar section renders.
- **`workspace_helper#workspace_icon_for`** — falls back to the workspace owner's avatar only when `workspace.personal?`.

Note: `_settings_sidebar_switcher.html.erb` also reads `personal?` for avatar shape, but that partial is no longer rendered from the settings sidebar (removed in Phase 2c-1 Task 2 — the header switcher supersedes it). It remains in use from `_workspace_sidebar_items.html.erb`.

These branches are guarded by `:personal` posture checks at the application level, so they are dead under `:none` — but they still execute and are read directly by views/helpers.

### Why this is debt, not just a dead column

Under `:none`, every `personal?` branch in the presentation layer (`settings_navigation_helper#settings_context_kind`, `workspace_helper#workspace_icon_for`) is dead — yet it's read directly by views/helpers. That's a *presentation leak*: how a workspace is shown/treated is decided by scattering `Workspace#personal?` reads across the UI rather than asking one posture-aware seam.

**Candidate refactor** (when the `personal` column is removed, or a second onboarding posture stresses the same seam): introduce a single posture-aware presentation seam — a presenter or helper that answers "how should this workspace be presented/treated under the current onboarding posture?" — and demote `personal` to an implementation detail behind it. Until then the branches stay labeled and tied to the removal trigger above.

### Removal trigger

Remove or consolidate these call-sites when **either** of the following fires:

1. The `personal` boolean column is removed from the `workspaces` table (requires all `:personal`-posture users to have migrated off).
2. A second onboarding posture stresses the same `personal?` seam — at that point the scattering becomes a maintenance hazard and the presenter/seam refactor pays for itself immediately.
