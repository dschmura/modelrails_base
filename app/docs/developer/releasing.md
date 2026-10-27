---
title: Releasing
description: Cut a release candidate, review it on staging, ship it to production, and keep next in step
keywords: release candidate staging production hotfix revert tag next main merge-back
---

# Releasing

A change takes one path: a PR into `next`, a release branch cut from `next`
and reviewed on staging, then a PR from that branch into `main`, which is
production. [Forking](forking#protect-the-branches) sets up the branch rules
with `bin/branch-rules`, and [Deployment](deployment#5-deploy-from-ci) switches
on the deploys.

| Branch | Deploys to | Takes changes from |
| --- | --- | --- |
| `next` | nowhere | feature PRs |
| `release/<date>` | staging | its cut from `next`, then fix and revert PRs |
| `main` | production | release and hotfix PRs |

## Cut a release

Push `next` as a new release branch named for the day (add `-2` for a second
one the same day). The rules allow creating a branch, and the push deploys it
to staging:

```bash
git fetch origin
git push origin origin/next:refs/heads/release/2026.10.27
```

Open its PR now, so reviewers have one place to talk:

```bash
gh pr create --base main --head release/2026.10.27 --title "Release 2026.10.27" \
  --body-file .github/PULL_REQUEST_TEMPLATE/release.md
```

## Review on staging

Review on staging, not on the PR's diff. A fix for something found in review
goes into the release branch by PR, and staging redeploys. A fix that `next`
also needs reaches it through the merge-back below.

When review approves, record the commit staging is running in the PR's
"Commit reviewed on staging" field. The repository's Environments page shows
it on the latest staging deployment.

### Partial approval

When some of the changes aren't ready, revert them on the release branch, by
PR, and ship the rest:

```bash
git switch -c hold-back-search origin/release/2026.10.27
git revert -m 1 <the feature's merge commit>
git push -u origin hold-back-search
gh pr create --base release/2026.10.27 --title "Hold back search for this release"
```

List each held-back PR and its revert commit under "Held back".

**The revert reaches `next` too.** After the release merges back, the held-back
feature is gone from `next` as well. To bring it back, revert the revert on
`next` by PR (`git revert <the revert commit>`). Don't re-merge the feature
branch: git sees its commits as already merged, so nothing comes back.

## Ship it

Merge with the reviewed commit, not with the button:

```bash
gh pr merge <release PR> --merge --match-head-commit <commit reviewed on staging>
```

If the branch moved after review, GitHub refuses ("Head branch was modified"),
and the new commit gets reviewed on staging first. The merge deploys
production, and the release branch is deleted.

Tag the merge commit on `main` so a release has a name:

```bash
git fetch origin
git tag -a v2026.10.27 origin/main -m "Release 2026.10.27"
git push origin v2026.10.27
```

## Merge main back into next

Do this after every release and every hotfix. A PR whose head is `main` itself
can't be brought up to date, since that would push to `main`, so go through a
branch cut from it:

```bash
git fetch origin
git push origin origin/main:refs/heads/sync/main-into-next
gh pr create --base next --head sync/main-into-next --title "Merge main back into next" \
  --body "After release 2026.10.27."
```

Update the branch if GitHub asks, then merge with **a merge commit**. A squash
or rebase leaves `main` out of `next`'s history, so every later release PR
shows changes `main` already has, and can conflict on them.

## Hotfix

A fix production can't wait a release for goes straight to `main`:

```bash
git switch -c hotfix/sign-in-loop origin/main
# fix, commit, push
gh pr create --base main --title "Sign-in no longer loops after a password reset"
```

Merging it deploys production. Then merge `main` back into `next` as above.
If a release branch is open, bring the fix into it the same way, through a
branch cut from `main` with a PR into `release/<date>`.

## Changing the flow

The flow is a default, not a requirement. The branch rules live in
`config/github/rulesets/`, the deploys in `.github/workflows/deploy.yml`, and
this page and the release template in `.github/PULL_REQUEST_TEMPLATE/release.md`
describe them. Change all of them together.
