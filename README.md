# Ubuntu 22.04 WSL Rebuild Playbook

This repository converts a live broken WSL user profile at `/mnt/recovery` into a reproducible Ansible setup for a new Ubuntu 22.04 WSL distro.

It captures:

- System configuration (`apt` sources, `wsl.conf`, timezone/locale, keyring)
- Installed package and enabled service lists
- UID/GID, shell, group memberships
- Home config including `.ssh`, `.gnupg`, `.config`, tool directories (`.nvm`, `.jenv`, `.sdkman`, `.zsh`, etc.)
- Repo inventory and clone endpoints
- SSH keys and credentials inside `seed/home/` (directory snapshot)

## Layout

- `collectors/build_recovery_seed.sh` – capture seed data from `/mnt/recovery`
- `collectors/sync_seed_to_vars.sh` – regenerate Ansible vars from seed
- `collectors/decrypt_seed.sh` – decrypt `home-config.tar.gz.aes256` if encrypted
- `collectors/encrypt_home_bundle.sh` – create encrypted `vault/home-secrets.tar.gz.aes256` for safe GitHub storage
- `install` – Primeagen-style ansible bootstrap installer
- `ansible-run` – Primeagen-style local ansible runner (`local.yml`)
- `scripts/run_rebuild.sh` – recovery-aware runner (sync/decrypt + ansible)
- `scripts/validate_seed.sh` – full seed-vs-recovery validation report
- `local.yml` – Primeagen-style localhost entrypoint using `tasks/`
- `tasks/` – Primeagen-style task pipeline (`ssh.yml`, `core-setup.yml`, `node-setup.yml`, `dotfiles.yml`)
- `roles/` – ansible roles for system/app/home restore
- `vars/` – generated variables used by ansible
- `seed/` – generated snapshot (excluded by `.gitignore`)

## 1) Capture seed from broken distro

```bash
cd /home/aziz0220/ubuntu-setup
# ensure the broken disk is mounted read-only at /mnt/recovery first
# (example: sudo mount -o ro /dev/sdX /mnt/recovery)
./collectors/build_recovery_seed.sh /mnt/recovery ./seed aziz0220
# optional full-state capture (large):
SEED_HOME_MODE=full ./collectors/build_recovery_seed.sh /mnt/recovery ./seed aziz0220
```

This collector now reads directly from `/mnt/recovery`:

- package inventory from `var/lib/dpkg/status`
- enabled services from `etc/systemd/system` symlinks
- group/user metadata from `etc/passwd` + `etc/group`
- snap inventory from `var/lib/snapd/snaps`
- git remotes by scanning repos under `home/<user>`
- runtime versions/defaults from `.nvm` and `.sdkman`
- home dotfiles/config snapshot into `seed/home/` (directory-first workflow)

`seed/home/` defaults to a bootstrap-focused snapshot (dotfiles, shell/git config, `.config`, keys, selected tool config) and excludes high-volume session/cache data.
Set `SEED_HOME_MODE=full` for a larger forensic-style full-state home capture.

## 2) Move this repo + seed to a fresh Ubuntu install

Copy `/mnt/recovery/home/aziz0220/ubuntu22-rebuild` and `seed/` out of the broken tree.

The seed output is now directory-first:

- `seed/home/` (restored home tree, config-focused)
- `seed/metadata/` (packages/services/repos/runtime metadata)
- `seed/system/` (OS config snapshots)

Legacy archive mode (`home-config.tar.gz`) is still supported by restore scripts for backward compatibility, but not required.

## 2b) Secure public GitHub workflow (Primeagen-style)

For a public repo, keep plaintext home data out of git and commit only encrypted secrets:

```bash
RECOVERY_SEED_PASSWORD='your-passphrase' \
  ./collectors/encrypt_home_bundle.sh ./seed ./vault/home-secrets.tar.gz.aes256
```

This encrypted file can be committed safely. Plaintext `seed/` remains ignored by `.gitignore`.

## 3) Restore

```bash
cd /path/to/ubuntu22-rebuild
./install
./ansible-run
```

`ansible-run` uses `local.yml` by default (matching ThePrimeagen workflow).  
`scripts/run_rebuild.sh` is still available for seed sync + decrypt + run in one command.
`site.yml` is kept as a compatibility wrapper that imports `local.yml`.

## 3b) One command for /home/aziz0220 new distro

From a fresh Ubuntu shell:

```bash
cd /home
git clone git@github.com:aziz0220/ubuntu-setup.git ubuntu22-rebuild
cd /home/aziz0220/ubuntu22-rebuild

# Copy seed folder from the broken disk to:
# /home/aziz0220/ubuntu22-rebuild/seed
# or to --seed-dir and set the path below.
RECOVERY_SEED_PASSWORD=... ./scripts/full_restore.sh --seed-dir /home/aziz0220/ubuntu22-rebuild/seed --user aziz0220
```

Dry-run (safe preview) before running live:

```bash
DRY_RUN=1 ./scripts/full_restore.sh --seed-dir /home/aziz0220/ubuntu22-rebuild/seed --user aziz0220 --recovery-root /mnt/recovery
```

When the repo is already present and you just want to run the seed/apply step on a fresh copy:

```bash
cd /home/aziz0220/ubuntu22-rebuild
./scripts/full_restore.sh --skip-update --seed-dir /home/aziz0220/ubuntu22-rebuild/seed --user aziz0220
```

The full command performs these exact steps on `/home/aziz0220`:

- clone/fetch `git@github.com:aziz0220/ubuntu-setup.git` into `/home/aziz0220/ubuntu22-rebuild`
- verify restore source exists (`seed/home`, legacy archive, or `vault/home-secrets.tar.gz.aes256`)
- regenerate all `vars/` from seed metadata when metadata is present
- run ansible to restore apt/system/home and clone required repos

`run_rebuild.sh` can auto-decrypt:

- legacy `seed/home-config.tar.gz.aes256`
- `vault/home-secrets.tar.gz.aes256` (into `seed/home`) when `RECOVERY_SEED_PASSWORD` is provided

`run_rebuild.sh` will:

- run `collectors/sync_seed_to_vars.sh` automatically
- generate all `vars/*.yml` from seed
- run `ansible-playbook local.yml` (Primeagen-style entrypoint)
- auto-install `ansible` (via `apt`) when missing

If ansible installation fails automatically:

```bash
sudo apt-get update && sudo apt-get install -y ansible
```

## Reliability behavior

The playbook is designed to stay reproducible across target machines while surfacing real drift:

- restores base OS first, then user/home state, then runtime/app stack
- installs only snapshot packages available on the target release and prints skipped package names
- enables only services that exist on the target and prints unavailable services
- fails fast when required repo clone or required snap install fails
- preserves runtime defaults for `nvm` and `sdkman` versions from `vars/runtimes.yml`
- warns when source-home symlinks point outside Linux home (for example WSL `/mnt/c/...`) so you can migrate those credentials manually

## Mandatory repos restored

The following are guaranteed in `vars/repos.yml`:

- `cli-agent-orchestrator`
- `pipmedia`
- `SWE-Refactor`
- `RefactorBench`

All clone URLs are preserved from the source machine; discovered repos such as `.nvm`, `.jenv`, `.oh-my-zsh`, and `.config/nvim` are also included for parity.

## Quick validation commands

```bash
./collectors/build_recovery_seed.sh /mnt/recovery ./seed aziz0220
./collectors/sync_seed_to_vars.sh ./seed /mnt/recovery aziz0220
./scripts/validate_seed.sh ./seed /mnt/recovery aziz0220
bash -n collectors/build_recovery_seed.sh collectors/sync_seed_to_vars.sh scripts/run_rebuild.sh
ansible-playbook --syntax-check local.yml
```

At least validate on a fresh target:

```bash
git -C /home/aziz0220 status --short
ls -la /home/aziz0220/.ssh
```

Then run:

```bash
source /home/aziz0220/.zshrc
java -version
node -v
```
