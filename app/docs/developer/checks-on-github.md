---
title: Checks on GitHub
description: The checks GitHub Actions runs on every push and pull request, and the ones it runs on a schedule. Also called CI.
keywords: ci continuous integration github actions checks pull request static test shard lane_specs fork_shaped_specs docker_build image_scan scheduled workflow cve audit
---

# Checks on GitHub

`git push` runs the [pre-push checks](/docs/developer/before-you-push) on your machine first. Then GitHub Actions runs its own checks: on every push and pull request, and some on a schedule. This is what people mean by CI. A CVE, below, is a published security vulnerability in a package the app uses.

## On every push and pull request

The test checks split the suite into shards, slices that run side by side; [Testing](/docs/developer/testing#ci-sharding) explains how they're split and which specs a change selects.

| Check | What it checks |
|-------|----------------|
| `static` | One job for every static check: Brakeman, bundler-audit (gem CVEs), the importmap audit (JS dependency CVEs), RuboCop with GitHub annotations, the comment-block gate over the PR's diff, `mdl` (markdown) and `erb_lint` (ERB). Each check runs even after an earlier one fails, so one push reports every failure. They were four jobs; one runner minute bills for what took four. |
| `changes` | Sorts a pull request's changed files into [change lanes](/docs/developer/testing#change-lanes) with `bin/test-plan`, for a pull request into `next`. A push, and a pull request into `main` or a `release/` branch, is always `full`, unless it differs only in the changelog from a parent commit CI passed on (waiting up to 8 minutes for that parent's push run to finish): then nothing runs the specs ([why](/docs/developer/testing#change-lanes)) |
| `lane_specs` | On a pull request that touches only lanes (locale, docs, workflows), runs just those lanes' specs on one runner, with the same browser and compiled assets as a shard |
| `test_shard` | The full RSpec suite with Cuprite and the axe accessibility audit, split across parallel shards (eight by default, set by the `CI_SHARDS` repository variable), on a `full` change and on every push to `next` and `main`; each uploads screenshots when it fails |
| `fork_shaped_specs` | Runs the specs that read `config/deploy.yml` in a fresh fork made with `bin/fork` and `bin/deploy-setup`, so a spec that passes only on the template's untouched file fails here rather than in a fork's CI ([why](/docs/developer/testing#specs-that-read-configdeployyml-run-in-a-fork-too)). Every change except a changelog-only one; in a fork it does nothing |
| `test` | Passes only when whichever path ran passed, along with `fork_shaped_specs`: `lane_specs` on a lane change, every shard on a `full` one, and nothing on a changelog-only change from a green parent. After a full run it checks the merged results: every example ran, and coverage meets the 90% floor. This is the check the branch ruleset requires by name |
| `docker_build` | Verifies the production `Dockerfile` builds (catches build-time regressions that structural specs cannot). Its own workflow, run on every push to `main`, unfiltered. A pull request that changes a build input (`Dockerfile`, `.dockerignore`, `Gemfile`, `Gemfile.lock`, `.tool-versions`, `bin/docker-entrypoint`) gets the same proof from `image_scan`, which builds the identical image from scratch, so `docker_build` runs on a pull request only when its own workflow changes. The pre-push hook runs the same build locally through `bin/docker-build-check` on the same inputs. Uses GHA layer caching — cold builds ~3-5 min, warm builds ~30-60s. See [Deployment](/docs/developer/deployment). |

## Scheduled checks

Six checks answer questions a per-PR run cannot, because what they watch changes without anyone committing. Every one but `workflow_audit` also runs on demand from the Actions tab (`workflow_dispatch`).

| Check | When | What it checks |
|-------|------|----------------|
| `js_advisory` | Daily | The same importmap audit as the `static` job, against `main` — an advisory published between pushes is otherwise invisible until the next PR happens to touch the tree. `static` stays the required check; this is additive. |
| `image_scan` | Weekly, plus every PR that changes a build input | OS-package CVEs in the production image, which appear without any code change. It builds the image from scratch, so on those PRs it is also the proof that the image builds. |
| `hotcell_image_scan` | Weekly where the `HOTCELL_SCAN` repository variable is set, plus every PR that changes `hotcell/` | The same scan of the [Hot Cell](/docs/developer/hot-cell) image. A fork that keeps the cell off leaves the variable unset and pays for no weekly build. |
| `fork_vocabulary` | Weekly | The whole suite under `spec/fixtures/vocabulary.course.yml`, proving the promise that a fork renaming its nouns keeps this suite green. The per-PR gate catches literal-noun copy assertions in the shapes it knows; this catches the rest. |
| `devcontainer` | Weekly, plus every PR that changes `.devcontainer/`, `Dockerfile`, `Gemfile.lock`, `.tool-versions` or `bin/setup` | Builds the Dev Container and runs its setup, which a change to the base image or a feature can break with no commit here. |
| `workflow_audit` | Weekly, plus every PR that changes `.github/` or `mise.toml`/`mise.lock` | `jactionlint` over the workflows and `dependabot.yml`; the weekly run catches a pinned action archived or advised against since. |

**Scheduled workflows switch themselves off in an inactive public repository.** GitHub disables them after 60 days with no repository activity — see [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) (`schedule`). The condition is repository *visibility*, so a private fork is not affected; a public fork that goes quiet loses these six checks silently and re-enables them with any repository activity.
