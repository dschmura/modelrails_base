<!-- A release/<date> branch into main. The guide: /docs/developer/releasing -->

## Release

- Branch: `release/YYYY.MM.DD`
- Commit reviewed on staging: <!-- the full SHA from the staging deployment record -->

## What ships

<!-- The PRs merged since the last release: git log --merges --oneline origin/main..HEAD -->

## Held back

<!-- PRs reverted on this branch, each with its revert commit, so next can restore them after the merge-back. Delete if none. -->

## Ship it

The merge button doesn't check what was reviewed. This does, and refuses if the branch moved since:

```bash
gh pr merge <this PR> --merge --match-head-commit <the commit above>
```
