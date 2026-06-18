# Identity Phase 2c-2 — "your workspace" desaturation + context banner (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Close out Phase 2 with two small workspace-page polishes: (1) make a **personal/your workspace render desaturated** on its own pages (not the sky-210 "org that forgot to pick a color" look) — the desaturated CSS already exists, we just wire it onto the application layout; (2) a slim **"You're in [X]" context banner** above workspace content, shown only when the user belongs to 2+ workspaces (matched to the header switcher's collapse-when-one). Spec: `docs/superpowers/specs/2026-06-18-identity-account-model-clarity-design.md`. Execute after #354 merges.

**Architecture:** Both changes live in `app/views/layouts/application.html.erb` (the workspace-pages layout). (1) The `<main>` currently always uses `data-workspace-branded` + an inline `--ws-primary-*` hue style; we branch it — `Current.workspace.personal?` → `data-workspace-kind="personal"` (the existing desaturated slate ramp in `application.css:277`), else → `data-workspace-branded` (the hue). No new CSS. (2) A new `shared/_workspace_context_banner` partial rendered above the workspace container, guarded by `switcher_workspaces.size > 1` (reusing the 2b helper — memoized so the banner + header switcher share one query). **Keep the banner subtle** (slim strip, small muted text) — the maintainer flagged it may be "too much" and will browser-review.

**Tech Stack:** Rails 8.1, Ruby 4.0.4 (`mise exec --`), Tailwind v4 / OKLCH (existing tokens — no new ones), modelrails_ui (semantic tokens, AAA — CI-only). TDD; full suite green before every commit; commit but **DO NOT push**; never bypass Lefthook.

## File Structure

| File | Action | Note |
|---|---|---|
| `app/views/layouts/application.html.erb` | Modify (~L46–49) | branch `<main>`: personal → `data-workspace-kind="personal"`, org → `data-workspace-branded` + hue; render the banner above the workspace container |
| `app/helpers/workspace_helper.rb` | Modify | memoize `switcher_workspaces` (so banner + switcher share one load) |
| `app/views/shared/_workspace_context_banner.html.erb` | **Create** | the slim "You're in [X]" strip |
| `config/locales/en/workspaces.en.yml` | Modify | `workspaces.context_banner.*` |
| `spec/requests/workspace_theming_spec.rb` | **Create** | personal → `data-workspace-kind`, org → `data-workspace-branded` |
| `spec/requests/workspace_context_banner_spec.rb` | **Create** | banner present at 2+ workspaces, absent at 1, names current |

---

## Task 1 — desaturate "your workspace" on its own pages

- [ ] **Step 1: Request spec (RED).** `spec/requests/workspace_theming_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Workspace theming (main element)", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "renders a personal workspace desaturated (data-workspace-kind=personal, no hue brand)" do
    personal = user.workspaces.kept.find(&:personal?)
    get workspace_path(personal)
    expect(response.body).to include('data-workspace-kind="personal"')
    expect(response.body).not_to match(/data-workspace-branded[^>]*--ws-primary/)
  end

  it "renders an org workspace branded with its hue" do
    org = create(:workspace, primary_color: 145)
    create(:membership, :owner, user: user, workspace: org)
    get workspace_path(org)
    expect(response.body).to include("data-workspace-branded")
    expect(response.body).to include("oklch(0.40 0.15 145)")
  end
end
```

- [ ] **Step 2: Run → FAIL** (today the personal workspace gets `data-workspace-branded` + hue 210).

- [ ] **Step 3: Branch the `<main>`** in `app/views/layouts/application.html.erb` (the existing `data-workspace-branded` + inline `--ws-primary-*` block, ~L46–49). One `<main>`, conditional attributes:

```erb
<main id="main-content" tabindex="-1" class="flex-1 min-w-0"
  <% if Current.workspace.personal? %>
      data-workspace-kind="personal">
  <% else %>
      <% ws_hue = Current.workspace.primary_color || 210 %>
      data-workspace-branded
      style="--ws-primary-light: oklch(0.40 0.15 <%= ws_hue %>); --ws-primary-dark: oklch(0.78 0.10 <%= ws_hue %>);">
  <% end %>
  <%= render "shared/workspace_back_link" %>
  <%= yield %>
</main>
```

(Verify the rendered tag is well-formed — exactly one `>` closes the opening tag in each branch.)

- [ ] **Step 4: Run the spec → PASS.** Full suite green; commit (do NOT push):

```bash
mise exec -- bundle exec rspec
git add app/views/layouts/application.html.erb spec/requests/workspace_theming_spec.rb
git commit -m "feat(theming): personal workspaces render desaturated on their own pages (reuse data-workspace-kind ramp)"
```

---

## Task 2 — the "You're in [X]" context banner

- [ ] **Step 1: Memoize the switcher helper** so the banner doesn't re-query. In `app/helpers/workspace_helper.rb`, change `switcher_workspaces` to memoize: `@switcher_workspaces ||= Current.user.workspaces.kept.includes(:logo_attachment, memberships: :role)`.

- [ ] **Step 2: Request spec (RED).** `spec/requests/workspace_context_banner_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Workspace context banner", type: :request do
  let(:user) { create(:user) }                       # :personal → 1 workspace
  before { sign_in(user) }

  it "is absent with a single workspace" do
    get workspace_path(user.workspaces.first)
    expect(response.body).not_to include("workspace-context-banner")
  end

  it "shows 'You're in [name]' when the user has 2+ workspaces" do
    org = create(:workspace)
    create(:membership, :owner, user: user, workspace: org)
    get workspace_path(org)
    expect(response.body).to include("workspace-context-banner")
    expect(response.body).to include(CGI.escapeHTML(org.name))
  end
end
```

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Locale.** Add to `config/locales/en/workspaces.en.yml` under `en: workspaces:`:

```yaml
    context_banner:
      in_workspace_html: "You're in %{name}"
```

- [ ] **Step 5: The partial.** `app/views/shared/_workspace_context_banner.html.erb` — slim, subtle, AAA, semantic tokens:

```erb
<%# Slim workspace-context bar — shown only when the user belongs to 2+
    workspaces (the header switcher is present then too). Keep it subtle. %>
<% if Current.workspace && switcher_workspaces.size > 1 %>
  <div id="workspace-context-banner" role="status"
       class="bg-surface-sunken border-b border-border px-4 py-1.5 text-xs text-text-body">
    <%= t("workspaces.context_banner.in_workspace_html",
          name: tag.strong(Current.workspace.name, class: "font-medium text-text-heading")) %>
  </div>
<% end %>
```

- [ ] **Step 6: Render it** in `app/views/layouts/application.html.erb`, inside the `<% if Current.workspace %>` block, immediately BEFORE the `<div class="flex-1 flex flex-col md:flex-row …">` workspace container (so it's a full-width strip between the header and the sidebar+main area): `<%= render "shared/workspace_context_banner" %>`.

- [ ] **Step 7: Run the spec → PASS.** Full suite green; commit (do NOT push):

```bash
mise exec -- bundle exec rspec
git add app/helpers/workspace_helper.rb app/views/shared/_workspace_context_banner.html.erb app/views/layouts/application.html.erb config/locales/en/workspaces.en.yml spec/requests/workspace_context_banner_spec.rb
git commit -m "feat(workspace): slim 'You're in [X]' context banner (2+ workspaces; matches the switcher)"
```

---

## Self-review

- **No new CSS / tokens** — Task 1 reuses the existing `[data-workspace-kind="personal"]` desaturated ramp; Task 2 uses semantic tokens.
- **Banner is subtle + matched** — appears exactly when the header switcher does (`switcher_workspaces.size > 1`); slim strip, muted text. The maintainer will browser-review and may dial it back.
- **No N+1** — `switcher_workspaces` memoized; banner + switcher share one load.
- **`:none`-safe** — under `:none` a workspaceless user on `/me` has no `Current.workspace`, so neither change fires; the banner only shows inside a workspace.
- **AAA** — proven in CI (a system-spec axe pass is optional here; the request specs cover structure). Consider adding the banner to an existing workspace-page system spec's axe scope if one exists.

## Execution handoff

1. **Subagent-Driven (recommended)** — implementer per task + review.
2. **Inline** — `superpowers:executing-plans`.

> After 2c-2 merges, **Phase 2 is complete** — the identity model is named, documented, and fully migrated to.
