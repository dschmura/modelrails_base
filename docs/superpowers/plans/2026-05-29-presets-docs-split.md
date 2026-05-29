# Split presets.md into hub + per-preset pages — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the 270-line `app/docs/presets.md` into a slim hub (overview + chooser + shared concepts) plus three self-contained per-preset pages, so a developer can read serially to compare or jump straight to the preset they're standing up.

**Architecture:** Hub-and-spoke. `presets.md` keeps its `/docs/presets` slug and becomes the chooser + shared vocabulary; three new pages (`presets-solo.md`, `presets-single-tenant.md`, `presets-open-saas.md`) each hold one preset's full setup/behavior. A new "Presets" markdowndocs category groups them on the index and powers the related-docs sidebar. Content is **moved, not rewritten**.

**Tech Stack:** Markdown served by the markdowndocs engine; `config/initializers/markdowndocs.rb` (categories); `spec/docs/index_coverage_spec.rb` (orphan guard); `rake markdown:check` (markdownlint).

**Commit strategy:** This is an *atomic* documentation move — partial states leave broken links (hub → not-yet-created spokes) or duplicated content (section in both hub and spoke). So Tasks 1–6 build one consistent state and the single commit happens in Task 7 after full verification. Steps remain bite-sized for reviewability.

**Reference:** spec at `docs/superpowers/specs/2026-05-29-presets-docs-split-design.md`. Source line ranges below are from `presets.md` at plan-authoring time (270 lines); extract by **heading boundaries**, not raw line numbers, since they shift after the first edit.

---

## Task 1: Create `presets-solo.md`

**Files:**
- Create: `app/docs/presets-solo.md`
- Source: `app/docs/presets.md` — the `## Solo-default` section (currently lines 34–85, i.e. from `## Solo-default` up to but **not** including the `---` divider before `## Single-tenant`)

- [ ] **Step 1: Create the file with front-matter + breadcrumb, then the extracted body, then the footer**

Front-matter + breadcrumb (verbatim top of file):

```markdown
---
title: Solo-default
description: Stand up and verify the Solo-default preset — every user gets a personal workspace; signup open or invite-only
keywords: solo-default preset personal workspace prosumer multi-workspace signup onboarding switcher
audience: [guide, technical]
---

[App Presets](/docs/presets) › Solo-default

# Solo-default
```

Then paste the **body** of the current `## Solo-default` section — everything *after* the `## Solo-default` heading line and *before* the `---` divider that precedes `## Single-tenant`. (The `## Solo-default` heading itself is replaced by the `# Solo-default` H1 above; demote any inner `##`/`###` only if the source used `##` for sub-parts — it uses bold `**…**` sub-labels, so no demotion needed.)

Then append the footer (verbatim):

```markdown
## Next steps

- ‹ **[Compare all presets](/docs/presets)** — the decision matrix and the other two shapes.
- **[Extending ModelRails →](/docs/extending)** — add your own workspace-scoped features on top of this preset.
```

- [ ] **Step 2: Fix internal links in the new file**

In the pasted body, the "When to switch presets" bullets point to the other presets. Change any `(#single-tenant)` / `(#open-saas)` anchors (or `**Single-tenant**` / `**Open SaaS**` plain bold) to absolute links: `[Single-tenant](/docs/presets-single-tenant)` and `[Open SaaS](/docs/presets-open-saas)`. Ensure **no** link uses a `.md` suffix.

- [ ] **Step 3: Verify markdown lints clean**

Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0 (no new violations).

---

## Task 2: Create `presets-single-tenant.md`

**Files:**
- Create: `app/docs/presets-single-tenant.md`
- Source: `app/docs/presets.md` — the `## Single-tenant` section (currently lines 88–164), **excluding** the cross-cutting paragraph `**Switching presets on a live app is a migration…**` (line 165), which moves to the hub in Task 4.

- [ ] **Step 1: Create the file with front-matter + breadcrumb + body + footer**

Front-matter + breadcrumb:

```markdown
---
title: Single-tenant
description: Stand up and verify the Single-tenant preset — one shared workspace, no personal workspaces, tenancy UI suppressed
keywords: single-tenant preset shared workspace internal tool owner bootstrap seed owner_setup_link invite-only
audience: [guide, technical]
---

[App Presets](/docs/presets) › Single-tenant

# Single-tenant
```

Then paste the **body** of the `## Single-tenant` section — after the `## Single-tenant` heading and before the `**Switching presets on a live app is a migration…**` paragraph. Do **not** include that migration paragraph or the `---` divider.

Then append the same footer block as Task 1 Step 1 (the "## Next steps" with "Compare all presets" + "Extending ModelRails").

- [ ] **Step 2: Fix internal links**

Change the "When to switch presets" links to `[Solo-default](/docs/presets-solo)` and `[Open SaaS](/docs/presets-open-saas)`. No `.md` suffixes.

- [ ] **Step 3: Verify**

Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0.

---

## Task 3: Create `presets-open-saas.md`

**Files:**
- Create: `app/docs/presets-open-saas.md`
- Source: `app/docs/presets.md` — the `## Open SaaS` section (currently lines 169–267, everything from `## Open SaaS` up to the `## Next steps` heading).

- [ ] **Step 1: Create the file with front-matter + breadcrumb + body + footer**

Front-matter + breadcrumb:

```markdown
---
title: Open SaaS
description: Stand up and verify the Open SaaS preset — per-customer org workspaces, shareable join links, two signup postures
keywords: open-saas preset multi-tenant signup posture open_link join link flow a flow b allowlist tightening
audience: [guide, technical]
---

[App Presets](/docs/presets) › Open SaaS

# Open SaaS
```

Then paste the **body** of the `## Open SaaS` section — after the `## Open SaaS` heading and before the `## Next steps` heading. The inner `### Signup posture — pick one` subheading is preserved as-is.

Then append the same footer block as Task 1.

- [ ] **Step 2: Fix internal links**

Change the "When to switch presets" links to `[Solo-default](/docs/presets-solo)` and `[Single-tenant](/docs/presets-single-tenant)`. Keep existing `/docs/...` and `/workspaces/...` links. No `.md` suffixes.

- [ ] **Step 3: Verify**

Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0.

---

## Task 4: Rewrite `presets.md` as the hub

**Files:**
- Modify: `app/docs/presets.md` — replace everything from `## Solo-default` (line 34) through the end of file with the hub tail below; keep the front-matter (lines 1–6), intro (8–20), decision matrix, and `## Quick decision` (22–30).

- [ ] **Step 1: Update the decision-matrix links to point at spokes**

In the matrix table (the `| Preset | Use this for… | …` block, lines ~14–18), change each preset-name cell link from the in-page anchor to the spoke slug:
- `**[Solo-default](#solo-default)**` → `**[Solo-default](/docs/presets-solo)**`
- `**[Single-tenant](#single-tenant)**` → `**[Single-tenant](/docs/presets-single-tenant)**`
- `**[Open SaaS](#open-saas)**` → `**[Open SaaS](/docs/presets-open-saas)**`

- [ ] **Step 2: Update the "Quick decision" bullets to link to spokes**

In `## Quick decision` (lines ~22–30), make each preset name a link:
- "→ **[Solo-default](/docs/presets-solo)**."
- "→ **[Single-tenant](/docs/presets-single-tenant)**."
- "→ **[Open SaaS](/docs/presets-open-saas)**."

- [ ] **Step 3: Delete the three preset sections and replace the tail**

Delete from the `---` divider before `## Solo-default` through the end of the file (everything: Solo-default, Single-tenant, Open SaaS, and the old `## Next steps`). Replace with this exact hub tail:

```markdown
---

## Switching presets later

**Switching presets on a live app is a migration, not a config edit.** Flipping `TENANCY_ONBOARDING` later doesn't migrate existing data — for example, `:personal`→`:shared` leaves every user's personal workspace intact and adds them to the shared one. Pick a preset at setup time; mid-life changes require a deliberate migration plan. (Open SaaS has its own mid-life nuance — tightening the join-strategy allowlist — documented on its page.)

## Next steps

Pick the shape you're building and follow its page end-to-end:

- **[Solo-default →](/docs/presets-solo)** — prosumer / multi-workspace tools; the shipped default.
- **[Single-tenant →](/docs/presets-single-tenant)** — one shared workspace for an internal tool or one-org deployment.
- **[Open SaaS →](/docs/presets-open-saas)** — per-customer org workspaces with shareable join links.

Then **[Extending ModelRails →](/docs/extending)** to build your own features on top.
```

- [ ] **Step 4: Verify the hub lints clean and has no stray anchors**

Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0.
Run: `grep -nE "\]\(#(solo-default|single-tenant|open-saas)\)" app/docs/presets.md`
Expected: no output (all anchor links replaced with spoke slugs).

---

## Task 5: Register the new "Presets" category

**Files:**
- Modify: `config/initializers/markdowndocs.rb` — the `config.categories` hash.

- [ ] **Step 1: Move `presets` out of "Getting Started" and add the "Presets" category**

Change the `"Getting Started"` entry to drop `presets`, and add a new `"Presets"` category. Result:

```ruby
    "Getting Started" => %w[getting-started],
    "Presets" => %w[presets presets-solo presets-single-tenant presets-open-saas],
    "Architecture" => %w[architecture],
```

(Insert the `"Presets"` line immediately after `"Getting Started"` so it reads as the second group on the index, matching the onboarding journey order.)

- [ ] **Step 2: Run the orphan-guard spec**

Run: `mise exec -- bundle exec rspec spec/docs/index_coverage_spec.rb`
Expected: 2 examples, 0 failures (every `app/docs/*.md` is categorized; no stale slugs).

---

## Task 6: Confirm the journey cross-links still resolve

**Files:**
- Read-only check of `app/docs/getting-started.md` (the `getting-started` → `/docs/presets` link must remain).

- [ ] **Step 1: Confirm getting-started still bridges to the hub**

Run: `grep -n "/docs/presets" app/docs/getting-started.md`
Expected: at least one match (the "choose your app shape" / "Next steps" link to `/docs/presets`). No change needed — the hub kept the `presets` slug.

- [ ] **Step 2: Confirm no relative `.md` links anywhere in docs**

Run: `grep -rnE "\]\([a-z0-9-]+\.md[)#]" app/docs/*.md`
Expected: no output.

---

## Task 7: Full verification, commit, push, PR

- [ ] **Step 1: Boot the app and verify every preset route renders (200), the old anchor URLs are gone, and no link 406s**

Start the server if not running (`bin/dev`), then:

```bash
for slug in presets presets-solo presets-single-tenant presets-open-saas; do
  curl -s -o /dev/null -w "/docs/$slug -> %{http_code}\n" "http://localhost:3000/docs/$slug"
done
```

Expected: all four → `200`. (Restart the server or clear the markdowndocs cache with `bin/rails tmp:cache:clear` if a page 404s — new files may need a fresh read.)

- [ ] **Step 2: Run the docs specs**

Run: `mise exec -- bundle exec rspec spec/docs/index_coverage_spec.rb`
Expected: 2 examples, 0 failures.

- [ ] **Step 3: Run the full suite**

Run: `mise exec -- bundle exec rspec`
Expected: 0 failures (docs-only change; the surface-drift flake may need one rerun — it is unrelated).

- [ ] **Step 4: Commit**

```bash
git add app/docs/presets.md app/docs/presets-solo.md app/docs/presets-single-tenant.md app/docs/presets-open-saas.md config/initializers/markdowndocs.rb
git commit -m "docs(presets): split into hub + per-preset pages

presets.md becomes the chooser + shared concepts (what-is-a-preset, the
decision matrix as a jump table, 'switching is a migration'); three new
self-contained pages (presets-solo / presets-single-tenant / presets-open-saas)
hold each preset's full setup + behavior. New 'Presets' markdowndocs category
groups them and powers related-docs cross-linking. Content moved, not rewritten.

The hub keeps the /docs/presets slug, so getting-started's link is unchanged."
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin docs/split-presets-into-pages
```

Then open a PR (base `main`) summarizing the hub-and-spoke split, the new category, and that content was moved not rewritten. Note the spec/plan under `docs/superpowers/`.

---

## Self-review notes (author)

- **Spec coverage:** hub content (Task 4), three spokes (Tasks 1–3), hybrid boundary (spokes self-contained; admit/Tenanted left as links — preserved from source), navigation (breadcrumb + footer in each spoke; matrix-as-jump-table in hub), category (Task 5), journey re-wiring (Tasks 4 & 6), migration-not-rewrite (extract instructions), testing (Task 7). All covered.
- **Switching-is-a-migration** relocated from the Single-tenant tail to the hub `## Switching presets later` (Task 2 excludes it; Task 4 adds it). No duplication.
- **No `.md` links** enforced in Tasks 1–3 (link fixes), Task 6 Step 2, and verified by curl in Task 7.
