---
title: Invitations
description: Receiving and accepting workspace, project, and client invitations
keywords: invitation invite workspace project client accept decline email-match magic link clientside
---

## Receiving an invitation

When an admin or project member invites you by email, you receive an invitation email with an **Accept** link. Invitations expire after 7 days; if yours has expired, ask the sender to resend it.

There are three invitation types:

| Type | Who sends it | Decline link included? |
|------|-------------|----------------------|
| Workspace member invitation | Workspace admin | Yes |
| Project collaborator invitation | Project member | Yes |
| Client invitation | Project member | No |

## Accepting an invitation

### If you already have an account

Click **Accept** in the email, sign in if prompted, and the invitation is accepted immediately. Your account's verified email must match the address the invitation was sent to.

### If you are new to the app

1. Click **Accept** in the email.
2. You will be prompted to sign in — enter the **same email address** the invitation was sent to and complete magic-link registration (you will receive a sign-in email).
3. The invitation is claimed once you verify the invited email address — not at the point of signup.

See [Authentication](/docs/user/authentication) for how magic-link sign-in works.

### Email-match guard

Emailed invitations are tied to a specific address. A leaked or forwarded invitation link **cannot be accepted from a different email address** — the guard rejects mismatches before the membership is created.

The one exception: **magic-link invitations** (a shareable URL that an admin copies and distributes, for example in a Slack channel) carry no email address and can be accepted by anyone with the link.

## Declining an invitation

Workspace and project invitations include a **Decline** link in the email. Clicking it marks the invitation as declined — no account or membership is created. Client invitations do not include a decline link; to decline, simply ignore it.

## Client invitations

A client invitation grants read-only access to specific resources within a single project via the client area. The invitation email uses the project name in the subject (not the workspace name).

**Existing users** accepting a client invitation: one click and you land directly in the client area.

**New users**: complete magic-link registration with the invited email address; the client access is granted once you verify that address.

The same email-match guard applies — a leaked client invitation link cannot be redeemed by a different email address.

For details on what clients can see and how workspace members share resources with clients, see [Clientside](/docs/user/clientside).

---

**Related:** [Workspaces](/docs/user/workspaces) · [Clientside](/docs/user/clientside)
