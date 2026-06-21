# Application Flows Wireframes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one indexed doc page, `app/docs/application-flows.md`, that maps the five current user journeys as low-fi UI-screen wireframes drawn in theme-adaptive inline SVG.

**Architecture:** A single markdown page with front-matter, an atom legend, and five `<svg>` flows (one per journey). All SVG is hand-authored from a fixed primitive vocabulary on a fixed coordinate grid so the wireframes read as one consistent set. A Nokogiri spec enforces the machine-checkable contract (well-formed XML, `role="img"` + non-empty `aria-label`, no scripts); visual polish is verified in the browser at `/docs/application-flows`.

**Tech Stack:** Markdown + inline SVG (markdowndocs `allow_svg`), RSpec + Nokogiri, the existing `rake markdown:check` and `spec/docs/index_coverage_spec.rb` gates.

## Global Constraints

- **Theme-adaptive only.** Root `<svg>`: `fill="none" stroke="currentColor"` and `font-family="ui-sans-serif, system-ui, sans-serif"`. Accent via `class="text-accent"` (sets CSS `color`, picked up by `stroke="currentColor"`/`fill="currentColor"`). **No raw hex, no web-fonts.**
- **Accessibility contract.** Every flow's root `<svg>` has `role="img"` and a non-empty `aria-label` that narrates its screens in order. One accessible name per flow; atoms live under it.
- **Sanitizer-safe.** markdowndocs strips scripts/handlers/external refs — author plain shapes + text only. No `<script>`, no `on*` attributes, no `<image>`/external `href`, no cross-`<svg>` `<use>` (each flow is self-contained).
- **Primary action = bold accent outline** (`class="text-accent"` + `stroke-width="2.25"`), NOT a filled rect — a `currentColor` label on an accent fill is invisible, and there is no theme-safe knock-out color. Secondary action = thin neutral outline (`stroke-width="1.25"`).
- **One screen-frame type** for every screen (no mobile frame in v1).
- **Page format** matches siblings: YAML front-matter (`title`, `description`, `keywords`, `audience: [guide, technical]`), one H1.
- **Markdown lint-clean** (`rake markdown:check`): blank line around every heading/list/fenced block; fenced code blocks specify a language. (SVG blocks are raw HTML, not fenced.)
- **Indexed:** `application-flows` added to the **Architecture** category in `config/initializers/markdowndocs.rb` (else `index_coverage_spec` fails).
- **Content is verified, not invented:** every label/branch reflects the shipped app (onboarding #362/#363, tools #364, Clientside #365–#367). Do not add UI that does not exist.

## Layout grid (shared by all flows)

All coordinates in user units; `width="100%"` scales each flow to its container.

- Margins: `MX = 16` (left/right), `MY = 40` (top, leaves room for a step badge).
- Frame: `FW = 200` wide, `FH = 140` tall. Frame body region is `y0+30 .. y0+FH-6`.
- Horizontal slot pitch: `FW + G` where `G = 64` (the connector lives in the gap). Slot `i` (0-based, within a row) has `x = MX + i*(FW+G)` → columns at **x = 16, 280, 544**; frame right edges at **216, 480, 744**.
- Row pitch: `FH + RV` where `RV = 80` (caption + wrap connector). Row `r` (0-based) top `y = MY + r*(FH+RV)` → rows at **y = 40, 260**.
- A 3-wide row ⇒ `viewBox="0 0 760 230"`. A 2-row (3+n) flow ⇒ `viewBox="0 0 760 480"`.
- **Connector:** horizontal arrow from a frame's right edge to the next frame's left edge at the row mid-line `y = rowTop + 70`; label centered above at `y = rowTop + 60`. Dashed connector (`stroke-dasharray="6 4"`) = "email sent / async hop".
- **Caption:** centered under each frame at `y = rowTop + FH + 18`, `font-size="11"`. Optional faint **annotation** sub-line at `+13` below the caption, `font-size="9.5" opacity="0.55"`.
- **Step badge** (onboarding only): numbered `<circle r="11">` centered above the frame at `y = rowTop - 14`.

## Primitive vocabulary (exact SVG; reuse verbatim with substituted coords/text)

These are the only shapes used. `{x},{y}` are the frame's top-left (a slot origin). Helper offsets are relative to the frame.

```text
FRAME(x,y):                       a screen with browser chrome
  <rect x="{x}" y="{y}" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="{x}" y1="{y+24}" x2="{x+200}" y2="{y+24}" stroke-width="1"/>
  <circle cx="{x+14}" cy="{y+12}" r="3" stroke-width="1"/>
  <circle cx="{x+26}" cy="{y+12}" r="3" stroke-width="1"/>
  <circle cx="{x+38}" cy="{y+12}" r="3" stroke-width="1"/>
  <rect x="{x+54}" y="{y+6}" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>

HEADING(x,y,w):  <rect x="{x}" y="{y}" width="{w}" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
TEXTBAR(x,y,w):  <rect x="{x}" y="{y}" width="{w}" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
FIELD(x,y,w):    <rect x="{x}" y="{y}" width="{w}" height="14" rx="4" stroke-width="1"/>
                 <rect x="{x+6}" y="{y+5}" width="{w*0.4 rounded}" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
BTN_PRIMARY(x,y,w,label):
  <rect class="text-accent" x="{x}" y="{y}" width="{w}" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="{x+w/2}" y="{y+12.5}" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">{label}</text>
BTN_SECONDARY(x,y,w,label):
  <rect x="{x}" y="{y}" width="{w}" height="18" rx="5" stroke-width="1.25" opacity="0.8"/>
  <text x="{x+w/2}" y="{y+12.5}" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">{label}</text>
PILL(x,y,w,label):                role/tag chip
  <rect x="{x}" y="{y}" width="{w}" height="14" rx="7" stroke-width="1" opacity="0.7"/>
  <text x="{x+w/2}" y="{y+10}" text-anchor="middle" font-size="8.5" fill="currentColor" stroke="none" opacity="0.8">{label}</text>
CHECKROW(x,y,w,label,checked):    checklist line
  <rect x="{x}" y="{y}" width="11" height="11" rx="3" stroke-width="1.25" {checked ? 'class="text-accent"' : 'opacity="0.7"'}/>
  <path d="M{x+2.5},{y+5.5} L{x+4.5},{y+8} L{x+8.5},{y+3}" stroke-width="1.5" {checked ? 'class="text-accent"' : 'opacity="0"'}/>
  <rect x="{x+17}" y="{y+3}" width="{w}" height="5" rx="2.5" fill="currentColor" stroke="none" opacity="0.22"/>
TOGGLE(x,y,on):                    settings switch
  <rect x="{x}" y="{y}" width="28" height="14" rx="7" stroke-width="1.25" {on ? 'class="text-accent"' : 'opacity="0.6"'}/>
  <circle cx="{on ? x+21 : x+7}" cy="{y+7}" r="4.5" fill="currentColor" stroke="none" {on ? 'class="text-accent"' : 'opacity="0.6"'}/>
TAB(x,y,w,label,active):          one tab in a tab bar
  <rect x="{x}" y="{y}" width="{w}" height="15" rx="4" {active ? 'class="text-accent" stroke-width="2"' : 'stroke-width="1" opacity="0.55"'}/>
  <text x="{x+w/2}" y="{y+10.5}" text-anchor="middle" font-size="8" {active ? 'class="text-accent" font-weight="700"' : 'opacity="0.6"'} fill="currentColor" stroke="none">{label}</text>
DASHBOX(x,y,w,h,label):           placeholder / mail / image
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" stroke-width="1.25" stroke-dasharray="5 4" opacity="0.6"/>
  <text x="{x+w/2}" y="{y+h/2+3}" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.45">{label}</text>
CONNECTOR(x1,x2,y,label,dashed):  between two frames (uses defs marker "flowarrow")
  <path d="M{x1} {y} H{x2-2}" stroke-width="1.5" {dashed ? 'stroke-dasharray="6 4"' : ''} marker-end="url(#flowarrow)"/>
  <text x="{(x1+x2)/2}" y="{y-6}" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">{label}</text>
WRAPCONNECTOR(xRightOfLastTop, yTopMid, xFirstBottom, yBottomMid, label):  row1→row2 elbow
  <path d="M{xRightOfLastTop} {yTopMid} h28 V{yBottomMid} H{xFirstBottom-2}" stroke-width="1.5" marker-end="url(#flowarrow)"/>
  <text ... label near the vertical run ...>
BADGE(cx,cy,n):                   step number
  <circle cx="{cx}" cy="{cy}" r="11" stroke-width="1.5"/>
  <text x="{cx}" y="{cy+4}" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">{n}</text>
CAPTION(cx,y,text):   <text x="{cx}" y="{y}" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">{text}</text>
ANNOT(cx,y,text):     <text x="{cx}" y="{y}" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.55">{text}</text>
```

Each flow's `<svg>` includes the shared arrow marker in a local `<defs>` (ids are flow-unique to avoid collisions — `flowarrow-1`, `flowarrow-2`, …; the CONNECTOR snippet's `url(#flowarrow)` uses the flow's id):

```text
<defs><marker id="flowarrow-N" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto">
  <path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
```

---

### Task 1: SVG/a11y spec + page scaffold + legend + Flow 1 (worked reference) + index

This task locks the vocabulary, grid, gates, and page shell, and ships the first flow fully authored so the remaining flows are pure composition.

**Files:**
- Create: `spec/docs/application_flows_svg_spec.rb`
- Create: `app/docs/application-flows.md`
- Modify: `config/initializers/markdowndocs.rb` (Architecture category)
- Test: the new spec + `spec/docs/index_coverage_spec.rb` + `rake markdown:check`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: the page file at `app/docs/application-flows.md` with a `## 1 · Sign up & verify` section containing one `<svg role="img" aria-label="…">`; the primitive snippets above realized concretely (later tasks copy this style verbatim); `application-flows` present in the markdowndocs Architecture category.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/docs/application_flows_svg_spec.rb
require "rails_helper"
require "nokogiri"

# The wireframes carry meaning, so each flow <svg> must be well-formed, named
# for assistive tech, and free of anything the markdowndocs sanitizer would
# strip. Visual correctness is checked in the browser; this guards the contract.
RSpec.describe "app/docs/application-flows.md wireframes" do
  let(:source) { File.read(Rails.root.join("app/docs/application-flows.md")) }
  # Each top-level <svg>…</svg> block (flows are not nested).
  let(:svg_blocks) { source.scan(/<svg\b.*?<\/svg>/m) }

  it "has at least the five flow diagrams" do
    expect(svg_blocks.size).to be >= 5
  end

  it "every flow svg is well-formed XML" do
    svg_blocks.each do |svg|
      doc = Nokogiri::XML(svg) { |c| c.strict }
      expect(doc.errors).to be_empty, "malformed SVG: #{doc.errors.first}"
    end
  end

  it "every flow svg is role=img with a non-empty aria-label" do
    svg_blocks.each do |svg|
      root = Nokogiri::XML(svg).root
      expect(root["role"]).to eq("img")
      expect(root["aria-label"].to_s.strip).not_to be_empty
    end
  end

  it "contains no scripts, event handlers, or external refs (sanitizer-safe)" do
    svg_blocks.each do |svg|
      expect(svg).not_to match(/<script/i)
      expect(svg).not_to match(/\son\w+=/i)          # onclick, onload, …
      expect(svg).not_to match(/href\s*=\s*["'](?!#)/i) # only internal #frag refs allowed
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mise exec -- bundle exec rspec spec/docs/application_flows_svg_spec.rb`
Expected: FAIL — `Errno::ENOENT` (the page file does not exist yet).

- [ ] **Step 3: Create the page scaffold + legend + Flow 1**

Create `app/docs/application-flows.md`. Use this exact front-matter, intro, legend, and the fully-authored Flow 1 SVG. (Flow 1 is the canonical style reference for Tasks 2–3.)

````markdown
---
title: Application Flows
description: A visual map of every current user journey — sign up & verify, first-run onboarding, project home & tools, inviting teammates, and Clientside — as low-fi wireframes.
keywords: wireframes flows journeys onboarding signup verify project tools invite teammates members clientside client diagram
audience: [guide, technical]
---

# Application Flows

Low-fi wireframes of the app's five core journeys, as they work today. Each row is a sequence of screens; arrows are transitions. These illustrate flow and information architecture, not final visual design. For the behavior behind each one, follow the "See:" link under its heading.

The wireframes adapt to light and dark themes and are described for screen readers.

## Legend

- **Bold outline** = primary action · **thin outline** = secondary action.
- **Accent** elements (toggles, active tabs, the final screen) mark the emphasized or "after" state.
- **Dashed** box = placeholder/empty content · **dashed arrow** = an email/async hop.
- **Numbered badge** = an ordered wizard step · faint sub-line = an edge case or note.

## 1 · Sign up & verify

A new member creates an account and is asked to confirm their email — a soft, non-blocking gate. See: [Email & verification](/docs/emails), [Accounts](/docs/accounts).

<svg viewBox="0 0 760 230" width="100%" role="img" aria-label="Sign up and verify, three screens left to right. Screen one, a welcome landing page with a primary Create account button and a secondary Sign in button. An arrow labelled Create account leads to screen two, the create-account form with Name, Work email, and Password fields, a primary Create account button, and email or OAuth sign-up. An arrow labelled submit leads to screen three, a Check your email screen with a placeholder envelope, the message that a link was sent, and a secondary Resend button; verification is non-blocking and a reminder banner also appears." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-1" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>

  <!-- Screen 1: Welcome (x=16) -->
  <rect x="16" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="16" y1="64" x2="216" y2="64" stroke-width="1"/>
  <circle cx="30" cy="52" r="3" stroke-width="1"/><circle cx="42" cy="52" r="3" stroke-width="1"/><circle cx="54" cy="52" r="3" stroke-width="1"/>
  <rect x="70" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="36" y="84" width="110" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="36" y="104" width="150" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="36" y="116" width="120" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect class="text-accent" x="36" y="140" width="92" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="82" y="152.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Create account</text>
  <rect x="136" y="140" width="60" height="18" rx="5" stroke-width="1.25" opacity="0.8"/>
  <text x="166" y="152.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Sign in</text>

  <!-- Screen 2: Create account (x=280) -->
  <rect x="280" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="280" y1="64" x2="480" y2="64" stroke-width="1"/>
  <circle cx="294" cy="52" r="3" stroke-width="1"/><circle cx="306" cy="52" r="3" stroke-width="1"/><circle cx="318" cy="52" r="3" stroke-width="1"/>
  <rect x="334" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="300" y="78" width="120" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="300" y="92" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="97" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect x="300" y="110" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="115" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect x="300" y="128" width="160" height="14" rx="4" stroke-width="1"/><rect x="306" y="133" width="64" height="4" rx="2" fill="currentColor" stroke="none" opacity="0.3"/>
  <rect class="text-accent" x="300" y="148" width="160" height="18" rx="5" stroke-width="2.25"/>
  <text class="text-accent" x="380" y="160.5" text-anchor="middle" font-size="9" font-weight="700" fill="currentColor" stroke="none">Create account</text>

  <!-- Screen 3: Check your email (x=544) -->
  <rect x="544" y="40" width="200" height="140" rx="12" stroke-width="1.5"/>
  <line x1="544" y1="64" x2="744" y2="64" stroke-width="1"/>
  <circle cx="558" cy="52" r="3" stroke-width="1"/><circle cx="570" cy="52" r="3" stroke-width="1"/><circle cx="582" cy="52" r="3" stroke-width="1"/>
  <rect x="598" y="46" width="132" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <rect x="564" y="78" width="130" height="8" rx="4" fill="currentColor" stroke="none" opacity="0.4"/>
  <rect x="614" y="92" width="60" height="34" rx="6" stroke-width="1.25" stroke-dasharray="5 4" opacity="0.6"/>
  <text x="644" y="113" text-anchor="middle" font-size="14" fill="currentColor" stroke="none" opacity="0.45">✉</text>
  <rect x="564" y="134" width="160" height="6" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="564" y="150" width="70" height="18" rx="5" stroke-width="1.25" opacity="0.8"/>
  <text x="599" y="162.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Resend</text>

  <!-- Connectors -->
  <path d="M216 110 H278" stroke-width="1.5" marker-end="url(#flowarrow-1)"/>
  <text x="248" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Create account</text>
  <path d="M480 110 H542" stroke-width="1.5" marker-end="url(#flowarrow-1)"/>
  <text x="512" y="104" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">submit</text>

  <!-- Captions -->
  <text x="116" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Welcome</text>
  <text x="380" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Create account (+ OAuth)</text>
  <text x="644" y="198" text-anchor="middle" font-size="11" fill="currentColor" stroke="none">Check your email</text>
  <text x="644" y="211" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.55">non-blocking · reminder banner</text>
</svg>
````

- [ ] **Step 4: Add `application-flows` to the Architecture category**

In `config/initializers/markdowndocs.rb`, change the Architecture line:

```ruby
    "Architecture" => %w[architecture application-flows],
```

- [ ] **Step 5: Run the gates**

Run: `mise exec -- bundle exec rspec spec/docs/application_flows_svg_spec.rb spec/docs/index_coverage_spec.rb`
Expected: the SVG spec's "five flow diagrams" example FAILS (only 1 svg so far) — that's expected until Task 3; the well-formed / role / sanitizer examples PASS on the single svg; `index_coverage_spec` PASSES (page categorized).
Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0 (no violations in the new file).

- [ ] **Step 6: Commit**

```bash
git add spec/docs/application_flows_svg_spec.rb app/docs/application-flows.md config/initializers/markdowndocs.rb
git commit -m "docs(flows): wireframes page scaffold + flow 1 (sign up & verify) + svg spec"
```

---

### Task 2: Flow 2 (onboarding) + Flow 3 (project home & tools)

Append two flow sections, composed from the Task 1 primitives on the grid. Copy Flow 1's element style verbatim (same attributes, opacities, font-sizes); only coordinates and text change.

**Files:**
- Modify: `app/docs/application-flows.md` (append two `##` sections)
- Test: the SVG spec + `rake markdown:check`

**Interfaces:**
- Consumes: the primitive snippets + grid + Flow 1 style from Task 1; marker id pattern `flowarrow-N`.
- Produces: `## 2 · First-run onboarding` and `## 3 · Project home & tools`, each one `<svg role="img" aria-label="…">`.

**Flow 2 — First-run onboarding (`none`)** — `viewBox="0 0 760 480"`, marker id `flowarrow-2`. Two rows of three (badges 1–5 + final). Prose line + `See: [Onboarding](/docs/onboarding).`
Row 0 (y=40): badge1 "Check email" (heading + textbar + `Resend` secondary); badge2 "Name your workspace" (heading + one FIELD + `Continue` primary); badge3 "Create your first project" (heading + one FIELD + `Continue` primary).
Row 1 (y=260): badge4 "Choose tools" (heading + two CHECKROWs — "Docs" checked, a second faint unchecked — + `Continue` primary; ANNOT "self-hides unless >1 tool is registered"); badge5 "Invite teammates" (heading + FIELD "emails" + PILL "Member" + `Send invites` primary + `Skip` secondary); final "Project · Home" (ACCENT frame: draw the frame `<rect>` with `class="text-accent" stroke-width="2"`; a TAB "Docs" active + heading + textbars). No badge on final.
Connectors: row0 1→2→3 (labels "Continue"); WRAPCONNECTOR from badge3 frame (right edge x=744,y=110) down to badge4 frame (left edge x=16,y=330) labelled "first project saved"; row1 4→5 ("Continue"), 5→final ("Finish / Skip"). aria-label narrates all six screens + the self-hide note in order.

**Flow 3 — Project home & tools** — `viewBox="0 0 760 230"`, marker id `flowarrow-3`. One row of three. Prose line + `See: [Project tools](/docs/project-tools), [Projects](/docs/projects).`
S1 "Project home": heading + a tab bar of three TABs ("Docs" active, two faint) at y≈80 + textbars below. caption "Project home".
S2 "Tools settings": heading "Tools" + three CHECKROWs ("Docs" checked, "Messages" unchecked, "Files" unchecked) + `Save` primary. caption "Settings · Tools".
S3 "Home (updated)": heading + tab bar with a second tab now active/accent (the just-enabled tool) + textbars. caption "Home reflects the toggle".
Connectors: S1→S2 "open settings"; S2→S3 "Save". aria-label: "Project home and tools, three screens. Project home with a Docs tab active. Arrow to Tools settings, a checklist of tools with Docs enabled. Arrow labelled Save back to the project home, now showing the newly enabled tool's tab."

- [ ] **Step 1: Write Flow 2 and Flow 3 sections** — append both `##` sections to `app/docs/application-flows.md`, authored from the primitives/grid above, matching Flow 1's style exactly.
- [ ] **Step 2: Run the SVG spec**

Run: `mise exec -- bundle exec rspec spec/docs/application_flows_svg_spec.rb`
Expected: well-formed / role / sanitizer examples PASS for all three svgs; the "five flow diagrams" example still FAILS (3 < 5) — expected until Task 3.

- [ ] **Step 3: Markdown lint**

Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add app/docs/application-flows.md
git commit -m "docs(flows): onboarding + project-home-and-tools wireframes"
```

---

### Task 3: Flow 4 (invite teammates) + Flow 5 (Clientside)

Append the final two flow sections. Same primitives/grid/style. After this task the SVG spec is fully green (≥5 flows).

**Files:**
- Modify: `app/docs/application-flows.md` (append two `##` sections)
- Test: the SVG spec (now all examples pass) + `rake markdown:check`

**Interfaces:**
- Consumes: Task 1 primitives/grid; marker ids `flowarrow-4`, `flowarrow-5`.
- Produces: `## 4 · Invite teammates` and `## 5 · Clientside`, each one `<svg role="img" aria-label="…">`. After this, `app/docs/application-flows.md` has exactly five flow `<svg>`s.

**Flow 4 — Invite teammates** — `viewBox="0 0 760 480"`, marker id `flowarrow-4`. Two rows: row0 = admin (3 screens), row1 = invitee (2 screens, in columns 0 and 1). A faint row label `ANNOT` at the far left of each row ("Admin", "Invitee") or fold into captions. Prose + `See: [Workspaces](/docs/workspaces).`
Row0: S1 "People" (heading "People" + two list lines, each a TEXTBAR name + a PILL role: "Owner", "Member"; `Add people` primary). S2 "Add people" (heading + FIELD "emails" + PILL "Member ▾" role-select + `Send invites` primary). S3 "Pending" (heading "People" + a list line with ANNOT-style faint "invited · pending" + dashed underline).
Row1: S4 "Invite email" (frame; heading "Alex invited you to Acme"; TEXTBARs; `Accept invitation` primary; caption "Invite email"). S5 "Accept" (heading "Join Acme"; show the branch: a FIELD "set up your login" + `Create account` primary; ANNOT "existing user: one-click · new: set up a login"; caption "Accept → in the workspace").
Connectors: row0 S1→S2 "Add people", S2→S3 "Send"; dashed WRAPCONNECTOR S3→S4 "invite email sent"; row1 S4→S5 "Accept". aria-label narrates admin then invitee screens incl. the existing-vs-new branch.

**Flow 5 — Clientside** — `viewBox="0 0 760 480"`, marker id `flowarrow-5`. Two rows: row0 = team (3), row1 = client (2). Prose + `See: [Clientside](/docs/clientside).`
Row0: S1 "Enable Clientside" (heading "Clientside"; a TOGGLE off→on with label TEXTBAR "Enable client access"; `Save` primary; caption "Project setting"). S2 "Share a resource" (heading "Edit resource"; a CHECKROW checked "Share with the client side"; `Save` primary; ANNOT "only when Clientside is on; shares only when published"; caption "Per-resource sharing"). S3 "Invite a client" (heading "Invite a client"; FIELD "Email"; FIELD "Company"; `Send invite` primary; caption "Email + company").
Row1: S4 "Client email" (heading "Acme shared Project with you"; TEXTBARs; `Accept` primary; caption "Client email"). S5 "Client area" (ACCENT frame `class="text-accent" stroke-width="2"`; heading "Acme · Client area"; two CHECKROW-less read-only list lines (TEXTBARs only — no buttons/inputs to signal read-only); ANNOT "read-only · a ClientAccess, not a member — no seat"; caption "Client area").
Connectors: row0 S1→S2 "share", S2→S3 "invite"; dashed WRAPCONNECTOR S3→S4 "invite email sent"; row1 S4→S5 "Accept". aria-label narrates team then client screens incl. the read-only / no-seat note.

- [ ] **Step 1: Write Flow 4 and Flow 5 sections** — append both, authored from primitives/grid, matching Flow 1 style.
- [ ] **Step 2: Run the full SVG spec**

Run: `mise exec -- bundle exec rspec spec/docs/application_flows_svg_spec.rb`
Expected: ALL examples PASS (5 svgs; well-formed; role+aria-label; sanitizer-safe).

- [ ] **Step 3: Markdown lint**

Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add app/docs/application-flows.md
git commit -m "docs(flows): invite-teammates + clientside wireframes"
```

---

### Task 4: Cross-links + final gates

Link the feature docs to the new overview, then run every gate together.

**Files:**
- Modify: `app/docs/onboarding.md`, `app/docs/clientside.md`, `app/docs/workspaces.md`, `app/docs/projects.md` (add one cross-link line each)
- Test: full suite + `markdown:check` + the two docs specs

**Interfaces:**
- Consumes: the finished `application-flows.md` (Tasks 1–3).
- Produces: a one-line link to `/docs/application-flows` in each of the four feature docs.

- [ ] **Step 1: Add a cross-link to each feature doc**

In each of `app/docs/onboarding.md`, `app/docs/clientside.md`, `app/docs/workspaces.md`, `app/docs/projects.md`, add one sentence near the top (after the intro paragraph), e.g.:

```markdown
> See this journey drawn as a wireframe in [Application Flows](/docs/application-flows).
```

Match each page's existing voice; keep blank lines around the blockquote (markdown lint).

- [ ] **Step 2: Run the docs specs + lint**

Run: `mise exec -- bundle exec rspec spec/docs/application_flows_svg_spec.rb spec/docs/index_coverage_spec.rb`
Expected: all PASS.
Run: `mise exec -- bundle exec rake markdown:check`
Expected: exit 0.

- [ ] **Step 3: Run the full suite**

Run: `mise exec -- bundle exec rspec`
Expected: all examples pass (existing count + the new SVG spec; 0 failures).

- [ ] **Step 4: Commit**

```bash
git add app/docs/onboarding.md app/docs/clientside.md app/docs/workspaces.md app/docs/projects.md
git commit -m "docs(flows): cross-link feature docs to Application Flows"
```

---

## Self-Review

**Spec coverage:** ✅ new indexed page (T1+T4); fixed SVG vocabulary + grid (T1 primitives, used T1–T3); five flows (T1 flow 1; T2 flows 2–3; T3 flows 4–5); theme-adaptive/`currentColor`/`text-accent`/no-hex/no-webfont (Global Constraints, every svg); `role="img"`+`aria-label` (T1 spec enforces; every flow authored with it); sanitizer-safe (T1 spec enforces); Architecture category (T1 step 4); cross-links (T4); index_coverage + markdown:check + full suite (T1, T3, T4); well-formed-SVG spec (T1). Browser-only visual polish acknowledged (no task claims pixel-perfect; iteration expected).

**Placeholder scan:** No "TBD/TODO". The primitive block uses `{x},{y}` substitution markers, but those are realized concretely in Flow 1 (T1 step 3) which every later flow copies; flows 2–5 give exact per-screen content (frames, atoms, labels, connectors, captions, annotations, viewBox, marker id). No code step says "add appropriate X".

**Type/name consistency:** marker ids `flowarrow-1..5` unique per flow (no `<use>` across svgs); accent frame = `class="text-accent" stroke-width="2"` (consistent T2 final + T5 client area); primary = bold accent outline, secondary = thin outline (Global Constraint, used uniformly); category key `"Architecture"` matches `config/initializers/markdowndocs.rb`; page slug `application-flows` matches across category, spec file read path, and cross-links.

**Deviation from spec (flagged):** spec said "primary = accent *fill*"; plan uses bold accent *outline* (theme-safe label contrast). Documented in Global Constraints; surface to the user when presenting the result.
