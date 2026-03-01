# Ubuntu 22.04 WSL Rebuild Playbook

This repository converts a live broken WSL user profile at `/mnt/recovery` into a reproducible Ansible setup for a new Ubuntu 22.04 WSL distro.

It captures:

- System configuration (`apt` sources, `wsl.conf`, timezone/locale, keyring)
- Installed package and enabled service lists
- UID/GID, shell, group memberships
- Home config including `.ssh`, `.gnupg`, `.config`, tool directories (`.nvm`, `.jenv`, `.sdkman`, `.zsh`, etc.)
- Repo inventory and clone endpoints
- SSH keys and credentials inside the extracted home archive

## Layout

- `collectors/build_recovery_seed.sh` – capture seed data from `/mnt/recovery`
- `collectors/sync_seed_to_vars.sh` – regenerate Ansible vars from seed
- `collectors/decrypt_seed.sh` – decrypt `home-config.tar.gz.aes256` if encrypted
- `scripts/run_rebuild.sh` – optional sync + run ansible
- `roles/` – ansible roles for system/app/home restore
- `vars/` – generated variables used by ansible
- `seed/` – generated snapshot (excluded by `.gitignore`)

## 1) Capture seed from broken distro

```bash
cd /mnt/recovery/home/aziz0220/ubuntu22-rebuild
./collectors/build_recovery_seed.sh /mnt/recovery ./seed aziz0220
# optional encryption:
RECOVERY_SEED_PASSWORD=... ./collectors/build_recovery_seed.sh /mnt/recovery ./seed aziz0220
```

## 2) Move this repo + seed to a fresh Ubuntu install

Copy `/mnt/recovery/home/aziz0220/ubuntu22-rebuild` and `seed/` out of the broken tree.

Optional security step:

```bash
rm -f seed/home-config.tar.gz
```

and keep only:

- `seed/home-config.tar.gz.aes256`

## 3) Restore

```bash
cd /path/to/ubuntu22-rebuild
if [ -f seed/home-config.tar.gz.aes256 ]; then
  RECOVERY_SEED_PASSWORD=... ./collectors/decrypt_seed.sh
fi
./scripts/run_rebuild.sh
```

## 3b) One command for /home/aziz0220 new distro

From a fresh Ubuntu shell:

```bash
cd /home
git clone git@github.com:aziz0220/ubuntu-setup.git
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
- verify seed archive exists
- regenerate all `vars/` from the seed metadata
- decrypt seed if encrypted
- run ansible to restore apt/system/home and clone required repos

`run_rebuild.sh` can also auto-decrypt when password is provided:

```bash
RECOVERY_SEED_PASSWORD=... ./scripts/run_rebuild.sh
```

`run_rebuild.sh` will:

- run `collectors/sync_seed_to_vars.sh` automatically
- generate all `vars/*.yml` from seed
- run `ansible-playbook site.yml`

If ansible is missing:

```bash
sudo apt-get update && sudo apt-get install -y ansible
```

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
bash -n collectors/build_recovery_seed.sh collectors/sync_seed_to_vars.sh scripts/run_rebuild.sh
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
