# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Machine-to-machine access: provisioning enables `tailscaled` and turns on Tailscale SSH, so every provisioned machine can reach every other one without key distribution, port forwarding, or a public SSH port
- Vault captures agent and editor CLI logins so a restored machine is signed in rather than merely configured: Claude Code, Copilot, Junie, opencode, Vercel, Kimi, and openconnect-sso
- Claude Code plugin and marketplace manifests are captured, so a restored machine reinstalls the same plugin set without carrying the 627MB of plugin payload
- Home restore rewrites the capturing user's literal home path in JSON and TOML configs, which have no `$HOME` expansion, keeping plugin manifests and editor settings valid under a different username
- Vault captures CLI auth tokens that previously existed only on one machine: `gh`, `stripe`, `netlify`, `neonctl`, `kaggle`, `huggingface`, `railway`, `docker`, `fly`, `gemini` and `.claude.json`
- `validate_setup.sh` warns about uncommitted or unpushed work, and about repositories with no remote, before a rebuild discards them
- Home restore backs up every file it overwrites to `~/.dotfiles-backup/<timestamp>/`, so restoring onto an out-of-date machine cannot silently discard uncaptured local edits
- `ansible-run` warns when the clone is behind its upstream instead of silently provisioning from stale vars and a stale vault (`DOTFILES_SKIP_FETCH=1` to stay offline)
- Professional README with badges, architecture diagram, and documentation
- One-command bootstrap via `bash <(curl -fsSL ...)` — auto-installs dependencies, prompts for vault password
- One-command Windows PowerShell lifecycle for installing, bootstrapping, validating, launching, exporting, and removing isolated, named WSL distros
- Makefile with `lint`, `validate`, `check`, `provision` targets
- `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `LICENSE`
- `.editorconfig` and `.pre-commit-config.yaml`

### Changed
- Documentation states what is deliberately *not* restored — project repositories, unpushed work, remote-less repos — instead of advertising "repos" as a restored category, and documents the `~/.dotfiles-backup/<timestamp>/` safety net, the behind-origin warning, `DOTFILES_SKIP_FETCH`, `INCLUDE_PRIVATE`, and username independence
- Personal project repositories are no longer tracked or cloned; cloning, pushing and pulling your own work is the user's responsibility, since the provisioner cannot know about unpushed commits
- `install` script rewritten for multi-platform support (WSL, cloud VM, bare metal)
- `ansible-run` script improved with better error messages and environment detection
- CI workflow modernized with `actions/setup-python` and `ansible-lint` action
- Documentation restructured for clarity
- Home restore now syncs over pre-existing Ubuntu skeleton files and validates restored state
- Custom tools install as the target user and are required to pass post-install verification
- WSL services use distro-specific SSH/ttyd ports and Tailscale userspace networking
- Ubuntu 26.04 compatibility treats obsolete snapshot libraries as release-inapplicable

### Fixed
- Create supplemental groups by name without pinning captured GIDs, which collided with the primary group of any user whose uid differed from the capturing machine's and aborted user creation
- Dereference symlinks that escape the captured tree, so a WSL `~/.aws` pointing at `/mnt/c/...` is captured as real credentials instead of a link that dangles on every other machine
- Rewrite the capturing user's absolute home path to `$HOME` in captured shell rc files so a restored bundle works under any username
- Default `validate_setup.sh` to the invoking user instead of a hardcoded account name
- Derive WSL SSH and ttyd ports from the instance name so parallel distros do not collide
- Install Ubuntu's native Docker Engine package without mistaking Docker Desktop's Windows CLI for a Linux installation
- Run lifecycle payloads in a clean non-login Bash shell so incomplete restored profiles cannot block provisioning
- Exclude repository `.git` internals from portable home snapshots and parity checks
- Verify command-level non-interactive sudo access instead of using `sudo -v`, which can still prompt under mixed sudo policies
- Encode interactive user bootstrap and validation Bash payloads while preserving terminal input for vault prompts
- Repair partially created WSL users without a usable password and verify temporary passwordless sudo before bootstrap
- Encode embedded root Bash scripts before passing them through Windows PowerShell 5.1 and `wsl.exe`, preserving variables and multiline commands
- Preserve native `wsl.exe` exit-code handling when Windows PowerShell 5.1 reports harmless stderr warnings such as a failed root systemd user session
- Skip redundant `wsl --set-version` conversion when a newly installed named distro is already WSL2
- Normalize NUL-padded `wsl.exe` output captured by Windows PowerShell 5.1 so online and registered distros are detected correctly
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
