### Changed

- Pre-push runs the specs a branch's changes can break (`bin/test-plan --run`) instead of the whole suite, and runs bundler-audit, erb_lint and mdl only when their inputs changed.
- Pre-commit refuses a staged YAML file that won't parse.
- CI checks a pull request that touches only locale files, docs or non-CI workflows with those lanes' specs on one runner; every other pull request, and every push to `next` and `main`, still runs the full sharded suite.
