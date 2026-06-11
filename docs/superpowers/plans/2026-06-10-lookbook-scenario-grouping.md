# Lookbook catalog-wide scenario grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the proven `@!group` scenario divider (Overview · Examples · Reference) to the 45 components that have meta scenarios but aren't grouped yet, with a consistency guard that keeps it canonical.

**Architecture:** A throwaway classify-and-group script does the bulk edit (per repo); a durable consistency-guard test (gem Minitest + app RSpec) asserts the canonical order and fails CI on drift. Gem-first (generator templates), then app-adopt — same as Tier 1's `@logical_path` bulk. The script's parsing is de-risked by the guard + gem `rake` + the app 0b suite (which renders every scenario) + diff review.

**Tech Stack:** Ruby 4.0.4, Lookbook 2.3.14, Minitest (gem), RSpec (app).

**Spec:** `docs/superpowers/specs/2026-06-10-lookbook-scenario-grouping-design.md`

**Canonical structure (per preview with meta scenarios):**
- `# @!group Overview` → `showcase` (only the 4 already done)
- `# @!group Examples` → all canonical scenarios (current order)
- `# @!group Reference` → `playground` (if any), then `dont_*` (if any)
- Canonical-only previews (29) are left flat (no groups).

**Toolchain:** prefix Ruby with `PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH"`. The gem repo is OUTSIDE the app working dirs (edit via Bash/ruby there). Never `git add -A`.

---

## Task 1: Gem branch

- [ ] **Step 1: Branch off modelrails/harden**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
git fetch origin -q && git switch modelrails/harden -q && git pull --ff-only -q
git switch -c harden/lookbook-scenario-grouping
git branch --show-current   # => harden/lookbook-scenario-grouping
```

(The app is already on `feat/lookbook-scenario-grouping`, which carries the spec + this plan.)

## Task 2: Gem consistency guard test (the durable artifact)

**Files:** Create `test/test_lookbook_scenario_grouping.rb` (gem).

- [ ] **Step 1: Write the guard test**

Create `/Users/dschmura/Documents/code/modelrails_ui/test/test_lookbook_scenario_grouping.rb` (via `cat > ... <<'RUBY'`):

```ruby
# frozen_string_literal: true

require "test_helper"

# Every preview that has META scenarios (showcase / playground / dont_*) must group its
# scenarios into Overview/Examples/Reference in the canonical order. Canonical-only previews
# (no meta) are exempt and stay flat. Guards against scenario-order drift going forward.
class TestLookbookScenarioGrouping < Minitest::Test
  PREVIEW_ROOT = File.expand_path(
    "../lib/generators/modelrails_ui/lookbook/templates/previews/ui", __dir__
  )

  RANK = { overview: 0, examples: 1, reference_pg: 2, reference_dont: 3 }.freeze

  def classify(name)
    return :overview if name == "showcase"
    return :reference_pg if name == "playground"
    return :reference_dont if name.start_with?("dont_")
    :examples
  end

  def scenario_methods(src)
    src.scan(/^\s+def ([a-z_][a-z0-9_]*)/).flatten - %w[input_attrs]
  end

  def group_labels(src)
    src.scan(/^\s*#\s*@!group\s+(\w+)/).flatten
  end

  def previews
    Dir.glob(File.join(PREVIEW_ROOT, "*_component_preview.rb"))
  end

  def test_grouped_previews_are_in_canonical_order
    previews.each do |path|
      component = File.basename(path, "_component_preview.rb")
      src = File.read(path)
      methods = scenario_methods(src)
      has_meta = methods.any? { |m| m == "showcase" || m == "playground" || m.start_with?("dont_") }
      next unless has_meta # canonical-only previews stay flat — exempt

      ranks = methods.map { |m| RANK.fetch(classify(m)) }
      assert_equal ranks.sort, ranks,
        "#{component}: scenarios out of canonical order (showcase→examples→playground→dont): #{methods.inspect}"

      expected = []
      expected << "Overview" if methods.include?("showcase")
      expected << "Examples"
      expected << "Reference"
      assert_equal expected, group_labels(src),
        "#{component}: @!group labels #{group_labels(src).inspect} != expected #{expected.inspect}"
    end
  end

  def test_canonical_only_previews_stay_flat
    previews.each do |path|
      component = File.basename(path, "_component_preview.rb")
      src = File.read(path)
      methods = scenario_methods(src)
      has_meta = methods.any? { |m| m == "showcase" || m == "playground" || m.start_with?("dont_") }
      next if has_meta

      assert_empty group_labels(src),
        "#{component}: canonical-only preview should stay flat (no @!group), got #{group_labels(src).inspect}"
    end
  end
end
```

- [ ] **Step 2: Run it — verify it FAILS**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby -Itest test/test_lookbook_scenario_grouping.rb
```

Expected: FAIL — `test_grouped_previews_are_in_canonical_order` fails on the first ungrouped meta preview (e.g. `accordion`: has `dont_*` but no `@!group`, so `group_labels` is `[]` != `["Examples","Reference"]`). (The 4 already-grouped components pass.)

## Task 3: Gem — classify-and-group script + apply + verify

**Files:** Create (gem, one-off) `bin/group_scenarios.rb`; Modify the 45 ungrouped meta previews.

- [ ] **Step 1: Write the script**

Create `/Users/dschmura/Documents/code/modelrails_ui/bin/group_scenarios.rb` (via `cat > ... <<'RUBY'`):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# One-off: group each preview's scenarios into @!group Overview/Examples/Reference.
# Overview=showcase, Examples=canonical, Reference=playground then dont_*. Canonical-only
# previews (no meta) are left untouched. Idempotent: skips files that already contain @!group.
root = ARGV[0] or abort "usage: group_scenarios.rb <preview_root>"

Dir.glob(File.join(root, "*_component_preview.rb")).sort.each do |path|
  src = File.read(path)
  next if src.include?("@!group") # already grouped (the 4 showcase components)
  lines = src.lines
  inc = lines.index { |l| l =~ /^\s*include UIHelper/ } or next
  class_end = lines.rindex { |l| l =~ /^  end\s*$/ } or next
  body = lines[(inc + 1)...class_end]

  blocks = []
  pending = []
  i = 0
  while i < body.length
    if body[i] =~ /^\s+def ([a-z_][a-z0-9_]*)/
      name = Regexp.last_match(1)
      if body[i] =~ /;\s*end\s*$/ # one-line `def x; end`
        j = i
      else
        j = i
        j += 1 until j >= body.length || body[j] =~ /^    end\s*$/
      end
      lead = pending.drop_while { |l| l.strip.empty? } # keep comments, drop blank run
      blocks << { name: name, lines: lead + body[i..j] }
      pending = []
      i = j + 1
    else
      pending << body[i]
      i += 1
    end
  end

  meta = blocks.any? { |b| b[:name] == "showcase" || b[:name] == "playground" || b[:name].start_with?("dont_") }
  next unless meta # canonical-only: leave flat

  overview   = blocks.select { |b| b[:name] == "showcase" }
  playground = blocks.select { |b| b[:name] == "playground" }
  donts      = blocks.select { |b| b[:name].start_with?("dont_") }
  examples   = blocks - overview - playground - donts

  out = lines[0..inc] # through `include UIHelper`
  emit = lambda do |label, blks|
    return if blks.empty?
    out << "\n"
    out << "    # @!group #{label}\n"
    blks.each do |b|
      out << "\n"
      out.concat(b[:lines].map { |l| l.sub(/\s+\z/, "") + "\n" }.reject { |l| l == "\n" && out.last == "\n" })
    end
    out << "\n    # @!endgroup\n"
  end
  emit.call("Overview", overview)
  emit.call("Examples", examples)
  emit.call("Reference", playground + donts)
  out << "\n"
  out.concat(lines[class_end..-1]) # `  end` + `end`
  File.write(path, out.join)
  puts "grouped #{File.basename(path, "_component_preview.rb")}"
end
```

- [ ] **Step 2: Run the script on the gem previews**

```bash
cd /Users/dschmura/Documents/code/modelrails_ui
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby bin/group_scenarios.rb lib/generators/modelrails_ui/lookbook/templates/previews/ui
```

Expected: prints `grouped <component>` for ~45 components (skips the 4 already-grouped + the 29 canonical-only).

- [ ] **Step 3: Normalize spacing with RuboCop autocorrect (the script's blank-line output is approximate)**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rubocop -A lib/generators/modelrails_ui/lookbook/templates/previews/ui/ 2>&1 | tail -4
```

Expected: offenses corrected (layout/blank-line). Re-run `rubocop` (no `-A`) on that dir → 0 offenses.

- [ ] **Step 4: Run the consistency guard — verify it PASSES**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby -Itest test/test_lookbook_scenario_grouping.rb
```

Expected: PASS (2 runs, 0 failures) — all meta previews grouped + ordered; canonical-only stay flat.

- [ ] **Step 5: Review the diff — verify doc-comments + bodies preserved (NOT just the count)**

```bash
git diff --stat | tail -6   # ~45 files
# spot-check one of each shape: a dont-only, a playground-only, a playground+dont:
git diff lib/generators/modelrails_ui/lookbook/templates/previews/ui/accordion_component_preview.rb   # dont-only
git diff lib/generators/modelrails_ui/lookbook/templates/previews/ui/sheet_component_preview.rb        # playground-only
git diff lib/generators/modelrails_ui/lookbook/templates/previews/ui/avatar_component_preview.rb       # playground+dont
git diff lib/generators/modelrails_ui/lookbook/templates/previews/ui/device_mockup_component_preview.rb # playground+dont (was dont-before-playground)
```

Confirm in each: every original doc-comment + method body is intact (only `@!group` lines added + methods reordered into groups), and `device_mockup` now has `playground` before `dont_`. If any file looks mangled, fix it by hand and re-run Steps 4.

- [ ] **Step 6: Run the full gem suite (template-backed test must stay green)**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rake 2>&1 | tail -6
```

Expected: 0 failures, 0 errors, 0 offenses.

- [ ] **Step 7: Remove the one-off script and commit**

```bash
rm -f bin/group_scenarios.rb
git add test/test_lookbook_scenario_grouping.rb lib/generators/modelrails_ui/lookbook/templates/previews/ui/
git status   # confirm ONLY the test + the ~45 previews staged; NO stray files
git commit -m "feat(lookbook): group scenarios (Overview/Examples/Reference) catalog-wide

Applies the proven @!group divider to the 45 components with meta scenarios;
adds a consistency guard (canonical-only previews stay flat). device_mockup
ordering fixed (playground before dont)."
```

## Task 4: App — mirror (guard spec + apply + full suite)

**Files:** Create `spec/components/previews/ui/scenario_grouping_spec.rb` (app); Modify the 45 app previews.

- [ ] **Step 1: Write the failing app guard spec**

Create `/Users/dschmura/Documents/code/modelrails_base/spec/components/previews/ui/scenario_grouping_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Mirror of the gem guard: every app preview with meta scenarios (showcase/playground/dont_*)
# must group into Overview/Examples/Reference in canonical order; canonical-only stay flat.
RSpec.describe "Lookbook scenario grouping" do
  preview_root = Rails.root.join("spec/components/previews/ui")
  rank = { overview: 0, examples: 1, reference_pg: 2, reference_dont: 3 }

  classify = lambda do |name|
    next :overview if name == "showcase"
    next :reference_pg if name == "playground"
    next :reference_dont if name.start_with?("dont_")
    :examples
  end

  Dir.glob(preview_root.join("*_component_preview.rb")).sort.each do |path|
    component = File.basename(path, "_component_preview.rb")
    src = File.read(path)
    methods = src.scan(/^\s+def ([a-z_][a-z0-9_]*)/).flatten - %w[input_attrs]
    labels = src.scan(/^\s*#\s*@!group\s+(\w+)/).flatten
    has_meta = methods.any? { |m| m == "showcase" || m == "playground" || m.start_with?("dont_") }

    if has_meta
      it "#{component} groups scenarios in canonical order" do
        ranks = methods.map { |m| rank.fetch(classify.call(m)) }
        expect(ranks).to eq(ranks.sort), "out of order: #{methods.inspect}"
        expected = []
        expected << "Overview" if methods.include?("showcase")
        expected << "Examples"
        expected << "Reference"
        expect(labels).to eq(expected)
      end
    else
      it "#{component} (canonical-only) stays flat" do
        expect(labels).to be_empty
      end
    end
  end
end
```

- [ ] **Step 2: Run it — verify it FAILS**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec spec/components/previews/ui/scenario_grouping_spec.rb 2>&1 | grep -E "examples?, [0-9]+ failure"
```

Expected: FAIL — ~45 "groups scenarios in canonical order" examples fail (app previews not yet grouped).

- [ ] **Step 3: Run the SAME script on the app previews**

Re-create `bin/group_scenarios.rb` in the app (identical to Task 3 Step 1 — the engineer may be reading out of order, so the full script is repeated here):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# One-off: group each preview's scenarios into @!group Overview/Examples/Reference.
# Overview=showcase, Examples=canonical, Reference=playground then dont_*. Canonical-only
# previews (no meta) are left untouched. Idempotent: skips files that already contain @!group.
root = ARGV[0] or abort "usage: group_scenarios.rb <preview_root>"

Dir.glob(File.join(root, "*_component_preview.rb")).sort.each do |path|
  src = File.read(path)
  next if src.include?("@!group")
  lines = src.lines
  inc = lines.index { |l| l =~ /^\s*include UIHelper/ } or next
  class_end = lines.rindex { |l| l =~ /^  end\s*$/ } or next
  body = lines[(inc + 1)...class_end]

  blocks = []
  pending = []
  i = 0
  while i < body.length
    if body[i] =~ /^\s+def ([a-z_][a-z0-9_]*)/
      name = Regexp.last_match(1)
      if body[i] =~ /;\s*end\s*$/
        j = i
      else
        j = i
        j += 1 until j >= body.length || body[j] =~ /^    end\s*$/
      end
      lead = pending.drop_while { |l| l.strip.empty? }
      blocks << { name: name, lines: lead + body[i..j] }
      pending = []
      i = j + 1
    else
      pending << body[i]
      i += 1
    end
  end

  meta = blocks.any? { |b| b[:name] == "showcase" || b[:name] == "playground" || b[:name].start_with?("dont_") }
  next unless meta

  overview   = blocks.select { |b| b[:name] == "showcase" }
  playground = blocks.select { |b| b[:name] == "playground" }
  donts      = blocks.select { |b| b[:name].start_with?("dont_") }
  examples   = blocks - overview - playground - donts

  out = lines[0..inc]
  emit = lambda do |label, blks|
    return if blks.empty?
    out << "\n"
    out << "    # @!group #{label}\n"
    blks.each do |b|
      out << "\n"
      out.concat(b[:lines].map { |l| l.sub(/\s+\z/, "") + "\n" }.reject { |l| l == "\n" && out.last == "\n" })
    end
    out << "\n    # @!endgroup\n"
  end
  emit.call("Overview", overview)
  emit.call("Examples", examples)
  emit.call("Reference", playground + donts)
  out << "\n"
  out.concat(lines[class_end..-1])
  File.write(path, out.join)
  puts "grouped #{File.basename(path, "_component_preview.rb")}"
end
```

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" ruby bin/group_scenarios.rb spec/components/previews/ui
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rubocop -A spec/components/previews/ui/ 2>&1 | tail -3
```

- [ ] **Step 4: Run the app guard spec — verify it PASSES**

```bash
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec spec/components/previews/ui/scenario_grouping_spec.rb 2>&1 | grep -E "examples?, [0-9]+ failure"
```

Expected: PASS (≈78 examples — 45 grouped + 29 flat + 4 already-grouped, 0 failures).

- [ ] **Step 5: Diff review + FULL app suite (renders every scenario — the real corruption gate)**

```bash
git diff --stat | tail -6
git diff spec/components/previews/ui/accordion_component_preview.rb spec/components/previews/ui/device_mockup_component_preview.rb | head -60
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bundle exec rspec 2>&1 | grep -E "examples?, [0-9]+ failure"
```

Expected: full suite 0 failures (the 0b specs visit + render every scenario; a corrupted preview would fail to render). If a single flake hits, re-run once.

- [ ] **Step 6: Remove the one-off script and commit**

```bash
rm -f bin/group_scenarios.rb
git add spec/components/previews/ui/
git status   # ONLY the spec + ~45 previews; NO stray files (never config/credentials, db, docs/component-standards)
git commit -m "feat(lookbook): group scenarios (Overview/Examples/Reference) catalog-wide"
```

## Task 5: Live verification

**Files:** none.

- [ ] **Step 1: Boot a dev server (own pidfile; don't touch :3000) and confirm the nav**

```bash
cd /Users/dschmura/Documents/code/modelrails_base
PATH="$HOME/.local/share/mise/installs/ruby/4.0.4/bin:$PATH" bin/rails server -p 3004 -P /tmp/lb_grp.pid -e development &
curl -s -o /dev/null --retry 25 --retry-delay 2 --retry-all-errors --max-time 5 http://localhost:3004/lookbook
# a grouped (dont-only) component shows Examples + Reference:
html=$(curl -s --max-time 10 "http://localhost:3004/lookbook/inspect/Data%20Display/accordion")
for g in Examples Reference; do printf "  accordion nav '%s': %s\n" "$g" "$(printf '%s' "$html" | grep -qF "$g" && echo present || echo MISSING)"; done
# device_mockup: playground now before dont (Reference order):
curl -s "http://localhost:3004/lookbook/inspect/Media/device_mockup" -o /dev/null -w "device_mockup reachable: %{http_code}\n" --max-time 8
kill "$(cat /tmp/lb_grp.pid)" 2>/dev/null; rm -f /tmp/lb_grp.pid
```

Expected: accordion shows Examples + Reference nav sections. (A canonical-only component like `kbd` would show no group headers — flat.)

## Task 6: PR choreography

- [ ] **Step 1: PAUSE for user go-ahead.** Then push + open PRs (gem → modelrails/harden, app → main).

```bash
cd /Users/dschmura/Documents/code/modelrails_ui && git push -u origin harden/lookbook-scenario-grouping
gh pr create --base modelrails/harden --title "feat(lookbook): catalog-wide scenario grouping (Overview/Examples/Reference)" --body "..."
cd /Users/dschmura/Documents/code/modelrails_base && git push -u origin feat/lookbook-scenario-grouping  # move docs/component-standards aside first if markdown_lint blocks
gh pr create --base main --title "feat(lookbook): catalog-wide scenario grouping (Overview/Examples/Reference)" --body "..."
```

- [ ] **Step 2: Watch CI; READ the actual per-check states (not the watch exit) before merging** (`gh pr checks <N>` → grep `fail|pending`; merge only when 0 non-green + state OPEN). Rerun transient infra (docker_build registry timeouts) with `gh run rerun <id> --failed`; never bypass.

---

## Self-review (against the spec)

- **Apply divider to the 45 meta components:** Task 3 (gem) + Task 4 (app). ✅
- **Canonical structure (Overview/Examples/Reference, playground→dont):** the script + the guard encode it. ✅
- **Canonical-only 29 stay flat:** the script skips them (no meta) + the guard's `test_canonical_only_previews_stay_flat`. ✅
- **device_mockup ordering subsumed:** Reference = playground then dont; verified in Task 3 Step 5 + Task 5. ✅
- **Consistency guard (durable):** gem `test_lookbook_scenario_grouping.rb` + app `scenario_grouping_spec.rb`. ✅
- **Doc-comment preservation:** diff review (Task 3 Step 5, Task 4 Step 5) + gem `rake` + app full suite (renders scenarios). ✅
- **PR shape + proactive-merge discipline:** Task 6 (final-before-green; read actual checks). ✅
- **Placeholder scan:** the only deferred specifics are the PR `--body "..."` (filled at push). The script is repeated in full in Task 4 (not "similar to Task 3"). No code placeholders.
- **Consistency:** `classify`, `RANK`/`rank`, group labels, and the `@!group` regex are identical across the gem test, app spec, and script.
