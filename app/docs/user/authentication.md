---
title: Authentication
description: How to sign in and out — magic links, passkeys, and OAuth (Google / GitHub)
keywords: sign in sign out magic link passkey passwordless oauth google github account recovery first sign-in
---

## Signing in

This app is **passwordless-first**: you sign in by entering your email address, and a sign-in link is emailed to you. Click the link and you're in — no password needed.

### Magic link (email)

1. Go to the sign-in page and enter your email address.
2. Check your inbox for a sign-in email (subject: "Sign in to …"). It arrives within a few seconds.
3. Click the link in the email — it signs you in immediately.

The link is single-use and expires after a short window. If it expires, return to the sign-in page and request a fresh one.

For more on the emails this process sends, see [Email Flows](/docs/user/emails).

### Passkeys (fingerprint / Face ID / device PIN)

Passkeys let you sign in with your device's biometric or PIN instead of waiting for an email. After your first magic-link sign-in, a banner invites you to add a passkey — it only appears once. You can also add or manage passkeys any time at **Settings → Passkeys**.

Once a passkey is registered, clicking "Sign in with a passkey" on the sign-in page lets your browser or device authenticate you instantly — no email required.

For setup details (Relying Party configuration, browser support, troubleshooting), see [Passkeys](/docs/developer/passkeys).

### OAuth (Google or GitHub)

If Google or GitHub sign-in is enabled, you can use the provider button on the sign-in page instead of email. On your first visit the provider creates an account for you. On subsequent visits it signs you back in.

If you already have an account (by email) and want to link Google or GitHub to it: sign in first, then click the provider button — if the provider email matches your account, the provider is linked automatically. Manage all linked sign-in methods at **Settings → Connected Accounts**.

### First sign-in (new accounts)

When you sign in for the very first time with a new email address, the app prompts you to enter your name before continuing. No separate verification step is required — clicking the magic link proves ownership of the email address.

After registration, a non-blocking banner suggests adding a passkey. You can dismiss it or add one immediately; either way it will not appear again.

## Account recovery

There is no separate "forgot password" reset flow. If you can't sign in, request a **magic link** from the sign-in page — the same flow used for normal sign-in. Click the link to get back in, then visit **Settings → Password** if you want to update your password.

## Signing out

Use the user menu (top right) to sign out. Sessions are not shared across browsers or devices.

---

**Related:** [Email Flows](/docs/user/emails) · [Invitations](/docs/user/invitations) · [Passkeys (developer)](/docs/developer/passkeys)
