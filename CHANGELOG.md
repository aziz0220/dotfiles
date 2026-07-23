# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Professional README with badges, architecture diagram, and documentation
- One-command bootstrap via `bash <(curl -fsSL ...)` — auto-installs dependencies, prompts for vault password
- One-command Windows PowerShell lifecycle for installing, bootstrapping, validating, launching, exporting, and removing isolated, named WSL distros
- Makefile with `lint`, `validate`, `check`, `provision` targets
- `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `LICENSE`
- `.editorconfig` and `.pre-commit-config.yaml`

### Changed
- `install` script rewritten for multi-platform support (WSL, cloud VM, bare metal)
- `ansible-run` script improved with better error messages and environment detection
- CI workflow modernized with `actions/setup-python` and `ansible-lint` action
- Documentation restructured for clarity
- Home restore now syncs over pre-existing Ubuntu skeleton files and validates restored state
- Custom tools install as the target user and are required to pass post-install verification
- WSL services use distro-specific SSH/ttyd ports and Tailscale userspace networking
- Ubuntu 26.04 compatibility treats obsolete snapshot libraries as release-inapplicable

### Fixed
- Forward arbitrary Ansible arguments such as `--ask-become-pass` instead of treating them as tags
- Surface failed repository clones instead of reporting a successful playbook
- Install current Junie, Copilot, clangd, Rust, Cloudflare, Tailscale, and Stripe CLIs
- Keep user-scoped tools discoverable from clean login shells with portable `$HOME`-relative paths
- Create an isolated WSL instance from a registered local source when the requested release is missing from the online catalog

## [0.1.0] — 2026-03-01

### Added
- Initial release with Ansible-based bootstrap
- Encrypted secrets vault (AES-256-CBC + PBKDF2)
- System setup role (APT sources, locale, timezone, services)
- App stack role (packages, snap, npm, pipx, cargo, gem, flatpak, runtimes)
- Home restore role (user, groups, dotfiles, SSH, GPG, repos)
- Capture scripts for bootstrapping home and software inventory
- Decrypt/encrypt scripts for secrets management
- Validation script for post-provision checks
- CI pipeline with lint, validate, secret scan, and full provision
- Branch protection with required reviews and status checks
