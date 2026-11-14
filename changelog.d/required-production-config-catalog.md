### Fixed

- Production refuses to boot when the mail login or a sign-in provider's client id is still a placeholder.

### Added

- `bin/rails deploy:check` lists every input production needs, with where to get each one.
- A generated page, /docs/developer/required-production-config, and config/credentials/production.yml.example show every production input and where to get it.
