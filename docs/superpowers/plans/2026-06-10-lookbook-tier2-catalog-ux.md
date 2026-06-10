# Lookbook Tier 2 — catalog UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Lookbook theme toggle into the chrome toolbar (2b), confirm the canonical `ui` call is copyable via the Source panel (2a), and add an all-variants showcase scenario to 6 variant-axis components (2c).

**Architecture:** Two independent shippable phases / PR-pairs. **Phase A (PR-A, catalog chrome):** 2a + 2b — both edit `component_preview.html.erb` + the Lookbook initializer. **Phase B (PR-B, showcase):** 2c — additive template-backed scenarios + 0b axe specs. Gem-first (generator templates), then app-adopt; same cross-repo groove as Tier 1.

**Tech Stack:** Ruby 4.0.4, Rails 8.1, Lookbook 2.3.14, ViewComponent, Minitest (gem), RSpec + Playwright/axe (app).

**Spec:** `docs/superpowers/specs/2026-06-10-lookbook-tier2-catalog-ux-design.md`

**Reference — verified mechanisms (lookbook-2.3.14):**
- `config.lookbook.preview_display_options = { theme: %w[light dark] }` renders a toolbar dropdown (`preview_entity.rb:157`); the rendered layout reads the choice via `params.dig(:lookbook, :display, :theme)`.
- The app 0b axe harness drives dark mode itself (`spec/support/playwright_accessibility.rb:241 set_theme` toggles `html.classList` + a `theme` cookie via JS), **independent of the preview-theme button** — so removing the button does not affect dark-mode AAA coverage.
- The gem generator copies `component_preview.html.erb` and `preview_theme_controller.js` via `copy_file` (raw copy — ERB in the `.html.erb` stays literal for Rails to evaluate at app runtime). `copy_preview_theme_controller` is `lookbook_generator.rb:21`.
- No Lookbook config sets the default inspector panel in 2.3.14; the Source panel is shown by default. 2a is therefore verification + a targeted doc audit.

**Toolchain:** prefix Ruby with `PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH"`. The gem repo (`/Users/dschmura/Documents/code/modelrails_ui`) is OUTSIDE the app working dirs — edit gem files via Bash heredoc / ruby / sed (Write/Edit may be blocked there); never `git add -A` (gem has untracked `docs/design/*` — wait, those were committed; still, stage explicitly).

---

# PHASE A — Catalog chrome (PR-A): 2a + 2b

## Task A1: Gem branch setup

**Files:** none (git only).

- [ ] **Step 1: Create the gem branch off modelrails/harden**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
git fetch origin -q
git switch modelrails/harden -q && git pull --ff-only -q
git switch -c harden/lookbook-tier2-chrome
git branch --show-current   # => harden/lookbook-tier2-chrome
```

(The app is already on `feat/lookbook-tier2-catalog-ux`, which carries the spec + this plan.)

## Task A2: 2b — theme display option + param-driven layout (gem template + app)

**Files:**
- Modify (gem): `/Users/dschmura/Documents/code/modelrails_ui/lib/generators/modelrails_ui/lookbook/templates/component_preview.html.erb`
- Modify (gem): `/Users/dschmura/Documents/code/modelrails_ui/lib/generators/modelrails_ui/lookbook/templates/lookbook.rb`
- Modify (app): `/Users/dschmura/Documents/code/modelrails_base/app/views/layouts/component_preview.html.erb`
- Modify (app): `/Users/dschmura/Documents/code/modelrails_base/config/initializers/modelrails_ui_lookbook.rb`

- [ ] **Step 1: Register the `theme` display option (gem template `lookbook.rb`)**

Add this line inside the `if Rails.env.development?` block, after the `page_paths` line:

```ruby
  Rails.application.config.lookbook.preview_display_options = { theme: %w[light dark] }
```

- [ ] **Step 2: Register the same in the app initializer**

In `config/initializers/modelrails_ui_lookbook.rb`, after the `page_paths` line (inside the `Rails.env.development?` gating), add:

```ruby
  Rails.application.config.lookbook.preview_display_options = { theme: %w[light dark] } if Rails.env.development?
```

- [ ] **Step 3: Rewrite the app layout — read the theme param, drop the button**

Replace the entire contents of `app/views/layouts/component_preview.html.erb` with:

```erb
<!DOCTYPE html>
<html lang="en" class="<%= "dark" if params.dig(:lookbook, :display, :theme) == "dark" %>">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title><%= content_for?(:title) ? yield(:title) : "UI component preview" %></title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-surface-raised text-text-body p-6">
    <%# Theme is driven by Lookbook's `theme` display option (toolbar dropdown); the
        non-Lookbook host (VC preview controller) renders light, and the axe harness
        forces .dark itself. See docs/superpowers/specs/2026-06-10-lookbook-tier2-catalog-ux-design.md %>
    <%= yield %>
  </body>
</html>
```

- [ ] **Step 4: Mirror the layout into the gem template**

Write the SAME content (Step 3) to the gem template `.../templates/component_preview.html.erb`, EXCEPT drop the `<title>` line's `content_for?` if the gem template lacked it — match the gem template's existing head otherwise. Use a Bash heredoc (`cat > path <<'ERB'`). Concretely, the gem template head has no `<title>` line currently; keep it without one to match, but DO add the `class=` on `<html>` and remove the toggle `<div>`. Final gem template:

```erb
<!DOCTYPE html>
<html lang="en" class="<%= "dark" if params.dig(:lookbook, :display, :theme) == "dark" %>">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-surface-raised text-text-body p-6">
    <%= yield %>
  </body>
</html>
```

- [ ] **Step 5: Live-verify the toolbar toggle (app, fresh dev server)**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bin/rails server -p 3002 -P /tmp/lb_t2.pid -e development &
# wait for boot, then:
curl -s -o /dev/null -w '%{http_code}\n' --retry 20 --retry-delay 2 --retry-all-errors "http://localhost:3002/lookbook/inspect/Actions/button/primary"
# dark via the display param:
curl -s "http://localhost:3002/lookbook/preview/Actions/button/primary?lookbook%5Bdisplay%5D%5Btheme%5D=dark" | grep -o '<html[^>]*>' | head -1
# expect: <html lang="en" class="dark">
curl -s "http://localhost:3002/lookbook/preview/Actions/button/primary" | grep -o '<html[^>]*>' | head -1
# expect: <html lang="en" class="">
kill "$(cat /tmp/lb_t2.pid)" 2>/dev/null; rm -f /tmp/lb_t2.pid
```

Expected: the dark URL renders `<html ... class="dark">`, the plain URL `class=""`. If the param path differs, open `/lookbook` in a browser, pick a component, and confirm a **Theme** dropdown appears in the toolbar and flipping it re-renders dark/light. (Do NOT proceed to cleanup until the toolbar control demonstrably flips the theme.)

- [ ] **Step 6: Commit both repos**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui && git add lib/generators/modelrails_ui/lookbook/templates/component_preview.html.erb lib/generators/modelrails_ui/lookbook/templates/lookbook.rb && \
  git commit -m "feat(lookbook): theme via preview_display_options toolbar control (drop in-canvas button)"
cd /Users/dschmura/Documents/code/modelrails_base && git add app/views/layouts/component_preview.html.erb config/initializers/modelrails_ui_lookbook.rb && \
  git commit -m "feat(lookbook): theme via preview_display_options toolbar control (drop in-canvas button)"
```

## Task A3: 2b cleanup — remove the bespoke controller, generator step, obsolete spec

**Files:**
- Delete (gem): `.../templates/preview_theme_controller.js`
- Modify (gem): `.../lookbook/lookbook_generator.rb` (remove `copy_preview_theme_controller`)
- Delete (app): `app/javascript/controllers/preview_theme_controller.js`
- Delete (app): `spec/system/ui/preview_theme_toggle_spec.rb`

- [ ] **Step 1: Remove the gem generator step + template**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
git rm lib/generators/modelrails_ui/lookbook/templates/preview_theme_controller.js
# delete the copy_preview_theme_controller method (and its preceding comment block) from lookbook_generator.rb
ruby -i -e '
  src = File.read("lib/generators/modelrails_ui/lookbook/lookbook_generator.rb")
  src.sub!(/\n\s*# Self-contained light\/dark toggle.*?def copy_preview_theme_controller.*?\n\s*end\n/m, "\n")
  src.sub!(/\n\s*def copy_preview_theme_controller.*?\n\s*end\n/m, "\n") # fallback if no comment
  File.write("lib/generators/modelrails_ui/lookbook/lookbook_generator.rb", src)
' lib/generators/modelrails_ui/lookbook/lookbook_generator.rb
grep -c "preview_theme" lib/generators/modelrails_ui/lookbook/lookbook_generator.rb   # expect 0
```

- [ ] **Step 2: Run the gem suite (regression — generator + structural tests)**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rake 2>&1 | tail -8
```

Expected: 0 failures, 0 offenses. If a generator/structural test asserted `preview_theme_controller.js` is copied, fix that test (remove the assertion) and re-run.

- [ ] **Step 3: Remove the app vendored controller + obsolete spec**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
git rm app/javascript/controllers/preview_theme_controller.js spec/system/ui/preview_theme_toggle_spec.rb
# confirm nothing else references the controller:
grep -rn "preview-theme\|preview_theme" app/ spec/ | grep -v "playwright_accessibility" || echo "no remaining references"
```

Expected: "no remaining references" (the axe harness uses its own `theme` cookie + direct `.dark` toggle, not `preview-theme`).

- [ ] **Step 4: Run the FULL app suite — both-theme axe is the proof**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec 2>&1 | grep -E "examples?, [0-9]+ failure"
```

Expected: 0 failures. Every 0b axe spec runs `axe_clean_in_both_themes?` — a green run proves the param-driven theme still produces a correct dark render. (If a flake hits, re-run; see the Tier 1 plan's CI=true note.)

- [ ] **Step 5: Commit both repos**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui && git add -A lib/ test/ && git status && \
  git commit -m "refactor(lookbook): remove bespoke preview-theme controller + generator step"
cd /Users/dschmura/Documents/code/modelrails_base && git add -A app/ spec/ && git status && \
  git commit -m "refactor(lookbook): remove bespoke preview-theme controller + obsolete toggle spec"
```

(Verify `git status` shows only the intended deletions/edits before committing; do not sweep untracked files.)

## Task A4: 2a — verify Source-panel coverage + targeted doc audit

**Files:** possibly a few preview `.rb` doc-comments (app + gem) — expected to be few or none.

- [ ] **Step 1: Verify the Source panel shows a copyable canonical call for each preview TYPE**

With a dev server running (`bin/rails server -p 3002`), open `/lookbook` and check three representatives:
- **template-backed** (e.g. `card` → default): Source tab shows the scenario's `.html.erb` (the `ui :card` / markup) — copyable. ✓
- **inline playground** (e.g. `button` → playground): Source shows the `ui :button, label, variant: ...` Ruby method — the call is visible. ✓
- **compound** (e.g. `dialog` → default): Source shows `render "shared/modal"` / `render "shared/confirm_dialog"` — the real paste-ready usage. ✓

Record the finding. If all three show the call, 2a's mechanism is satisfied by Lookbook's default Source panel.

- [ ] **Step 2: Targeted doc-lead audit (fix only genuine gaps)**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
# list previews whose doc-comment never shows a `ui :<name>` or `render "shared` call anywhere:
for f in spec/components/previews/ui/*_component_preview.rb; do
  grep -q "ui :\|render \"shared" "$f" || echo "no inline call shown: $f"
done
```

For each flagged preview (expected: few/none), confirm via the Source panel whether the call is already discoverable there. Only if a component's call is genuinely invisible (not in Source, not in docs), add a one-line usage example to its doc-comment. **Do not** add usage snippets where Source already shows the call — that's the rejected option B.

- [ ] **Step 3: Commit (only if Step 2 produced changes)**

```bash
# if doc edits were made (mirror identical edits to the gem templates):
git add spec/components/previews/ui/ && git commit -m "docs(lookbook): lead the doc-comment with the ui call where it was buried"
# gem side, if applicable, similarly.
# If NO changes: skip — record "2a satisfied by default Source panel; no doc edits needed".
```

## Task A5: PR-A choreography

- [ ] **Step 1: Push + open PRs (PAUSE for user go-ahead first, per proactive-merge)**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui && git push -u origin harden/lookbook-tier2-chrome
gh pr create --base modelrails/harden --title "feat(lookbook): Tier 2 chrome — theme toolbar control + source-panel canonical call" --body "..."
cd /Users/dschmura/Documents/code/modelrails_base && git push -u origin feat/lookbook-tier2-catalog-ux
gh pr create --base main --title "feat(lookbook): Tier 2 chrome — theme toolbar control + source-panel canonical call" --body "..."
```

- [ ] **Step 2: Watch both PRs' CI to green** (`gh pr checks <N> --watch`). The app `test` job runs the full both-theme AAA axe suite. Gem CI runs bare `rake` (tests + RuboCop). Rerun transient flakes; never bypass.

---

# PHASE B — All-variants showcase (PR-B): 2c

**Scope:** `button`, `badge`, `alert`, `banner`, `indicator`, `chat_bubble`. Branch off `main` AFTER PR-A merges (or off PR-A's branch if running back-to-back).

## Task B1: Branch setup + button showcase EXEMPLAR

**Files:**
- Create (gem): `.../previews/ui/button_component_preview/showcase.html.erb`
- Modify (gem): `.../previews/ui/button_component_preview.rb` (add `def showcase; end`)
- Create (app): `spec/components/previews/ui/button_component_preview/showcase.html.erb`
- Modify (app): `spec/components/previews/ui/button_component_preview.rb`
- Modify (app): `spec/system/ui/button_component_spec.rb` (add a showcase axe assertion)

- [ ] **Step 1: Branches**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui && git switch modelrails/harden -q && git pull --ff-only -q && git switch -c harden/lookbook-tier2-showcase
cd /Users/dschmura/Documents/code/modelrails_base && git switch main -q && git pull --ff-only -q && git switch -c feat/lookbook-tier2-showcase
```

- [ ] **Step 2: Create the button showcase template (gem + app, identical)**

`button_component_preview/showcase.html.erb` (button's proven cells, from its COMBOS):

```erb
<%# locals: () -%>
<div class="flex flex-wrap items-start gap-4">
  <% [%w[solid primary], %w[solid danger], %w[outline neutral], %w[text primary], %w[text danger]].each do |variant, tone| %>
    <div class="flex flex-col items-center gap-1">
      <%= ui :button, "Button", variant: variant.to_sym, tone: tone.to_sym %>
      <span class="text-xs text-text-muted"><%= variant %> / <%= tone %></span>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Add the empty `showcase` method to both button previews**

Add to `button_component_preview.rb` (gem + app), after the `playground` method:

```ruby
    # Every AAA-proven variant × tone cell on one screen.
    def showcase
    end
```

- [ ] **Step 4: Add a showcase axe assertion to the app 0b spec**

In `spec/system/ui/button_component_spec.rb`, add (matching the file's existing visit + axe pattern):

```ruby
  it "showcase renders every proven cell, AAA in both themes" do
    visit "/rails/view_components/ui/button_component/showcase"
    expect(page).to have_css("[data-slot], button, a", minimum: 5)
    expect(axe_clean_in_both_themes?).to be true
  end
```

(Confirm the exact preview-host URL + the file's existing axe helper name by reading 2-3 existing `it` blocks in that spec first; mirror them precisely.)

- [ ] **Step 5: Run the button showcase 0b spec**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" CI=true bundle exec rspec spec/system/ui/button_component_spec.rb -e showcase 2>&1 | tail -8
```

Expected: PASS (AAA, both themes). If it fails AAA, an unproven cell slipped in — fix the cell list. Run the gem suite too (`cd gem && rake`) so the template-backed test sees the new scenario.

- [ ] **Step 6: Commit both repos** (stage explicitly; mirror message).

## Task B2: Fan out the remaining 5 showcases

**Files (per component `<c>` in badge, alert, banner, indicator, chat_bubble):** the same 5 files as Task B1, substituting `<c>`.

- [ ] **Step 1: For each of the 5 components, derive its proven cells from the component's source**

```bash
# read each component's proven variant/tone cells (the source of truth):
for c in badge alert banner indicator chat_bubble; do
  echo "── $c ──"; grep -nE "COMBOS|VARIANTS|TONES|variant|tone" /Users/dschmura/Documents/code/modelrails_base/app/components/ui/${c}_component.rb | head -12
done
```

Use each component's actual proven `(variant, tone)` cells (e.g. badge's 9 from COMBOS; alert is tone-only: neutral/info/success/warning/danger). Do NOT invent cells — enumerate what the component proves, or an unproven combo will raise / fail AAA.

- [ ] **Step 2: Create each `<c>_component_preview/showcase.html.erb`** (gem + app), modeled on the button template but iterating that component's real cells. For tone-only components (alert), iterate tones with `ui :alert, "...", tone: tone.to_sym`. Add the empty `def showcase; end` to each preview `.rb` (gem + app).

- [ ] **Step 3: Add a showcase axe assertion to each component's app 0b spec** (mirror Task B1 Step 4, substituting the component name + its preview-host URL).

- [ ] **Step 4: Run each showcase spec at `CI=true`**, then the FULL app suite + gem `rake`:

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" CI=true bundle exec rspec spec/system/ui/{badge,alert,banner,indicator,chat_bubble}_component_spec.rb 2>&1 | tail -8
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec 2>&1 | grep -E "examples?, [0-9]+ failure"
cd /Users/dschmura/Documents/code/modelrails_ui && PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rake 2>&1 | tail -4
```

Expected: all green (6 showcases proven AAA in both themes; gem tests + RuboCop clean).

- [ ] **Step 5: Commit both repos** (stage explicitly).

## Task B3: PR-B choreography

- [ ] **Step 1: PAUSE for user go-ahead, then push + open PR-B (gem → modelrails/harden, app → main); watch CI to green.**

---

## Self-review (against the spec)

- **2a (Source + lead docs):** Task A4. ✅ (verification + targeted audit; transparent it may be near-empty).
- **2b (theme toolbar control):** Tasks A2 (register + layout) + A3 (remove bespoke controller/button/spec). ✅
- **2c (showcase, 6 components):** Tasks B1 (button exemplar) + B2 (fan-out 5). ✅
- **Gem-first / app-adopt:** every task pairs gem template + app copy. ✅
- **Testing:** A3 Step 4 (full both-theme axe = 2b proof), B1/B2 (per-showcase AAA), gem `rake`. ✅
- **PR shaping (2 PRs):** Phase A = PR-A, Phase B = PR-B. ✅
- **Placeholder scan:** the only deferred specifics are the 5 fan-out showcases' cell lists — concretely sourced from each component's COMBOS/VARIANTS constant (B2 Step 1), not invented. The PR-A/PR-B `--body "..."` are filled at push time. No code placeholders.
- **Consistency:** `params.dig(:lookbook, :display, :theme)`, `def showcase; end`, and `axe_clean_in_both_themes?` are used identically across tasks.
