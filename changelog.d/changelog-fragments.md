### Changed

- Each PR's changelog entry is a file of its own in `changelog.d/`, so entries no longer conflict; `bin/release prepare` gathers them into the release's notes, and `bin/sync` writes its links there too.
