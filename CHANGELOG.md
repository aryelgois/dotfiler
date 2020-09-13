# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added

- `mount` and `umount` commands support `--`

### Changed

- Replace `mkdir -p` with a more portable command
- Refactor parsing arguments
- `init` takes two optional arguments `REPO_ROOT` and `DIR`

### Removed

- Unused and duplicated code

### Fixed

- Use correct git repository when outside of it
- Avoid using a repository at `$HOME` or above
- Detect git repository when a FUSE mountpoint is in place


## [0.1.0] - 2019-10-26

### Added

- Implementation in shell script
  - `dotfiler init`
  - `dotfiler mount`
  - `dotfiler umount`
  - `dotfiler add`
  - `dotfiler rm`
- [Makefile]


[unreleased]: https://github.com/aryelgois/dotfiler/compare/v0.1.0...develop
[0.1.0]: https://github.com/aryelgois/dotfiler/compare/initial-commit...v0.1.0

[makefile]: Makefile
