# Changelog

All notable changes to this package are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).
Every PR adds a changelog entry (checked by `scripts/dod.jl`): a lane adds a new
`changelog.d/<lane>.md` fragment, which `julia scripts/changelog.jl fold` moves under
`## Unreleased` at release; a change outside lanes may edit `## Unreleased` directly. Breaking
changes carry migration notes.

## Unreleased

Scaffold (pre-release; no API yet):

- Vendored the ecosystem factory template 0.2.1 (see `.factory-version`).
- Empty `ChuiCore` module (version 0.0.1, `julia = "1.10"`), MIT license.
- TestItemRunner test suite with a module-load item and Aqua / ExplicitImports quality items.
- Minimal Documenter skeleton in `docs/`.
