---
title: Instance operations
description: Who an operator is, how the first one comes to exist, what the operations area can and cannot do, and the security posture around it
keywords: operator operations admin instance bootstrap invite-only suspend lock workspace activity owner
---

# Instance operations

An **operator** administers the whole instance from above the workspaces:
creating and locking workspaces, looking users up, granting other operators,
and reading activity across every workspace. Operators are ordinary users
with an `Operatorship` row — nothing else marks them out, and holding one
does not make them a member of anything. The operations area never opens a
workspace the way a member does; see [Extending: Cross-workspace
queries](extending#cross-workspace-queries), Pattern 4.

## Day one on an invite-only instance

Nobody can reach `/operations` until an operator exists, so the first one is
minted from the command line:

```sh
bin/rails operators:grant[me@example.com]
bin/rails tenancy:owner_setup_link[me@example.com]
```

`operators:grant` looks the user up by email and grants an `Operatorship`
(idempotent — running it again just reports they're already an operator).
`tenancy:owner_setup_link` mints a short-lived sign-in link so the first
operator doesn't need a password to get in. Sign in with the link, then open
`/operations`.

Under the `:shared` preset (see [App Presets](presets)) this already happened
for you: the seed grants the bootstrap Owner an operatorship at boot, because
on that preset someone has to be able to create workspaces and see users
before anyone else exists.

## What the area does

- **Workspaces** (`/operations/workspaces`) — every kept workspace, locked
  ones included. Open one to see its member list and recent activity, lock
  or unlock it, or create a new one: an existing user's email makes them the
  owner immediately; an unknown email makes *the operator* the interim
  owner and sends that email an ordinary workspace invitation carrying the
  Owner role. See [The operator becomes the owner](#the-operator-becomes-the-owner)
  below — this is deliberate.
- **Users** (`/operations/users`) — a search box, not a browsable list: look
  a user up by their exact email address (names are encrypted
  non-deterministically and can't be searched or sorted in SQL — see
  [Security: Personal Data at Rest](security#personal-data-at-rest)). From a
  user's page, unlock a locked account or suspend their access outright
  (every session ends, every membership is discarded). Read [the
  caution](#caution-suspending-a-workspaces-sole-owner) below before
  suspending an owner.
- **Activity** (`/operations/activity_logs`) — every workspace's activity,
  newest first, paginated. Personal security events (password changes,
  passkeys, new devices) never appear here — that split is the same `admin`
  vs. `personal` visibility the rest of the app already uses.

  One kind of `admin` row is excluded on top of that split: a suppressed
  invitation delivery. Those rows are the only evidence that a recipient
  blocked an inviter, and on a single-operator instance the operator is
  usually the inviter — so admin visibility alone would hand them a way to
  confirm a block. `ActivityLog::INVITER_UNREADABLE_ACTIONS` names them and
  the feed filters them out. If you add an action whose existence would tell
  an inviter something a recipient chose not to tell them, add it there too.
- **Operators** (`/operations/operatorships`) — who can do all this, and who
  granted them. Granting takes an email that must already belong to a user;
  revoking removes an `Operatorship`, except the last one — see [How it
  stays safe](#how-it-stays-safe).

## What it deliberately does not do

- Act *inside* a workspace. Editing projects, changing settings, inviting
  members — that's a member's job. Grant yourself a membership the ordinary
  way if you need to do it (or, for a workspace you just created for an
  unknown owner, you're already in it).
- Scope an operator to some workspaces rather than all of them. An
  operator's reach is the whole instance today — `operated_workspaces` is
  every kept workspace, with no notion of "some." A scoped-operator arc that
  narrows this is planned, not built.
- Impersonate a user.

## The operator becomes the owner

Creating a workspace for an email with no account doesn't leave that
invitation floating with nobody to receive it: the operator who created the
workspace becomes its owner immediately, and the invited email gets an
ordinary Owner invitation through the same path any workspace invitation
uses. This was deliberate, not an oversight — "invited to nothing" isn't a
state this product has a page for, and routing it through the ordinary
invitation flow means every other page in the app can keep assuming a
workspace always has an owner.

The consequence: until the invited owner accepts, the operator is a real,
tenant-visible member of that workspace, showing up in its member list like
anyone else. Nothing removes them automatically — not on acceptance, not
ever. Hand off deliberately, the same way any owner would: transfer
ownership or leave the workspace once the new owner is in place. An operator
who creates workspaces regularly and never hands off accumulates
memberships this way; tracked as #1118.

## Caution: suspending a workspace's sole owner

`suspend_access!` discards every one of a user's memberships — including an
Owner one — without checking whether that leaves a workspace with zero kept
owners. The guard that normally blocks removing a workspace's last owner
lives on the ordinary deactivation path, not on the discard path suspension
uses, so it doesn't run here.

Suspending a user who is the sole owner of a workspace leaves that workspace
with nobody who can administer it. This is pre-existing behavior — the same
thing happened when this was only a rake task run by hand — and the
operations area makes it reachable with one click instead of shell access.
It isn't fixed here; it's tracked as #1120, pending a product decision.
Before suspending a user, check their memberships (their user page lists
every workspace they belong to) for any workspace where they're the only
owner.

## How it stays safe

- A non-operator gets a 404 on every `/operations` route — the area's
  existence isn't confirmed to them.
- Every request re-checks reauthentication, hard-wired on
  (`force: true`): it fires even for a fork that has turned
  `reauth_enabled` off. This is the app's only surface gated on *every*
  action, GET included, not just mutations — see [Security:
  Re-Authentication](security#re-authentication-sensitive-changes).
- `Operations::` controllers never include `WorkspaceScoped` and never set
  `Current.workspace`; a workspace is reached only through the signed-in
  operator's own reach relation, `Current.user.operated_workspaces`. See
  [Extending: Cross-workspace queries](extending#cross-workspace-queries),
  Pattern 4.
- The last operator can't be revoked from the panel — the roster refuses, so
  an instance can't lock everyone out through the UI. `bin/rails
  operators:revoke[email]` still can, deliberately: it's the break-glass
  path for an instance whose last operator has left or lost access, and
  it's a server-access operation, not a click.

  The guard (`Operatorship#revoke_by_operator!`) is atomic under
  concurrency: `BEGIN IMMEDIATE` opens the transaction at the block's first
  statement, so the count runs under the writer lock (`lock!` is only a
  reload on SQLite, not the mechanism) — two operators revoking two
  *different* rows can't both pass the count check and leave zero (the
  lock-then-check shape of every guarded mutator — see [Architecture §
  Concurrency](architecture); a Postgres fork must add an explicit lock). It
  also refuses an operator revoking their own row outright, and checks that
  case AFTER the last-operator one:
  when only one operator remains, that operator is necessarily the one
  attempting the revoke, so `:last_operator` is the more useful refusal — it
  names the break-glass path, where a generic self-revoke refusal would
  point at a second operator who doesn't exist.
- Granting and revoking an operatorship writes an audit row in the same
  transaction as the grant or revoke, and those rows sit behind the
  security retention floor described in [Security: Activity
  Tracking](security#activity-tracking).
- An operator locking or unlocking a workspace shows up in that workspace's
  *own* activity feed too, named as the actor — a tenant owner can see that
  an operator touched their workspace, not just that it happened.
