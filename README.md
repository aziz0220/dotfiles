# Ubuntu Setup (Ansible Bootstrap)

This repo is the source-of-truth bootstrap repo for rebuilding your workstation on a new machine.

**Last captured: July 2026 — Ubuntu 24.04 (Noble) with Ansible-managed state.**

Goal:
- install system packages (apt, snap, npm, pipx, cargo)
- restore dotfiles/configs from captured bootstrap home
- restore SSH/GPG/cloud secrets from encrypted bundle
- clone working repositories
- install CLI tools (aws-cli, docker, ollama, kind, uv)
- set up runtimes (Node via nvm)

## Quick Start

On a **new Ubuntu 26.04+ WSL** distro:

1. Install bootstrap dependencies:

```bash
sudo apt-get update && sudo apt-get install -y ansible git curl
```

2. Clone this repo:

```bash
git clone https://github.com/aziz0220/ubuntu-setup.git && cd ubuntu-setup
```

3. Set your secrets password and run full bootstrap:

```bash
export SETUP_SECRETS_PASSWORD='YOUR_PASSWORD'
./ansible-run
```

This runs `local.yml` on localhost with `become`.

## Secrets Workflow

Plaintext home bootstrap data lives in:
- `.bootstrap/home` (gitignored)

Encrypted bundle lives in:
- `vault/home-secrets.tar.gz.aes256`

Decrypt bundle into `.bootstrap/home`:

```bash
export SETUP_SECRETS_PASSWORD='YOUR_PASSWORD'
./scripts/decrypt_home_bundle.sh
```

Encrypt `.bootstrap/home` back into vault bundle:

```bash
export SETUP_SECRETS_PASSWORD='YOUR_PASSWORD'
./scripts/encrypt_home_bundle.sh
```

## Re-capturing State (one-time migration)

Capture current machine config into `.bootstrap/home` (curated allowlist):

```bash
ALLOW_REPO_OVERWRITE=1 ./scripts/capture_bootstrap_home.sh
```

Then encrypt it:

```bash
export SETUP_SECRETS_PASSWORD='YOUR_PASSWORD'
./scripts/encrypt_home_bundle.sh
```

Capture software inventory from current machine into Ansible vars (`apt`, `snap`, `npm -g`, `pipx`, `cargo`, `gem`, `flatpak`):

```bash
ALLOW_REPO_OVERWRITE=1 ./scripts/capture_software_inventory.sh
```

## Validation

Run post-bootstrap checks:

```bash
./scripts/validate_setup.sh
```

Validation covers:
- required repo files
- package parity (normalized for `t64` transitions)
- repository path/git parity from `vars/repos.yml`
- home parity from `.bootstrap/home`

## Tags

Run a subset of tasks:

```bash
./ansible-run core
./ansible-run dotfiles
./ansible-run node
```

## Repo Structure

- `local.yml`: main playbook entrypoint
- `roles/system_setup`: apt sources, locale/timezone, services
- `roles/app_stack`: packages, snap, npm, pipx, cargo, gem, flatpak, runtimes, custom tools
- `roles/home_restore`: user, groups, home restore, repos
- `vars/*.yml`: declarative machine snapshot inputs
- `scripts/*`: capture/encrypt/decrypt/validate helpers

## Notes

- Repo-first model: `vars/*.yml` + `.bootstrap/home` are canonical.
- Keep plaintext secrets only in `.bootstrap/home` (ignored by git).
- Commit only encrypted secrets artifacts in `vault/`.
- `apt` package list uses `t64` fallback for cross-distro compatibility.
- Add one-off installers to `vars/custom-tools.yml` using `check_cmd` + `install_cmd`.
