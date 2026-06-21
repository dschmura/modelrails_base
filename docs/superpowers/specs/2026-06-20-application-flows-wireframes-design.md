# Application Flows wireframes — Design

Date: 2026-06-20
Status: Approved (design); ready for implementation planning
Branch: `docs/application-flows-wireframes`
Goal: A documentation page that visually maps every current user journey as low-fi **UI-screen wireframes**, rendered as theme-adaptive inline SVG in the docs' AAA idiom. The user expects to iterate after seeing it rendered.

## Deliverable

A new indexed doc page **`app/docs/application-flows.md`** ("Application Flows") containing five flows, each rendered as a left-to-right row of UI-screen wireframes (inline SVG), with a one-line prose intro per flow and a cross-link to the detailed feature doc. Categorized under **Architecture** in `config/initializers/markdowndocs.rb`. Cross-linked from `onboarding.md`, `clientside.md`, `workspaces.md`, `projects.md`.

This is a single cohesive visual artifact; the SVG vocabulary is fixed up front so all wireframes share one language.

## Constraints (match the existing doc-SVG idiom)

- Theme-adaptive: `stroke="currentColor"`, `fill="none"` on the root `<svg>`; accent strokes/fills via `class="text-accent"` (the same CSS-token class the existing preset diagrams use). **No raw hex, no web-fonts** — `font-family="ui-sans-serif, system-ui, sans-serif"`.
- Accessible: each flow's `<svg>` is `role="img"` with a thorough `aria-label` that narrates the screens in order (the visual carries meaning; one accessible name per flow). `width="100%"` + a `viewBox`; decorative atoms live under that single role.
- Sanitizer-safe: markdowndocs `allow_svg = true` strips scripts/handlers — author plain shapes/text only (no `<script>`, no `on*` handlers, no external refs).
- Markdown-lint clean; front-matter block like the other pages (`title`, `description`, `keywords`, `audience: [guide, technical]`).
- Rendering is **browser-only** — the plan guarantees well-formed, sanitizer-safe, theme-adaptive SVG, but visual polish is verified at `/docs`, not in CI (same posture as the AAA-in-CI note). Expect a follow-up iteration after the user views it.

## Shared SVG visual vocabulary (fixed primitives)

Each screen is drawn from this fixed atom set so all wireframes look uniform. Coordinates are illustrative; the plan pins exact reusable snippets.

- **Screen frame (desktop):** rounded `<rect>` (~220×150) with a top chrome bar (1.5px rule), three small `<circle>` dots, and a pill URL bar. The screen body is drawn inside. One frame type is used for every screen so the flows read as a consistent row (no mobile frame in v1 — add later only if the user wants device variety).
- **Text bar:** a short filled-ish `<rect>` (low opacity) standing in for a line of text/heading; varied widths.
- **Input field:** a bordered `<rect>` (1px) with a faint placeholder text bar inside.
- **Primary button:** an **accent** filled `<rect>` (`class="text-accent"`, filled) with a centered label — the call to action.
- **Secondary button:** an outline `<rect>` with a label.
- **Tag / role pill:** a small rounded `<rect>` outline with short text (e.g. "Owner", "Client").
- **Placeholder / image:** a dashed `<rect>` with a faint "[ … ]" label.
- **Annotation:** a small low-opacity callout note (rounded rect + short text) for edge cases ("self-hides when >1 tool", "clients don't consume a seat").
- **Connector:** a horizontal arrow (`marker-end` triangle) between screens, with an optional short label above ("Continue", "verify", "accept").
- **Step badge:** a numbered circle above a screen for ordered wizard steps.

A short legend block at the top of the page documents these atoms once (primary = accent fill, dashed = placeholder/conditional, pill = role/tag, note = annotation).

## The five flows (current app — verified during the docs audit)

Each flow = one `<svg>` (a row of screens + connectors), preceded by an H2 + one prose line + a "See: [feature doc]" link.

1. **Sign up & verify** — Landing/CTA → Create account (name · work email · password · "or continue with Google/Apple") → **Check your email** (masked address · Resend · the non-blocking verify banner). See `/docs/emails`, `/docs/accounts`.
2. **First-run onboarding (`none` posture)** — numbered steps: 1 Check email → 2 Name your workspace → 3 Create first project → 4 Pick tools *(annotation: self-hides unless >1 tool registered)* → 5 Invite teammates (or skip) → Project home. See `/docs/onboarding`.
3. **Project home & tools** — Project home (tool **tabs**: Docs …) → Tools settings (checkbox list of tools) → back to home with the tab reflecting the toggle. See `/docs/project-tools`, `/docs/projects`.
4. **Invite teammates (members)** — People list (members + roles) → Add people (emails + **role** select) → Pending → *(invitee side)* Invite email → Invitation ("X invited you", **branch**: existing → one-click; new → set up login) → In the workspace. See `/docs/workspaces`.
5. **Clientside (external client)** — Enable Clientside (project setting toggle) → Invite a client (email + **company**) → Client email → Accept (set up login if new) → **Client area** (read-only; only shared items) *(annotation: a `ClientAccess`, not a member — no seat)*. See `/docs/clientside`.

## Page structure

```text
front-matter
# Application Flows
intro paragraph (what this page is; links to the detailed feature docs)
## Legend  (the atom legend — one small SVG or inline list)
## 1 · Sign up & verify        + svg + "See: …"
## 2 · First-run onboarding     + svg + "See: …"
## 3 · Project home & tools     + svg + "See: …"
## 4 · Invite teammates         + svg + "See: …"
## 5 · Clientside               + svg + "See: …"
```

## Testing / gates

- `spec/docs/index_coverage_spec.rb` — the new page must be categorized (add `application-flows` to the **Architecture** category).
- `rake markdown:check` — lint clean.
- A lightweight **well-formed-SVG check**: a spec (or a rake one-off) that parses each `<svg>` block in `application-flows.md` with Nokogiri and asserts it's valid XML, every root `<svg>` has `role="img"` + a non-empty `aria-label`, and there are no `<script>`/`on*` attributes (sanitizer-safety + a11y contract). This is the automatable part; visual correctness stays a browser check.
- Full suite green.

## Out of scope / iteration

- No new app behavior — documentation only.
- Pixel-perfect fidelity / final visual polish is expected to evolve after the user views `/docs/application-flows` in the browser; this design delivers a complete, accurate, theme-adaptive first version.
- Not embedding per-flow wireframes into each feature page (single overview page + cross-links instead).

## Suggested phasing (for the plan)

- **P1** — Page scaffold + front-matter + intro + legend + the SVG primitive vocabulary established in the first flow (flow 1), categorized in markdowndocs, plus the well-formed-SVG spec. Gives a viewable first screen + the locked visual language.
- **P2** — Flows 2 (onboarding) and 3 (project/tools) using the locked vocabulary.
- **P3** — Flows 4 (invite teammates) and 5 (Clientside).
- **P4** — Cross-links from the feature docs + final gates (index coverage, markdown lint, SVG spec, full suite).
