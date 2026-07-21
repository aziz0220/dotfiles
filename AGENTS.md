# AGENTS.md — AI-Assisted Development Guide

This file documents the conventions, architecture, and patterns used in this repository so that AI agents (like opencode, Claude Code, or GitHub Copilot) can contribute effectively.

## Repository Purpose

A declarative, portable workstation bootstrap. One command provisions any Ubuntu machine (WSL2, cloud VM, bare metal) with dotfiles, secrets, packages, tools, and repos from an encrypted, version-controlled vault.

## Tech Stack

| Component | Technology |
|-----------|------------|
| Provisioning | Ansible (local playbook) |
| Secrets | AES-256-CBC + PBKDF2 via OpenSSL |
| CI/CD | GitHub Actions |
| Linting | yamllint, shellcheck, ansible-lint |
| Testing | Docker (local + CI) |
| Task runner | Makefile + justfile |
| Scripting | Bash (strict mode: `set -euo pipefail`) |

## Architecture

```
install (bootstrap)
  → ansible-run (orchestrator)
    → local.yml (main playbook)
      → roles/system_setup/   (system config)
      → roles/app_stack/      (packages, tools, runtimes)
      → roles/home_restore/   (dotfiles, secrets, repos)
```

Data sources:
- `vars/*.yml` — declarative machine state (version controlled)
- `vault/home-secrets.tar.gz.aes256` — encrypted secrets bundle
- `.bootstrap/home/` — decrypted secrets (gitignored)

## Key Conventions

### Shell scripts
- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail`
- Colors: `RED`, `GREEN`, `YELLOW`, `CYAN`, `BOLD`, `NC`
- Functions: `log()`, `warn()`, `err()`, `info()`, `header()`
- All scripts pass `shellcheck`

### Ansible
- Single playbook: `local.yml`
- Three roles: `system_setup`, `app_stack`, `home_restore`
- Tasks organized in `tasks/*.yml` by concern
- Variables in `vars/*.yml` — one file per concern
- Runtime variables: `user_name`, `user_home`, `user_uid`, `user_gid`, `user_shell`

### YAML
- Strict 2-space indentation
- No trailing spaces
- All `vars/*.yml` pass `yamllint --strict`
- No use of `!vault` Ansible vault (uses OpenSSL AES-256-CBC instead)

### Git
- Branch protection: required PRs, 1 approval, 4 status checks, linear history
- Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`
- Squash-merge only
- Encrypted vault only — never commit `.bootstrap/home/`

## Common Tasks

### Add a package
1. Add to the appropriate `vars/*.yml` file
2. If it needs a custom installer, add to `vars/custom-tools.yml`
3. Run `make validate`

### Add a new role
1. Create `roles/<name>/tasks/main.yml`
2. Include in `local.yml`
3. Add required files check in `Makefile` and CI

### Update CI checks
Edit `.github/workflows/ci.yml`. If check names change, update branch protection at:
`Settings > Branches > main > Edit > Status checks that must pass`

### Rotate vault password
```bash
bash scripts/rotate_vault_password.sh
```

### Test with Docker
```bash
make docker-test          # Ubuntu 24.04
make docker-test DISTRO=22.04  # Ubuntu 22.04
make docker-test DISTRO=26.04  # Ubuntu 26.04
```

## CI Pipeline

| Job | Description | Runs on |
|-----|-------------|---------|
| Lint | yamllint, shellcheck, ansible syntax, ansible-lint | ubuntu-latest |
| Validate | YAML syntax, required files, gitignore check, vault presence | ubuntu-latest |
| Secret scan | Check for tracked credentials outside vault | ubuntu-latest |
| Full provision | Full playbook run on clean system | ubuntu-22.04 + ubuntu-24.04 |
| Home restore | Restore over a clean distro home | ubuntu-26.04 container |

## Security

- Secrets encrypted with AES-256-CBC + PBKDF2 (OpenSSL)
- Vault password stored as GitHub secret `SETUP_SECRETS_PASSWORD`
- `.bootstrap/home/` is gitignored — never committed
- No `-iter` flag in OpenSSL commands (cross-version compatible)

## Contact

For questions or contributions, open an issue or PR at:
https://github.com/aziz0220/dotfiles
