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

`bin/release` runs each step. Every command takes `--dry-run`.

| Step | Command |
| --- | --- |
| Name the release in the changelog | `bin/release prepare` |
| Cut the candidate | `bin/release cut` |
| Ship the reviewed commit | `bin/release ship <PR> <commit>` |
| Merge `main` back after a hotfix | `bin/release sync` |

## Prepare the changelog

```bash
bin/release prepare
```

PRs add their lines under `## [Unreleased]` in `CHANGELOG.md`. `prepare`
opens a PR into `next` that renames that section to the release, such as
`## v2026.10.27`, and folds its repeated `### Added` / `### Fixed` / ...
subsections into one each. It then starts a fresh, empty `[Unreleased]`
above it and turns on auto-merge, so the PR lands once its checks pass. It
commits through a temporary index, so your checkout is never touched.

The rename happens on `next`, before the cut, so that work merged during
review lands under the new `[Unreleased]`. Renaming on the release branch
instead would collide with those lines at the merge-back.

**A release is named for the day.** A second one the same day becomes
`2026.10.27-2`, then `-3`. The script skips any name already used by a tag or
a release branch.

## Cut a release

```bash
bin/release cut
```

Run it once the changelog PR has merged. It pushes `next` as
`release/<name>`, which deploys to staging, and opens the release PR into
`main` from the release template. The PR body names the branch, and its "What
ships" section is that release's changelog section. `cut` refuses a release
that already shipped, or one whose branch is already open.

## Review on staging

Review on staging, not on the PR's diff. A fix for something found in review
goes into the release branch by PR, and staging redeploys. A fix that `next`
also needs reaches it through the merge-back.

When review approves, record the commit staging is running in the PR's
"Commit reviewed on staging" field. The repository's Environments page shows
it on the latest staging deployment.

### Partial approval

When some of the changes aren't ready, revert them on the release branch, by
PR, and ship the rest:

```bash
git switch -c hold-back-search origin/release/2026.10.27
git revert -m 1 <the feature's merge commit>
# also delete its line from the release's CHANGELOG.md section
git push -u origin hold-back-search
gh pr create --base release/2026.10.27 --title "Hold back search for this release"
```

List each held-back PR and its revert commit under "Held back".

**The revert reaches `next` too.** After the release merges back, the held-back
feature is gone from `next` as well. To bring it back, revert the revert on
`next` by PR (`git revert <the revert commit>`), and put its changelog line
back under `[Unreleased]`. Don't re-merge the feature branch: git sees its
commits as already merged, so nothing comes back.

## Ship it

```bash
bin/release ship <release PR> <commit reviewed on staging>
```

It does three things:

1. Merges with `--match-head-commit <commit>`, so only the reviewed commit
   ships. If the branch moved after review, GitHub refuses ("Head branch was
   modified"), and the new commit gets reviewed on staging first. The merge
   deploys production, and the release branch is deleted.
2. Tags the merge commit `v<name>` and pushes the tag.
3. Merges `main` back into `next`, as below.

## Merge main back into next

`ship` does this itself. After a hotfix, run:

```bash
bin/release sync
```

It pushes a branch cut from `main` (`sync/<name>`), opens its PR into `next`,
brings it up to date, and turns on auto-merge with a merge commit. A PR whose
head is `main` itself can't be brought up to date, since that would push to
`main`, which is why a separate branch is needed. If `next` moves again before
the PR merges, press Update branch. Keep it **a merge commit**: a squash or
rebase leaves `main` out of `next`'s history, so every later release PR shows
changes `main` already has, and can conflict on them.

## Hotfix

A fix production can't wait a release for goes straight to `main`:

```bash
git switch -c hotfix/sign-in-loop origin/main
# fix, commit, push
gh pr create --base main --title "Sign-in no longer loops after a password reset"
```

Merging it deploys production. Then run `bin/release sync`. If a release
branch is open, bring the fix into it through a branch cut from `main` with a
PR into `release/<name>`.

## In case of emergency

The rulesets give no one a bypass, admins included. When production is down
and the PR path can't carry the fix (CI itself is broken, say), an admin
switches the blocking ruleset off, pushes, and switches it back on:

```bash
gh api repos/OWNER/REPO/rulesets --jq '.[] | "\(.id) \(.name)"'
gh api -X PUT repos/OWNER/REPO/rulesets/<id> -f enforcement=disabled
git push origin hotfix/sign-in-loop:main
bin/branch-rules   # add --solo if the repo runs solo; turns every ruleset back on
```

Rerunning `bin/branch-rules` puts back every ruleset exactly as
`config/github/rulesets/` describes it. Then merge `main` back into `next` as
after any hotfix. A ruleset left disabled is the risk here, so rerun the
script in the same sitting as the push.

## Changing the flow

The flow is a default, not a requirement. The branch rules live in
`config/github/rulesets/`, the deploys in `.github/workflows/deploy.yml`, the
steps in `bin/release`, and this page and the release template in
`.github/PULL_REQUEST_TEMPLATE/release.md` describe them. Change all of them
together.

The changelog convention is separate from the flow. It lives in
`lib/release_changelog.rb`, which `bin/release` uses only through `cut`,
`section` and `prepared_name`. A fork that keeps its changelog another way
replaces that file and leaves the rest alone.
