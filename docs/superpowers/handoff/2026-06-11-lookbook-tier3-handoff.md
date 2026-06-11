# Lookbook Tier 3 — handoff for a fresh session

**Date:** 2026-06-11 · **Status:** teed up, not started · **Repos:** `modelrails_base` (app) + `modelrails_ui` (gem)

This is the start-here doc for the next chunk of the Lookbook catalog arc. Memory pointer:
`[[project_lookbook_catalog_improvements]]`.

## Where the arc stands (all SHIPPED & merged)

- **Tier 1** — Overview landing page + 8-section `@logical_path` sidebar grouping (gem #47 / app #270).
- **Tier 2** — theme→Lookbook toolbar display option (gem #48 / app #271); Source-panel canonical `ui` call (verified, no code); all-variants `showcase` scenarios on button/badge/alert/banner (gem #49 / app #272); `@!group` scenario divider + showcase-as-landing on those 4 (app #273).
- **Catalog-wide divider** — `@!group Overview/Examples/Reference` on all 49 meta components; 29 canonical-only stay flat; `device_mockup` ordering fixed; **consistency guard** in both repos (gem `test/test_lookbook_scenario_grouping.rb`, app `spec/components/previews/ui/scenario_grouping_spec.rb`) (gem #50 / app #274).
- **Drift reconciliation** — synced chart/accordion/form_field docs to the gem (app #275); chart **dev-only importmap pin** so the catalog renders the chart (app #276).

## Tier 3 work items (panel-derived; pick one to brainstorm first)

1. **3a — Per-section "reach for X when…" decision pages.** The hardest adoption question is choosing between siblings (dialog vs drawer vs sheet vs popover; input vs combobox vs select). One short markdown Lookbook **Page** per section with a decision table. Mechanism is proven (the Tier 1 Overview page is a Lookbook Page). **Highest adoption value — recommended first.**
2. **3b — Form-control `@param` playgrounds.** Add live `@param` playgrounds to form_field/input/checkbox/radio_group/range so a dev can flip `required`/`invalid`/`hint` and watch the ARIA rewire. **NOT universal** (DHH: a `separator` playground is ceremony). Pattern proven (15 components already have inline `def playground`).
3. **3c — `## Related` / `## Composes` cross-links.** Encode the relationship graph in doc-comments (form_field wraps input/label; gallery reuses the dialog modal; card composes everything). Cheap; rides the doc-comment convention; consider a consistency guard like the grouping one.
4. **3d — Per-preview backgrounds.** Raised components (card/dialog/sheet) render on `bg-surface-raised` — the same token as their own surface — so their elevation/edges are invisible; full-bleed components (navbar/footer/banner) want edge-to-edge. **Open question: does Lookbook 2.3.14 support a per-preview container/background?** Investigate `@display`/preview container options before scoping.
5. **3e — Resolve the stale `feat/lookbook-teaching-catalog` branch** (land or close — it's lingered across sessions) + fill the doc-comment structure on the ~4 components missing it.

**Guardrails (panel anti-recommendations — do NOT):** add more doc *prose*; make every component a playground; hide the `dont_*` anti-patterns; port atoms/molecules/organisms into the nav.

## Separate, bigger piece (not strictly Tier 3)

**`modelrails_ui:update` re-vendor engine** — the root cause of the drift we just patched: the app's vendored previews/components were generated once, then the gem evolved, so gem-side fixes (e.g. the chart pin doc) silently never reached the app. A `:update` generator that diffs the app's vendored copies against the *normalized* current gem output (per-repo RuboCop normalizes byte output — parity is semantic, see `[[project_vendored_parity_is_semantic]]`) would surface drift deliberately. This is the SP4 update-engine already flagged in `[[project_component_system_progress]]`; needs its own brainstorm.

## The proven toolkit (reuse these — don't re-derive)

- **Workflow:** brainstorm → spec (`docs/superpowers/specs/`) → plan (`docs/superpowers/plans/`) → subagent-driven execution. Default per `[[feedback_default_workflow]]`.
- **Lookbook Pages:** markdown `.md.erb` under `spec/components/previews/pages/`, wired via `config.lookbook.page_paths`; `00_` prefix = sort priority; the `embed UI::XxxComponentPreview, :scenario` page helper renders a live proven scenario.
- **Scenario grouping:** YARD `# @!group <Label>` / `# @!endgroup`; `default_scenario = visible_scenarios.first`; consistency-guard pattern (assert order + labels, exempt the flat ones).
- **Playgrounds:** `@param X select [...]` + inline `def playground(...)` rendering via `ui :name`; exempt from the template-backed test; smoke-tested in `spec/system/ui/playground_smoke_spec.rb`.
- **Cross-repo choreography:** gem-first (`modelrails/harden`) → app-adopt (`main`); generator-template changes don't bind the app at runtime (vendored copies) so the PR pairs are independent, but validate the app locally first.
- **CI/merge discipline (hard-won this session):**
  - AAA axe is `CI=true`-only; run `CI=true bundle exec rspec` locally, and the gem CI command is bare `rake` (tests **+** RuboCop), not `rake test`. `[[feedback_ci_vs_local_axe]]`
  - **Before merging, read the actual per-check states** (`gh pr checks <N>` → grep `fail|pending`), NEVER the `--watch` exit code (it exited 0 on a red `test` job). Merge guard: `non-green==0 && state==OPEN`. `[[feedback_proactive_pr_merge]]`
  - The user **proactively merges PRs the moment CI is green** — sequence a PR to be final before pushing; never push a follow-up to a maybe-merged PR (the `cannot lock ref` push error = it merged + branch deleted under you). `[[feedback_proactive_pr_merge]]`
  - The user's untracked `docs/component-standards/` WIP blocks the app push via `markdown_lint` (lints untracked files); **move it aside, push, restore** (or stash it).
  - careful-merge primitive: `gh api -X PUT /repos/<o>/<r>/pulls/<N>/merge -f sha=<FULL-40-char> -f merge_method=squash`.
- **Toolchain:** prefix Ruby with `PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH"`; the gem repo is outside the app working dirs (edit via Bash/heredoc there); never `git add -A` (gem has untracked `docs/design/*` + `MODELRAILS_STATUS.md`; app has `config/credentials/`, `db/development.sqlite3`, `docs/component-standards/`).

## How to start

Invoke the brainstorming skill on **3a** (decision pages) — highest value, proven Pages mechanism — or **3e** first if you want to clear the lingering branch before more drift accumulates. Each item is its own spec → plan → ship cycle.
