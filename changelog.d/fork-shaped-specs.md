### Added

- CI's `fork_shaped_specs` job runs the specs that read `config/deploy.yml` in a fresh fork made with `bin/fork` and `bin/deploy-setup`, so a spec that only passes on the template's own file fails in the template's pull request instead of a fork's CI.
