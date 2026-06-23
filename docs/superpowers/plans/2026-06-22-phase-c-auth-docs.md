# Phase C — Auth Docs (passwordless + passkeys) + click-to-expand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the auth docs match the shipped passwordless-first + passkeys reality, add the passkey testing guidance, and add `<details>` click-to-expand to the flows page.

**Architecture:** Mostly content edits to `app/docs/*.md`, gated by the existing doc specs (`application_flows_svg_spec`, `index_coverage_spec`, `rake markdown:check`) plus a new docs-accuracy grep guard. The SVG rewrite follows the page's existing inline-SVG idiom. Click-to-expand + the markdowndocs `~> 0.9` re-pin are the only gem-gated steps and come last.

**Tech Stack:** markdowndocs (gem; `~> 0.8` now, `~> 0.9` after release for `<details>`), RSpec, inline SVG, Rails 8.1.

## Global Constraints

- Ruby 4.0.4 / Rails 8.1; commands via `mise exec -- …`.
- **Verify every "stale" claim against the current shipped code before changing it** (user requirement) — fix only what is FALSE; leave accurate incidental mentions.
- **Targeted scope:** rewrite the centerpiece + critical pages + surgical fixes; NOT a comprehensive rewrite of every auth-touching doc, NOT the `audience:`→path-routing migration. (Removing the *deprecated* `audience:` key from docs we already touch IS in scope — it's behavior-neutral, since `[guide, technical]` already = multi-audience.)
- **SVG idiom** (match the existing flows): root `fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif"`, `role="img"` + thorough `aria-label`; screen = `rect rx=11 stroke-width=1.5` with a title bar `line` + 3 dot `circle`s; accent (primary button / checked) via `class="text-accent"`; primary button = accent **outline** (`stroke-width≈2.25`), never a fill (a currentColor label on an accent fill is invisible). **NO blank lines inside an `<svg>`** (a blank line ends the CommonMark HTML block and the next non-tag chunk becomes a `<p>` that breaks HTML5 foreign-content parsing → orphaned elements). Each flow `<svg>` keeps a unique `marker id` (`flowarrow-g1..g5`).
- **`<details>` rule:** put a **blank line after `<summary>`** so the markdown "why" bullets render inside the disclosure.
- All user-facing text already in these docs is English prose (no I18n keys in docs).
- Full RSpec suite green (0 failures) before each commit; never bypass Lefthook; no Co-Authored-By / AI-attribution trailer.

---

## File Structure

**Modify (docs):** `app/docs/emails.md`, `app/docs/application-flows.md`, `app/docs/qa-flows.md`, and (sweep) `app/docs/accounts.md`, `app/docs/accounts-and-identity.md`, `app/docs/getting-started.md`, `app/docs/onboarding.md`, `app/docs/security.md`.
**Modify (gem pin):** `Gemfile`, `Gemfile.lock`.
**Create (guard):** `spec/docs/auth_docs_accuracy_spec.rb`.
**Untouched:** `passkeys.md` already has no `audience:` key and already documents Local-HTTPS/Troubleshooting (forker caveat) — only a cross-link to qa-flows is added (Task 4).

---

### Task 1: Docs-accuracy guard + emails.md password-reset removal

**Files:**
- Create: `spec/docs/auth_docs_accuracy_spec.rb`
- Modify: `app/docs/emails.md`

**Interfaces — Produces:** a grep-style spec asserting no removed-auth references survive in docs; later tasks keep it green.

- [ ] **Step 1: Write the failing guard spec**

`spec/docs/auth_docs_accuracy_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Auth docs accuracy", type: :model do
  DOCS = Rails.root.join("app/docs")

  # References to code DELETED in Phase A — must not appear in any doc.
  it "has no references to the removed password-reset mailer/token" do
    offenders = Dir[DOCS.join("*.md")].select do |f|
      File.read(f).match?(/password_reset_email|password_reset_token|AuthenticationMailer[^\n]*password reset/i)
    end
    expect(offenders).to be_empty, "stale password-reset refs in: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  # The flows page must not depict a password field at signup/invite (passwordless-first).
  it "the flows page does not show a Create/Set password field" do
    flows = File.read(DOCS.join("application-flows.md"))
    expect(flows).not_to match(/Create password|Set a password|>Password<|Password<\/text>/)
  end
end
```

- [ ] **Step 2: Run red**

`mise exec -- bundle exec rspec spec/docs/auth_docs_accuracy_spec.rb`
Expected: FAIL — emails.md has `password_reset_email`/`password_reset_token`; application-flows.md has Password / Create password.

- [ ] **Step 3: Fix emails.md**

In `app/docs/emails.md`:
- Mailers table row: `| `AuthenticationMailer` | Email verification, password reset, email change |` → `| `AuthenticationMailer` | Email verification, email change |`
- Authentication Emails table: **delete** the row `| Password reset | "Forgot password" request | User's email | 2 hours |`.
- **Delete** the entire `### Password Reset` section (the 5 numbered steps referencing `password_reset_token` + `AuthenticationMailer.password_reset_email`).
- Under (or right after) the `### Passwordless Sign-In (Magic Links)` section, add a short recovery note:

```markdown
### Forgot password / account recovery

There is no password-reset email. "Forgot password?" issues a **magic link** (a
`MagicLinkToken` carrying a `set_password` intent); clicking it signs the user in
and lands them on the change-password form. Magic link is the single
email-recovery primitive — see [Passkeys](/docs/passkeys) for the passwordless
sign-in options and [Application Flows](/docs/application-flows) for the journey.
```

- Front-matter `keywords:` — drop "password reset". Remove the deprecated `audience: [guide, technical]` line.

- [ ] **Step 4: Green + markdown:check**

`mise exec -- bundle exec rspec spec/docs/auth_docs_accuracy_spec.rb` → the password_reset_email example PASSES (flows example still fails until Task 2 — that's expected; note it).
`mise exec -- bundle exec rake markdown:check` → clean.

- [ ] **Step 5: Commit**

```bash
git add spec/docs/auth_docs_accuracy_spec.rb app/docs/emails.md
git commit -m "docs(emails): replace password-reset with magic-link recovery + accuracy guard"
```

---

### Task 2: application-flows.md — rewrite the auth flow + fix the invite login screen

**Files:**
- Modify: `app/docs/application-flows.md`
- Test: `spec/docs/application_flows_svg_spec.rb` (existing) + `spec/docs/auth_docs_accuracy_spec.rb` (Task 1)

**Interfaces — Consumes:** the accuracy guard (Task 1) — this task makes its second example pass.

- [ ] **Step 1: Run the guard (red on the flows example)**

`mise exec -- bundle exec rspec spec/docs/auth_docs_accuracy_spec.rb -e "Create/Set password"` → FAIL (flow 1 has a Password field; flow 4 has "Create password").

- [ ] **Step 2: Rewrite flow 1 — "Sign up & sign in"**

Replace the flow-1 SVG (lines ~26–48) and its heading. The new flow depicts the **full passwordless + passkey story** as three screens (use a wider 2-row layout like the onboarding flow's `viewBox="0 0 600 410"`, or a 790-wide single row — author to the idiom; keep it blank-line-free; keep `marker id="flowarrow-g1"`):

- **Screen A — "Sign in or sign up"**: one **Email address** field (value `jane@acme.com`) + a primary **Continue** button (accent outline); below it a **"Sign in with a passkey"** button (a second outline/secondary button); a small caption "or use a magic link". (No password field.)
- **Screen B — "Check your email"**: "We sent a sign-in link to jane@acme.com — click it to continue." + a `Resend link` secondary button.
- **Screen C — "Set up a passkey?"** (the one-time post-sign-in interstitial): copy "Add a passkey for faster sign-in" + an **Add a passkey** button + a **Not now** text button.
- Connectors: A →(continue)→ B; B →(after link)→ signed-in/interstitial C.
- `aria-label`: describe all three screens accurately (no "Password").

Heading: `## 1 · Sign up & sign in` (was "Sign up & verify").

Replace the flow-1 "Why" prose (lines 50–53) with:

```markdown
- **Sign in or sign up** — One email-first door (`sessions#new` → `lookup`) for both. A new email gets a magic-link registration; an existing one gets a magic-link sign-in. There is **no password at signup** — password is a settings-only opt-in. A returning user with a passkey can tap **Sign in with a passkey** (usernameless/discoverable); any failure falls back to the magic link, so no one is stranded.
- **Check your email** — The magic link proves email ownership: clicking it verifies the address **and** signs the user in in one step. "Forgot password?" reuses this same link (a `set_password`-intent magic link) — there is no separate reset flow.
- **Set up a passkey?** — A one-time, dismissible prompt after the first sign-in (only when the user has no passkey yet and the browser supports WebAuthn). Adding one makes the next sign-in a single tap; magic link remains the universal fallback. Manage passkeys anytime in Settings.
```

- [ ] **Step 3: Fix flow 4 — invite "Set up your login" (remove the password)**

In flow 4's SVG (lines ~166–171), the third screen "Set up your login" shows **First name** + **Create password** + "Join Acme Co". Edit it to passwordless: keep **First name** (and add **Last name** if it fits), **remove** the "Create password" label + its input `rect`/`text` (lines ~169–170), and keep the **Join Acme Co** button (reposition as needed). Update the flow-4 `aria-label` (line 142) to drop "and Create password" → e.g. "…Set up your login, with First name and Last name and a Join button." Keep it blank-line-free.

Update the flow-4 "Why" bullet (line 180):

```markdown
- **Accept / set up login** — Consume-before-verify with an `EmailMismatch` guard: a leaked link can't be claimed by a different address. Existing users join in one click; a new email finishes a **passwordless** signup (name only — magic link already proved the email). One `User`, reused everywhere after.
```

- [ ] **Step 4: Drop the deprecated `audience:` key** from the front-matter (line 5).

- [ ] **Step 5: Verify (render-true, not just source)**

```bash
mise exec -- bundle exec rspec spec/docs/application_flows_svg_spec.rb   # ≥5 svgs, well-formed, role=img+aria-label, rendered-nesting (no breakout)
mise exec -- bundle exec rspec spec/docs/auth_docs_accuracy_spec.rb       # both examples now PASS
mise exec -- bundle exec rake markdown:check
```
Then visually verify the rewritten flow 1 + flow 4 render correctly in **both light and dark** themes (implementation-verifier / browser) — the SVG spec proves structure, not visual correctness. AAA is proven in CI.

- [ ] **Step 6: Commit**

```bash
git add app/docs/application-flows.md
git commit -m "docs(flows): rewrite signup/sign-in to passwordless + passkeys; drop invite password"
```

---

### Task 3: qa-flows.md — passkey QA + contributor test harness; sweep its stale claims

**Files:**
- Modify: `app/docs/qa-flows.md`
- Test: `spec/docs/auth_docs_accuracy_spec.rb`, `rake markdown:check`, `index_coverage_spec`

- [ ] **Step 1: Verify-then-fix Flow 1 / Flow 2 against code**

Read `qa-flows.md` Flow 1 (Signup/invitations, §1a–1c) and Flow 2 (Magic-link, incl. "Existing user (has password)"). Verify each step against the current `SessionsController#lookup`/`create`, magic-link callbacks, and `Settings::PasswordsController`. Fix only FALSE claims (e.g. any "create a password at signup", any reference to the removed `RegistrationsController`/public `PasswordsController`/password-reset). "Existing user (has password)" stays valid (password is an opt-in; the secondary "use your password instead" path exists) — just confirm the wording matches the shipped secondary-link flow.

- [ ] **Step 2: Add a passkey section**

Add `## Flow 8 — Passkeys` with two parts:

```markdown
## Flow 8 — Passkeys (WebAuthn)

### Manual QA (requires a secure context)

Passkeys need HTTPS — over plain `http://localhost` the "Sign in with a passkey"
button feature-detects off and the page falls back to magic link. To exercise the
real ceremony locally, run with TLS and set the origin:

1. `WEBAUTHN_ORIGIN=https://localhost:3000 bin/rails s --ssl` (or a tunnel).
2. Sign in (magic link) → Settings → Passkeys → **Add a passkey** → approve the
   platform prompt → the credential appears in the list.
3. Sign out → on the sign-in screen tap **Sign in with a passkey** → approve →
   signed in.
4. Remove the passkey in Settings → confirm sign-in still works via magic link.

See [Passkeys](/docs/passkeys) for RP-ID/origin configuration and troubleshooting.

### Writing passkey tests (contributors)

WebAuthn can't be driven by a normal Capybara click, so tests use one of two
real-crypto harnesses (no mocking the gem):

- **Request specs** use the gem's `WebAuthn::FakeClient` (real attestation /
  assertion crypto). See `spec/lib/passkeys/*_spec.rb` and
  `spec/requests/passkeys/*_spec.rb`.
- **System specs** use a Playwright **CDP virtual authenticator**, set up by
  `spec/support/webauthn_virtual_authenticator.rb` (`page.context.new_cdp_session`
  → `WebAuthn.enable` + `WebAuthn.addVirtualAuthenticator`). The example lives in
  `spec/system/passkey_auth_spec.rb`. Note: the virtual authenticator requires
  `Capybara.app_host` to match the configured RP origin.
```

- [ ] **Step 3: Drop the deprecated `audience:` key** (line 5).

- [ ] **Step 4: Verify + commit**

```bash
mise exec -- bundle exec rspec spec/docs/auth_docs_accuracy_spec.rb spec/docs/index_coverage_spec.rb
mise exec -- bundle exec rake markdown:check
git add app/docs/qa-flows.md
git commit -m "docs(qa-flows): passkey manual QA + contributor test-harness how-to; passwordless fixes"
```

Also add a one-line cross-link in `passkeys.md` (under "Local HTTPS testing" or "Managing passkeys"): "**Writing passkey tests?** See the contributor harness notes in [QA flows](/docs/qa-flows)." Commit with the same message or a follow-up `docs(passkeys): link contributor test harness`.

---

### Task 4: Surgical sweep — accounts / getting-started / onboarding / security

**Files:**
- Modify (only where FALSE): `app/docs/accounts.md`, `app/docs/accounts-and-identity.md`, `app/docs/getting-started.md`, `app/docs/onboarding.md`, `app/docs/security.md`
- Test: `spec/docs/auth_docs_accuracy_spec.rb`, `rake markdown:check`

- [ ] **Step 1: Enumerate candidates**

```bash
grep -rniE "create.*password|set a password|password.*(required|to (sign|complete))|forgot password|password reset|RegistrationsController|new_registration|PasswordsController" app/docs/accounts.md app/docs/accounts-and-identity.md app/docs/getting-started.md app/docs/onboarding.md app/docs/security.md
```

- [ ] **Step 2: Verify-then-fix each hit against the code**

For each hit, read it in context AND check the shipped behavior (`sessions_controller.rb`, `registrations` is GONE, `settings/passwords_controller.rb` for opt-in, magic-link callbacks). Fix only FALSE statements:
- "set/create a password to complete signup" → "you're signed in once your email is verified via the magic link; a password is an optional setting".
- "forgot password → reset email" → "forgot password → magic link".
- references to `RegistrationsController` / `new_registration_path` / public `PasswordsController` → remove/repoint (those are deleted).
- `security.md` password-policy prose → keep ONLY as the *opt-in* password's rules; recommend passkeys/magic-link as the default. Do NOT add the secure-context caveat narrative here (it lives in passkeys.md) beyond a one-line pointer if natural.
Leave accurate incidental mentions (e.g. "password" describing the settings opt-in) untouched. Do NOT rewrite whole pages.

- [ ] **Step 3: Verify + commit**

```bash
mise exec -- bundle exec rspec spec/docs/auth_docs_accuracy_spec.rb spec/docs/index_coverage_spec.rb
mise exec -- bundle exec rake markdown:check
git add app/docs/accounts.md app/docs/accounts-and-identity.md app/docs/getting-started.md app/docs/onboarding.md app/docs/security.md
git commit -m "docs: correct stale password-model claims across auth docs (verified vs code)"
```

---

### Task 5: markdowndocs `~> 0.9` re-pin + `<details>` click-to-expand (GEM-GATED)

> **Gate:** Do this task only once **markdowndocs 0.9.0 is released on RubyGems** (the `<details>` allowlist). If it isn't yet, STOP and report — Tasks 1–4 stand on their own; this is the clean fast-follow.

**Files:**
- Modify: `Gemfile`, `Gemfile.lock`, `app/docs/application-flows.md`
- Test: `spec/docs/application_flows_svg_spec.rb`, a render check, `rake markdown:check`

- [ ] **Step 1: Confirm 0.9.0 is installable**

`mise exec -- gem list -r markdowndocs --all | grep 0.9` (or `bundle outdated markdowndocs`). If absent, STOP (report: "0.9.0 not on RubyGems yet").

- [ ] **Step 2: Re-pin + bundle**

In `Gemfile`: `gem "markdowndocs", "~> 0.9"`. Run `mise exec -- bundle update markdowndocs --conservative`. Confirm `Gemfile.lock` now shows `markdowndocs (0.9.x)`.

- [ ] **Step 3: Wrap each flow's "Why" in `<details>`**

For each of the 5 flows in `application-flows.md`, replace the `**Why it's shaped this way**` block with a disclosure (blank line after `<summary>` so the bullets render):

```markdown
<details>
<summary>Why it's shaped this way</summary>

- **…** — …
- **…** — …
</details>
```

(Keep the bullet content identical to the current/Task-2 prose.)

- [ ] **Step 4: Verify (render-true)**

```bash
mise exec -- bundle exec rspec spec/docs/application_flows_svg_spec.rb   # SVGs still nest/well-formed
mise exec -- bundle exec rake markdown:check
```
Then render `/docs/application-flows` in a browser (dev server with the new gem): confirm each "Why" is a **collapsible** `<details>` and that the markdown bullets render **inside** it (the blank-line-after-summary rule) — in both themes. (markdowndocs renders `<details>` only because `config.allow_svg = true` is already set + 0.9.0 allowlists it.)

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock app/docs/application-flows.md
git commit -m "docs(flows): collapsible Why sections via markdowndocs 0.9 <details>"
```

---

### Task 6: Full-suite gate + finish

- [ ] **Step 1:** `mise exec -- bundle exec rspec` → **0 failures** (incl. the new accuracy guard, the svg spec, index_coverage). Investigate any pending.
- [ ] **Step 2:** Final grep guard — `grep -rniE "password_reset_email|password_reset_token|Create password|new_registration_path" app/docs` → zero.
- [ ] **Step 3:** Hand off via `superpowers:finishing-a-development-branch` (push + PR; CI proves AAA on the flows page + markdown lint).

---

## Self-Review

**Spec coverage:** emails password-reset→magic-link + audience drop → T1; flows auth rewrite (full passwordless+passkey story) + invite password removal + audience drop → T2; passkeys testing split (manual caveat already in passkeys.md; contributor harness → qa-flows) + qa-flows passwordless fixes → T3; surgical sweep (verify-vs-code) → T4; gem re-pin + `<details>` click-to-expand → T5 (gem-gated); full-suite/grep gate + finish → T6. ✓ Out-of-scope items (comprehensive rewrite, path-routing migration, global `.btn-primary` AAA gap) are excluded per spec.

**Placeholder scan:** prose + table/section edits are given verbatim; the flow-1 SVG is specified screen-by-screen with the idiom + gated by `application_flows_svg_spec` + render-verify (generative SVG authored to spec, the established pattern for this page — not a placeholder); the flow-4 SVG edit is a precise targeted removal; the sweep is verify-then-fix with the exact grep + decision rule. No "TBD".

**Consistency:** the accuracy guard (T1) is referenced by T2/T3/T4 and the final gate (T6); `application_flows_svg_spec` gates T2 + T5; the gem gate is isolated to T5 so T1–T4 land without it; heading rename "Sign up & verify"→"Sign up & sign in" used consistently; `<details>` blank-line-after-`<summary>` rule stated in Global Constraints + T5.

**Note for the implementer:** the brainstorm explorer over-generalized some specifics — trust the grep + the shipped code over any remembered claim; `passkeys.md` already lacks `audience:` and already has Local-HTTPS/Troubleshooting, so its only change is the qa-flows cross-link (T3).
