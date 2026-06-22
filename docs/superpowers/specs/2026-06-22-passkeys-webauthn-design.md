# Passkeys (WebAuthn) — Design (Phase B)

**Date:** 2026-06-22
**Status:** Approved direction (brainstorm + 6-reviewer panel complete); ready for plan after user review.
**Arc:** Phase **B** of the passwordless arc. Phase A (passwordless-first posture) shipped (PR #374). Phase C = docs + markdowndocs `<details>` click-to-expand.

## Goal

Let returning users sign in with a **passkey** (WebAuthn) as the fast primary path, with magic-link remaining the universal bootstrap + recovery. A passkey is *conceptually* another auth method but *physically* a capability — register once, authenticate many — so it gets its own model rather than a row on `Authentication`.

## Decisions (brainstorm) + hardening (panel)

Locked in brainstorming:

- **Login surface:** an explicit usernameless **"Sign in with a passkey"** button on `sessions/new` (the robust, testable core), **plus** conditional-UI **autofill** layered on the email field (same backend ceremony, graceful degradation).
- **WebAuthn user handle:** a **random opaque** `users.webauthn_handle`, not the integer PK (FIDO guidance; avoids enumeration).
- **Enrollment nudge:** a **one-time, post-first-sign-in dismissible interstitial** ("Set up a passkey for faster sign-in"), plus always-available settings management.
- **Recovery:** magic-link (existing) — so **no last-credential guard** (a user can delete every passkey and still sign in via a link).

Folded in from the panel (DHH · Aaron Patterson · Dave Thomas · Joël Quenneville · Léonie Watson · Chris Oliver; synthesized via Sandi Metz + Jim Weirich):

- **Challenge lives in a DB model with atomic one-time consume** (not the signed session) — the `MagicLinkToken` pattern; closes a replay/concurrency hole. *(Aaron, Dave)*
- **`sign_count` advanced atomically with clone detection.** *(Aaron, Dave)*
- **DB-level uniqueness** on `credential_id` and `webauthn_handle`; race-safe lazy handle generation. *(Aaron)*
- **RP ID / origin config seam** + env override — the forker footgun. *(Chris)*
- **Named failure outcomes + graceful magic-link fallback + browser/secure-context feature detection.** *(Dave, Chris, Léonie, Joël)*
- **A11y contract** (button, `aria-live` announcements, `UI::DialogComponent` interstitial, settings `aria-label` + confirm dialog). *(Léonie)*
- **Thin ceremony POROs**, **soft-delete credentials**, **beefed-up tests**, **`app/docs/passkeys.md`**.

## Library

`gem "webauthn", "~> 3.0"` (cedarcode/webauthn-ruby) — the standard Ruby WebAuthn implementation; handles CBOR/COSE/signature verification/attestation. No DIY crypto. Ruby 4.0.4 is compatible.

## Data model

### `WebauthnCredential` (new)

A registered passkey. `belongs_to :user`. Columns:

| Column | Notes |
|---|---|
| `user_id` | FK, not null |
| `external_id` | the WebAuthn credential id (base64url string). **Unique index.** |
| `public_key` | COSE public key (string/base64) |
| `sign_count` | integer, default 0 — advanced on each assertion; regression ⇒ clone |
| `nickname` | user-facing label ("Jane's iPhone") |
| `last_used_at` | refreshed on each successful assertion |
| `verified_at` | set once at registration; **immutable** (a passkey is registered, not re-verified) |
| `discarded_at` | soft delete (the app's `Discardable` concern) — avoids in-flight-auth races |
| timestamps | |

`User has_many :webauthn_credentials, dependent: :destroy`; include `Discardable`. Model exposes intent-revealing methods (see Ceremonies). Top-of-file comment explains *why this is not an `Authentication`* (capability, many-per-user, register-once).

### `WebauthnChallenge` (new) — the replay-safe nonce

Mirrors `MagicLinkToken`'s atomic single-use design rather than the signed session.

| Column | Notes |
|---|---|
| `challenge` | random bytes (base64url). **Unique index.** |
| `user_id` | nullable (null for usernameless authentication + registration-before-user-handle is known; set when scoped) |
| `purpose` | `"registration"` \| `"authentication"` |
| `expires_at` | short TTL (e.g. 5 minutes) |
| `consumed_at` | atomic single-use |
| timestamps | |

`self.issue(purpose:, user: nil)` creates one; `self.consume!(challenge)` does an atomic `UPDATE … WHERE consumed_at IS NULL AND expires_at > ?` and returns the row only if exactly one row was affected (the `MagicLinkToken.consume!` exemplar). Partial unique index keeps issuance race-safe.

### `users.webauthn_handle` (new column)

Random opaque base64url, **unique index**, generated **lazily** on first enrollment inside a transaction with `rescue ActiveRecord::RecordNotUnique` (the `MagicLinkToken.create_for_email` race-safe idiom). This is the stable WebAuthn `user.id` — decoupled from the integer PK and email.

### `users.passkey_prompt_seen_at` (new column)

Nullable timestamp; set when the user **dismisses or completes** the enrollment interstitial, so it shows at most once.

## Configuration — RP ID / origin (the forker footgun)

`config/initializers/webauthn.rb` configures the `webauthn` gem's relying party:

```ruby
WebAuthn.configure do |config|
  # RP ID must equal the registrable domain the app is served from.
  # Derived from the app host, overridable per environment via env var.
  config.origin = ENV.fetch("WEBAUTHN_ORIGIN") { default_origin_for(Rails.env) }
  config.rp_name = ENV.fetch("WEBAUTHN_RP_NAME", "<App name from I18n>")
  # rp_id defaults to the origin's host; set WEBAUTHN_RP_ID only for apex/subdomain cases.
end
```

- **prod:** derived from the deploy host (Kamal `RAILS_HOST`/`WEBAUTHN_ORIGIN`).
- **dev:** WebAuthn needs a secure context — document `https://localhost`/`127.0.0.1` (`bin/rails s --ssl` or a tunnel) with `WEBAUTHN_ORIGIN` set; the UI feature-detects `window.isSecureContext` and hides passkeys (falling back to magic-link) when unavailable.
- **test:** a fixed origin the `WebAuthn::FakeClient` uses.

A request spec asserts the configured origin matches the app host config, so a misconfig fails loudly.

## Ceremonies (thin POROs; controllers dispatch; models hold state)

Orchestration lives in two small POROs (clears the project's "service object = 3+ operations + cross-cutting concern" bar: each issues/consumes a challenge, calls the gem, mutates a credential, and may start a session). Controllers stay thin; `WebauthnCredential` holds the credential mutation.

### Registration — `Webauthn::RegisterCeremony`
- **`options`** (authenticated): ensure `webauthn_handle`; `WebauthnChallenge.issue(purpose: :registration, user:)`; build creation options via the gem with `resident_key: "required"` + `user_verification: "preferred"` (discoverable/usernameless) and `exclude` already-registered credential ids; return JSON.
- **`verify`** (authenticated): `WebauthnChallenge.consume!`; gem-verify the attestation against the challenge + configured origin; create the `WebauthnCredential` (external_id, public_key, initial sign_count, `verified_at: now`); on duplicate `external_id` raise `Webauthn::CredentialAlreadyRegistered`.

### Authentication — `Webauthn::AuthenticateCeremony`
- **`options`** (unauthenticated): `WebauthnChallenge.issue(purpose: :authentication)`; build request options with **empty `allowCredentials`** (usernameless/discoverable); return JSON.
- **`verify`** (unauthenticated): `WebauthnChallenge.consume!`; locate the `WebauthnCredential` by `external_id` (kept/undiscarded); gem-verify the assertion against the stored `public_key` + challenge + origin; **atomically advance `sign_count`** via a guarded `UPDATE … WHERE id = ? AND sign_count < ?` — if it doesn't advance, raise `Webauthn::ClonedAuthenticator` (reject 401 + security-log; do **not** auto-delete); set `last_used_at`; then `start_new_session_for(user)`.

The verify path runs in a single transaction so challenge-consume + sign_count-advance are serialized.

### Named error classes
`Webauthn::Error` < StandardError, with `UserCancelled`, `Unsupported`, `CredentialNotFound`, `CredentialAlreadyRegistered`, `VerificationFailed`, `ClonedAuthenticator`. Each maps to a distinct I18n message + status; the Stimulus controller maps the browser `DOMException` names (`NotAllowedError`/`InvalidStateError`/`NotSupportedError`) to the same vocabulary.

## Client (Stimulus + CSP)

A single `webauthn_controller.js` (CSP-safe: no inline JS; `fetch` + CSRF token + base64url encode/decode helpers):

- **Register:** on the settings/interstitial "Add a passkey" action → POST options → `navigator.credentials.create()` → POST verify.
- **Authenticate (button):** on click → POST options → `navigator.credentials.get()` (empty allowCredentials) → POST verify → on success navigate to `after_authentication_url`.
- **Authenticate (autofill):** at connect, if `window.PublicKeyCredential?.isConditionalMediationAvailable?.()` and secure context → call `get({ mediation: "conditional" })` against the email field marked `autocomplete="username webauthn"`; same verify path.
- **Feature detection / fallback:** if `!window.PublicKeyCredential` or `!window.isSecureContext`, the passkey button is not shown and the email/magic-link flow is the only surface. Every failure (cancel/no-credential/unsupported/verify-fail) announces (a11y) and leaves the user on the magic-link path.

## Sign-in UX

`sessions/new` keeps the email-first field (now `autocomplete="username webauthn"`) and adds a **"Sign in with a passkey"** button. There is no separate username step for passkeys — the button uses discoverable credentials. Failures never strand the user: they remain on the email entry → magic-link.

## Enrollment interstitial

After the first sign-in, if the user has no kept passkeys **and** `passkey_prompt_seen_at` is nil **and** the browser supports WebAuthn, render a one-time dismissible **`UI::DialogComponent`** ("Set up a passkey?" — Add / Not now). Either choice stamps `passkey_prompt_seen_at`. Always also reachable from settings.

## Settings management — `Settings::PasskeysController`

Mirrors `Settings::ConnectedAccountsController`: `index` (list kept credentials: nickname + last-used), `create` (registration verify, with nickname), `update` (rename — optional), `destroy` (soft-discard). Removal is always allowed (magic-link floor). Destroy is gated by a `UI::AlertDialogComponent` confirm.

## Accessibility contract (AAA; CI-proven)

- **Passkey button:** visible label/`aria-label`, ≥44px target, `focus-ring` (offset outline, never `focus:ring-*`); focus returns to the button after a cancelled/failed ceremony.
- **Fetch outcomes:** a persistent `role="status" aria-live="polite" aria-atomic="true"` region announces success / cancelled / verification-failed / no-passkey; focus is managed on failure.
- **Autofill:** the email field keeps a clear persistent `<label>`; `autocomplete="username webauthn"` doesn't break its semantics.
- **Interstitial:** `UI::DialogComponent` (focus trap, Escape, focus restore); heading via `aria-labelledby`; "Not now" a real focusable button; plain-language copy.
- **Settings list:** per-row remove `aria-label="Remove passkey: <nickname>"`; ≥44px; semantic list; empty state ("No passkeys yet"); destructive confirm.

## Security summary

Opaque handle (no enumeration); challenge is a DB nonce with **atomic one-time consume** + expiry (replay-safe across concurrent requests); `sign_count` advanced atomically with **clone detection** (reject + log, no auto-delete); `external_id` and `webauthn_handle` unique at the DB; RP ID/origin pinned from config and asserted; verification delegated entirely to the `webauthn` gem against the configured origin; CSP-compatible (Stimulus + `fetch` + CSRF, no inline JS).

## Testing strategy

- **Request-level (primary):** `WebAuthn::FakeClient` driving register + authenticate, **happy and error** paths — exercises *real* gem verification (a sanity spec confirms `FakeClient` rejects a forged attestation, so we know it's not a bypass). Cover: challenge **replay** (consumed challenge rejected), **expiry**, **origin/RP-ID mismatch**, `sign_count` **regression** (clone) → 401, unknown credential, duplicate registration.
- **Model/unit:** `WebauthnCredential#advance_sign_count!` regression guard; `WebauthnChallenge.consume!` atomicity; race-safe `webauthn_handle` generation; `Discardable` behavior.
- **System (Playwright CDP virtual authenticator — new `spec/support/webauthn_virtual_authenticator.rb`):** one happy-path smoke (button → real `navigator.credentials` → signed in) **plus** error-path smokes (user-cancel, no-passkey) and the interstitial once-only behavior. Passkey system specs run the **axe AAA** audit in both themes (the repo's CI-only AAA hook).
- **Factory:** `webauthn_credential` generated via `FakeClient` so `public_key` verifies against a real key.

## Documentation

`app/docs/passkeys.md` (a Phase-B deliverable, since config is needed to run it): what passkeys are + the magic-link fallback; **RP ID/origin configuration** per environment incl. the new-domain caveat (old passkeys invalidate → users re-register, magic-link covers them); **local HTTPS** testing; credential management; troubleshooting table; browser-support matrix. (Broader docs polish stays Phase C.)

## Out of scope / deferred (with trigger)

- Drop the enrollment interstitial (DHH dissent) — kept per product choice; revisit if adoption analytics show it's noise.
- A kill-switch feature flag — browser-detection + magic-link fallback already give graceful degradation; add if an incident needs a fast off-switch.
- Clone-detection *email* notification — ship reject+log first.
- Cross-browser system tests (Safari/Firefox) — Playwright is Chromium-only; pre-GA / manual.
- Passkey-only enforcement, attestation-statement enterprise policies, cross-device hybrid specifics beyond platform defaults.

## Risks / notes for the plan

- The **virtual-authenticator test harness** is new to this repo — the plan should stand it up early (it gates the system smoke) and fall back to request-level FakeClient coverage if a flow proves untestable in Playwright.
- Confirm the `webauthn` gem's exact API for options/verify + how it surfaces sign_count and verification errors, and pin the I18n/error mapping to the gem's real exceptions.
- The `webauthn` gem adds to the boot path; mirror it into any Rails-booting CI job (per the Gemfile-load-semantics lesson).
