# Ubuntu Setup (Ansible Bootstrap)

This repo is a clean bootstrap repo for rebuilding your workstation on a new machine.

Goal:
- install system packages
- restore dotfiles/configs
- restore SSH/GPG/secrets from an encrypted bundle
- clone working repositories
- validate parity after restore
- install key CLI tools (including `aws-cli` and `claude`)

## Quick Start

1. Install bootstrap dependencies:

```bash
./install
```

2. Set your secrets password and run full bootstrap:

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

Capture current machine config into `.bootstrap/home` (curated allowlist):

```bash
./scripts/capture_bootstrap_home.sh
```

Then encrypt it:

```bash
export SETUP_SECRETS_PASSWORD='YOUR_PASSWORD'
./scripts/encrypt_home_bundle.sh
```

Capture software inventory from current machine into Ansible vars (`apt`, `snap`, `npm -g`, `pipx`, `cargo`, `gem`, `flatpak`):

```bash
./scripts/capture_software_inventory.sh
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
- `roles/app_stack`: packages, snap, npm, pipx, cargo, gem, flatpak, runtimes
- `roles/home_restore`: user, groups, home restore, repos
- `vars/*.yml`: declarative machine snapshot inputs
- `scripts/*`: capture/encrypt/decrypt/validate helpers

## Notes

- Keep plaintext secrets only in `.bootstrap/home` (ignored by git).
- Commit only encrypted secrets artifacts in `vault/`.
- If bootstrap home is missing, `ansible-run` will auto-decrypt when an encrypted bundle is present and `SETUP_SECRETS_PASSWORD` is set.
- `aws-cli` is installed via snap (`classic`) from `vars/snap-list.yml`.
- `claude` CLI is installed via npm from `vars/npm-global.yml`.
- Add one-off installers to `vars/custom-tools.yml` using `check_cmd` + `install_cmd`, then re-run `./ansible-run`.
