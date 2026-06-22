# Phase C — Auth Docs (passwordless + passkeys) + click-to-expand — Design

**Date:** 2026-06-22
**Status:** Approved direction (brainstorm complete); ready for plan after user review.
**Arc:** Phase **C** (final) of the passwordless arc. A (passwordless-first) shipped #374; B (passkeys/WebAuthn) shipped #375. This phase makes the docs match the shipped behavior, adds passkey testing guidance, and introduces collapsible sections via markdowndocs 0.9.0.

## Goal

The docs still describe the pre-Phase-A password model (Email+Password signup, password-reset email). Bring the auth docs in line with the shipped passwordless-first + passkeys reality, document the passkey testing story (the user's explicit request), and add `<details>` click-to-expand to the flows page. **Scope: Targeted** (decided in brainstorming) — rewrite the centerpiece + critical pages, surgically fix outright-false claims elsewhere; NOT a comprehensive rewrite of every auth-touching doc, and NOT the `audience:`→path-routing migration.

## Decisions (locked in brainstorming)

- **Flows page depth:** depict the **full passwordless + passkey story** (email-first → magic-link → signed in; returning passkey button + magic-link fallback; one-time enrollment interstitial; fixed invite "set up your login").
- **Passkey testing docs — split by audience** (refined during review): the **manual secure-context/HTTPS caveat** (forker/operator-facing) stays in `passkeys.md`; the **contributor harness how-to** (virtual-authenticator + `FakeClient`) goes in the existing **`qa-flows.md`** (the testing-doc home, already in the sweep). NOT a new `technical/` subdir (that's the deferred path-routing migration).
- **Click-to-expand:** apply `<details>` on the **flows page** (each flow's "why"), not elsewhere.
- **Gem:** user releases markdowndocs **0.9.0**; app re-pins `~> 0.9` — gates the `<details>` rendering.

## Verified-stale inventory (grounded, with citations)

- `app/docs/application-flows.md` — signup screen shows "Create your account · Email address · **Password** · [Create account]" (lines 26–37); the invite flow ends in "Set up your login · First name · **Create password**" (line 142); the "why" prose (line 52) describes the old password+magic-link mix. **Wrong.**
- `app/docs/emails.md` — `AuthenticationMailer | … password reset …` (line 16); "Password reset … 2 hours" table row (line 27); a "Password Reset" section with `password_reset_token` + `AuthenticationMailer.password_reset_email` (lines 69–73). **References deleted code.**
- `app/docs/passkeys.md` — exists (config/local-HTTPS/troubleshooting); **missing** the testing section. (Also still carries the deprecated `audience:` key — drop it.)
- Other auth-touching docs (`accounts.md`, `accounts-and-identity.md`, `getting-started.md`, `onboarding.md`, `security.md`, `qa-flows.md`) — mention password/signup; **some genuinely stale, many incidental** — verify each during implementation, fix only the false claims.

## Components / changes

### 1. `application-flows.md` — centerpiece rewrite

Replace the **auth flow** SVG + prose. New depiction (inline SVG, matching the page's existing idiom — `role="img"` + thorough `aria-label`, `fill="none" stroke="currentColor"`, accent via `class="text-accent"`, **no internal blank lines**):

- **Sign up / sign in (single email-first door):** screen 1 "Enter your email" (one field + OAuth + a "Sign in with a passkey" button) → screen 2 "Check your email" (magic-link sent) → signed in. Note the secondary "use your password instead" only for opt-in users.
- **Returning login:** the passkey button (usernameless) as the fast path; magic-link as fallback.
- **Enrollment interstitial:** the one-time "Set up a passkey?" prompt after first sign-in.
- **Invite flow fix:** the "Set up your login" screen drops "Create password" — invited users finish via magic-link (passwordless).
- **"Why" prose + model primer:** rewrite to passwordless-first (magic-link default; password = settings opt-in, not a signup step; passkey = fast returning login; forgot-password → magic-link recovery). Remove password-as-signup framing.
- Onboarding / project-tools / clientside flows: unchanged.

**Click-to-expand:** wrap each flow's "Why it's shaped this way" block in `<details><summary>Why it's shaped this way</summary>` … `</details>`, with a **blank line after `<summary>`** so the markdown bullets render inside the disclosure. Default collapsed (skim screens, expand rationale).

### 2. `emails.md`

Remove the "Password Reset" section (lines ~69–73) and the password-reset table row / `AuthenticationMailer` "password reset" mention. Replace with the magic-link recovery story: "Forgot password?" issues a `set_password`-intent magic-link (no separate reset-token system). Keep verification, invitation, email-change, and notification mailers. Update the `keywords` front-matter (drop "password reset").

### 3. `passkeys.md` — add the manual testing caveat + drop deprecated `audience:`

- **Manual testing caveat (forker-facing):** WebAuthn needs a secure context — local HTTPS (`bin/rails s --ssl` or a tunnel) + `WEBAUTHN_ORIGIN`; over plain http the button feature-detects off and the flow falls back to magic-link.
- Remove the `audience:` front-matter key (deprecated in 0.9.0; root docs are multi-audience by default).
- (The contributor harness how-to lives in `qa-flows.md`, §4 — not here; passkeys.md stays forker/operator-facing.)

### 4. Surgical sweep (verify-then-fix, not rewrites) — code-accurate at completion

Grep `accounts.md`, `accounts-and-identity.md`, `getting-started.md`, `onboarding.md`, `security.md`, `qa-flows.md` for password/signup/registration/reset claims. For each, **read it in context AND verify against the current shipped code** before changing — fix only what is now FALSE (e.g. "set a password to complete signup" → "you're signed in; a passkey/password is optional in settings"; "forgot-password reset flow" → magic-link recovery; references to the removed `RegistrationsController`/public `PasswordsController`). Leave accurate incidental mentions (e.g. "password" in a settings-opt-in context) alone. This is a first-class task, not a footnote: when Phase C closes, these docs must correctly reflect the codebase (no half-stale claims left for "later").

**Plus — `qa-flows.md` also gains the passkey contributor-testing how-to** (from §3): how to write/run passkey tests — the Playwright CDP **virtual-authenticator** harness (`spec/support/webauthn_virtual_authenticator.rb`: `page.context.new_cdp_session` + `WebAuthn.enable`/`addVirtualAuthenticator`; `Capybara.app_host` aligned to the RP origin) and request-level **`WebAuthn::FakeClient`** (real crypto). Point to the existing passkey specs as examples. `qa-flows.md` is the testing-doc home, so this is its natural place (vs. the forker-facing `passkeys.md`).

### 5. Gem re-pin

After markdowndocs 0.9.0 is on RubyGems: `gem "markdowndocs", "~> 0.9"` in `Gemfile`, `bundle`, commit `Gemfile`+`Gemfile.lock`. This is the gate for `<details>` to render (the 0.9.0 sanitizer allowlist). The plan sequences the click-to-expand step after this.

## Testing / verification

- `spec/docs/application_flows_svg_spec.rb` (existing) gates the rewritten SVGs: ≥5 svgs, well-formed (Nokogiri strict), `role=img` + non-empty `aria-label`, no `<script>`/`on*`/external href, AND **rendered-through-markdowndocs nesting** (every drawing element nests in its `<svg>`; zero orphans = no blank-line breakout). Author SVG blank-line-free.
- `spec/docs/index_coverage_spec.rb` + `rake markdown:check` stay green.
- **Click-to-expand render check (needs 0.9.0):** a check that `<details>`/`<summary>` survive the markdowndocs pipeline and the "why" markdown renders inside (browser/render, not just source) — the disclosure actually collapses. (Until 0.9.0 is pinned, this can't pass; sequence accordingly.)
- Full suite green; AAA both themes (CI) for the flows page (it's already AAA-audited).
- No `password_reset`/`AuthenticationMailer.password_reset_email` references remain in docs (grep guard).

## Out of scope / deferred

- Comprehensive rewrite of incidental auth mentions across all docs.
- `audience:`→path-based-routing migration (0.9.0 feature) across the docs tree.
- The global `.btn-primary`/`text-interactive` AAA-under-workspace-branding gap (a separate, pre-existing follow-up; see the passwordless-arc memory).
- New passkey-related emails (enrollment confirmation, etc.) — not built; don't document.

## Risks / notes for the plan

- **0.9.0 must be released before the click-to-expand step** — the plan should make the gem re-pin + the `<details>` application one task, gated on the release; the doc-content tasks (flows screens/prose, emails, passkeys testing, sweep) do NOT depend on the gem and can land first.
- The SVG rewrite is the largest piece — author blank-line-free; lean on the existing svg spec; verify rendering in a browser (both themes) per the design-system rules.
- Verify every "stale" claim against the actual shipped code before changing it (the brainstorm explorer over-generalized some specifics; trust the grep + the code, not assumptions).
