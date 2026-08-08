# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Also read `AGENTS.md` (conventions, security, CI table) and `README.md` (user-facing usage). This file covers only what those don't.

## Commands

```bash
make check                   # lint + validate — run this before any commit
make lint                    # yamllint --strict, shellcheck, ansible syntax+lint, bash regression tests
make validate                # vars/*.yml parse, required-file manifest, .bootstrap/home not tracked
make provision               # ./ansible-run (all tags)
make provision-dotfiles      # ./ansible-run dotfiles  (any tag works: core, node, ssh, home)
make docker-test DISTRO=26.04  # home-restore against a clean Ubuntu container

bash test/ansible_run_test.sh    # single test: ansible-run arg/sudo/decrypt behavior (mocks ansible-playbook)
bash test/home_state_test.sh     # single test: capture_bootstrap_home.sh .git-pruning + portability
bash test/wsl_lifecycle_test.sh  # shells out to test/wsl_lifecycle_test.ps1 via pwsh; SKIPs if absent
```

`ansible-run` requires either `.bootstrap/home/` to exist or `SETUP_SECRETS_PASSWORD` set (it auto-decrypts the vault). It also requires passwordless sudo unless you pass `-K`.

## Architecture

`install` → `ansible-run` → `local.yml`. There is one playbook and one host (`localhost`, `connection: local`).

The indirection that matters: `local.yml` never names a role. It includes four thin wrappers in `tasks/` (~10 lines each) that `import_role` the real work:

| wrapper | role | contains |
|---|---|---|
| `tasks/core-setup.yml` | `roles/system_setup` | apt sources, locale, timezone, systemd services |
| `tasks/node-setup.yml` | `roles/app_stack` | apt/snap/npm/pipx/cargo/gem/flatpak, nvm, `custom_tools` |
| `tasks/dotfiles.yml` | `roles/home_restore` | user/groups, home tree copy, SSH/GPG perms, repo clones |
| `tasks/ssh.yml` | — | inline; just creates `~/.ssh` |

Tags are declared **twice** — on the `include_tasks` in `local.yml` and again on the `import_role` in the wrapper. Adding a tag means editing both, or it silently won't select.

Runtime identity (`user_name`, `user_home`, `user_uid`, `user_gid`, `user_shell`) is detected by `ansible-run` from the invoking shell and passed as `-e`; `vars/user-profile.yml` only supplies defaults. Never hardcode `aziz0220` in roles.

## The two data flows

**Restore (normal direction):** `vars/*.yml` + `vault/home-secrets.tar.gz.aes256` → decrypt to `.bootstrap/home/` (gitignored) → roles apply to the machine.

**Capture (rare, one-time migration):** `scripts/capture_bootstrap_home.sh` and `scripts/capture_software_inventory.sh` overwrite the repo *from* the host. Both refuse to run without `ALLOW_REPO_OVERWRITE=1`. That guard is deliberate — the repo is the source of truth, not the machine. Use `scripts/validate_setup.sh` for drift checks instead.

Secrets are OpenSSL AES-256-CBC + PBKDF2 (`scripts/{en,de}crypt_home_bundle.sh`), not Ansible Vault. No `-iter` flag — cross-version compatibility.

## Adding software

Everything declarative goes in `vars/*.yml`, one file per package manager. Anything with a bespoke installer goes in `vars/custom-tools.yml` as `{name, check_cmd, install_cmd, become}` — `check_cmd` is what makes it idempotent, so it must be a cheap, accurate presence test. If a tool must be verified after provisioning, also add it to the `Verify installed components` step in `.github/workflows/ci.yml`.

## Windows/WSL layer

`scripts/wsl.ps1` (`up`/`down`) is a self-contained PowerShell orchestrator run from Windows, downloaded via `irm`. It must stay Windows PowerShell 5.1-compatible (no PS7-only syntax) and its behavior is covered by `test/wsl_lifecycle_test.ps1`, which mocks `wsl.exe`. This is the only test CI runs from the lint job's script suite.

## Keeping check definitions in sync

The same lint/validate logic is duplicated in four places: `Makefile`, `justfile`, `.github/workflows/ci.yml`, and `.pre-commit-config.yaml`. They have already drifted (`justfile` lint omits `home_state_test.sh`; CI's lint job runs neither bash regression test). When you change a check, update the ones that matter and say which you touched. `shellcheck` targets are an explicit file list — a new script in `scripts/` or `test/` is covered, a new top-level script is not until you add it.

Renaming a CI job breaks branch protection (4 required status checks on `main`); it must be updated in GitHub settings manually.
