<div align="center">
  <h1>Dotfiles</h1>
  <p><strong>One command to restore your entire development environment — dotfiles, secrets, packages, and tools.</strong></p>

  <p>
    <a href="https://github.com/aziz0220/dotfiles/actions/workflows/ci.yml">
      <img src="https://github.com/aziz0220/dotfiles/actions/workflows/ci.yml/badge.svg" alt="CI">
    </a>
    <a href="LICENSE">
      <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License">
    </a>
    <a href="https://github.com/aziz0220/dotfiles">
      <img src="https://img.shields.io/badge/ansible-11.0%2B-orange.svg" alt="Ansible">
    </a>
    <a href="https://github.com/aziz0220/dotfiles">
      <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome">
    </a>
    <a href="https://github.com/aziz0220/dotfiles">
      <img src="https://img.shields.io/badge/maintained-yes-green.svg" alt="Maintenance">
    </a>
    <a href="https://github.com/aziz0220/dotfiles">
      <img src="https://img.shields.io/github/stars/aziz0220/dotfiles?style=social" alt="Stars">
    </a>
  </p>
</div>

---

Provision any Ubuntu machine — WSL2, cloud VM, bare metal, or VM — with your complete development environment in a single command. Your dotfiles, SSH keys, GPG keys, cloud credentials, packages, CLI tools, and runtimes are restored from an encrypted, version-controlled source of truth.

Your own project repositories are **not** part of that source of truth — see [What gets restored](#what-gets-restored-and-what-does-not).

## Features

- **One-command bootstrap** — `curl -fsSL https://raw.githubusercontent.com/aziz0220/dotfiles/main/install | bash`
- **One-command WSL lifecycle** — create, bootstrap, validate, launch, export, or remove a distro from PowerShell
- **Encrypted secrets** — SSH keys, GPG keys, AWS credentials, kube config stored in AES-256-CBC + PBKDF2 vault
- **Declarative machine state** — a curated apt essentials list plus snaps, npm/pip/cargo/gem packages and runtimes as version-controlled YAML
- **Idempotent** — safe to run multiple times; only installs what's missing
- **Tagged execution** — run only what you need: `./ansible-run dotfiles`, `./ansible-run node`, etc.
- **Username-independent** — restores under any account name; UID/GID, home path, and shell are detected at runtime and captured `$HOME` paths are rewritten
- **Non-destructive** — every file a restore overwrites is kept in `~/.dotfiles-backup/<timestamp>/`
- **Cross-distro compatible** — full provisioning on Ubuntu 22.04/24.04 plus Ubuntu 26.04 WSL home-restore coverage
- **CI-verified** — every commit runs lint, validation, secret scan, multi-LTS provisioning, and a 26.04 regression
- **Portable** — works on WSL2, cloud VMs (AWS, GCP, Azure), bare metal, VMware/VirtualBox

## Quick Start

### Prerequisites

- Ubuntu 22.04+ (Jammy, Noble, Resolute) — on WSL2, cloud VM, or bare metal
- `curl` and `sudo` access

### One-command setup

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aziz0220/dotfiles/main/install)
```

The script will:

1. Install Ansible and dependencies
2. Clone this repository
3. Prompt for your vault password
4. Run the full provisioning playbook
5. Restore your dotfiles, secrets, packages, tools, and repos

### One-command WSL lifecycle

Run these commands from **Windows PowerShell**, not from inside Ubuntu. The default `up` command installs Ubuntu 26.04 as the separately named `Ubuntu-26.04-Dotfiles` WSL2 instance when absent, creates the `aziz0220` Linux user, prompts securely for its password and the encrypted vault passphrase, provisions and validates the machine, then launches it. An existing distro named `Ubuntu-26.04` is not changed:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/aziz0220/dotfiles/main/scripts/wsl.ps1')))
```

Create a separately named instance or choose its storage location:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/aziz0220/dotfiles/main/scripts/wsl.ps1'))) up Ubuntu-26.04 -Name Work-26 -InstallLocation 'D:\WSL\Work-26'
```

Remove an instance with one command. Without `-Force`, teardown requires typing the exact distro name because `wsl --unregister` permanently deletes its filesystem:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/aziz0220/dotfiles/main/scripts/wsl.ps1'))) down Ubuntu-26.04
```

With no `-Name`, both `up` and `down` resolve the managed instance name to `Ubuntu-26.04-Dotfiles`; the existing `Ubuntu-26.04` distro is never selected. For a custom instance, pass the same explicit `-Name` to both actions.

If the requested release is temporarily absent from `wsl --list --online` but a distro with that source name is already registered, `up` creates the managed instance from a temporary `wsl --export`/`wsl --import` snapshot instead. The source remains registered and is never unregistered. The temporary archive is deleted after import; cloning can require additional time and disk space. Without `-InstallLocation`, imported instances use `%LOCALAPPDATA%\WSL\<Name>`.

Export a safety backup before removal:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/aziz0220/dotfiles/main/scripts/wsl.ps1'))) down Ubuntu-26.04 -ExportPath "$HOME\Backups\Ubuntu-26.04-Dotfiles.tar"
```

The `down` action does **not** capture, commit, or push machine state. That update workflow remains intentionally separate; use `-ExportPath` when unpushed data may exist.

### Authenticated access

The bootstrap repository is public. Private repositories use the SSH keys restored from the encrypted vault before cloning, so no separate GitHub token is required when those keys have access. `GITHUB_TOKEN` remains optional for authenticated access to the bootstrap repository and is passed ephemerally rather than saved in the Git remote.

### Manual setup

```bash
git clone https://github.com/aziz0220/dotfiles.git
cd dotfiles
export SETUP_SECRETS_PASSWORD='your-vault-password'
./ansible-run
```

## Usage

### Run everything

```bash
./ansible-run
# or with an explicit tag set
./ansible-run all
```

### Run specific components

```bash
./ansible-run core        # system packages, locale, timezone, services
./ansible-run dotfiles    # shell config, gitconfig, SSH config
./ansible-run home        # user home restore from bootstrap bundle
./ansible-run node        # Node.js via nvm + npm global packages
./ansible-run ssh         # SSH key setup
```

### Decrypt / encrypt secrets bundle

```bash
export SETUP_SECRETS_PASSWORD='your-vault-password'

# Decrypt into .bootstrap/home
./scripts/decrypt_home_bundle.sh

# Encrypt back from .bootstrap/home
./scripts/encrypt_home_bundle.sh
```

### Capture current machine state

```bash
# Capture dotfiles and configs
ALLOW_REPO_OVERWRITE=1 ./scripts/capture_bootstrap_home.sh

# Capture snap/npm/pipx/cargo/gem/flatpak state
# (vars/installed-packages.yml and vars/pip-user.yml are hand-curated and are
# NOT captured -- see "Apt packages" under Configuration Reference.)
ALLOW_REPO_OVERWRITE=1 ./scripts/capture_software_inventory.sh
```

Both refuse to run without `ALLOW_REPO_OVERWRITE=1`. They rewrite the repository *from* this
machine, which is the opposite of the normal direction — the repo is the source of truth. Re-encrypt
and commit afterwards, or the capture stays local:

```bash
./scripts/encrypt_home_bundle.sh && git add -A && git commit
```

### Validate setup

```bash
./scripts/validate_setup.sh
```

Checks package, repository, custom-tool, login-shell, and home parity, then flags local work that
exists only on this machine — uncommitted changes, unpushed commits, and repositories with no
remote. Run it before rebuilding or discarding a machine.

### Sync AI sessions across machines

Claude Code and Codex keep their conversations in local JSONL transcripts, so a session started on
one machine is invisible on another. `dotfiles sessions` carries them through a small **private**
git repository (`aziz0220/ai-sessions`), cloned to `~/.ai-sessions` — the repo is transport and
backup, not a workspace.

```bash
./bin/dotfiles sessions push     # publish this machine's recent sessions
./bin/dotfiles sessions pull     # bring other machines' sessions here (backs up files it replaces)
./bin/dotfiles sessions status   # ahead/behind, last sync, size
```

Then resume with the agent's own command (`claude --continue` / `claude --resume`, `codex resume`).
What syncs: `~/.claude/projects/**/*.jsonl`, `~/.claude/CLAUDE.md`, `~/.codex/sessions/**/*.jsonl`
modified within the last `AI_SESSIONS_DAYS` (default 30) days. Sessions older than the window, or
larger than `AI_SESSIONS_MAX_MB` (default 50), stay local. Credentials, tokens, caches, and
telemetry are **never** synced.

Two things to know:

- **Logins do not travel.** OAuth tokens rotate, so each machine runs `claude` → `/login` once.
  After that, pulled sessions resume normally. The `pull` command reminds you.
- **Push before you leave, pull when you arrive.** `pull` never silently discards a local file — it
  backs up anything it replaces under `~/.ai-sessions-backups/<timestamp>/`. Keeping the same
  username on every machine (`aziz0220`) is what lets Claude match project paths so `--continue`
  finds the synced sessions.

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                      dotfiles                            │
│                                                          │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐ │
│  │  install      │   │  ansible-run │   │  Makefile     │ │
│  │  (bootstrap)  │──▶│  (orchestrate)│  │  (dev tasks)   │ │
│  └──────────────┘   └──────┬───────┘   └──────────────┘ │
│                             │                             │
│                    ┌────────▼────────┐                   │
│                    │   local.yml      │                   │
│                    │  (main playbook) │                   │
│                    └────────┬────────┘                   │
│                             │                             │
│         ┌───────────────────┼───────────────────┐        │
│         ▼                   ▼                   ▼        │
│  ┌────────────┐    ┌──────────────┐    ┌────────────┐   │
│  │system_setup│    │  app_stack   │    │home_restore │   │
│  │ - apt srcs │    │ - packages   │    │ - user/groups│  │
│  │ - locale   │    │ - snap       │    │ - dotfiles  │   │
│  │ - timezone │    │ - npm/pip  │    │ - SSH/GPG   │   │
│  │ - services │    │ - runtimes  │    │ - repos     │   │
│  └────────────┘    │ - cargo/gem │    └────────────┘   │
│                    │ - flatpak   │                       │
│                    └──────────────┘                      │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Data Sources                                     │   │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │   │
│  │  │ vars/*.yml│  │ vault/   │  │ vars/repos.yml │  │   │
│  │  │(curated + │  │(encrypted│  │(tooling clones │  │   │
│  │  │ captured) │  │ secrets) │  │ only)           │  │   │
│  │  └──────────┘  └──────────┘  └────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### What gets restored, and what does not

One exception worth knowing before you rely on it: **Claude Code's login does not
survive the trip.** Its OAuth refresh token rotates on every use, so the copy in
the vault is superseded the moment the capturing machine refreshes — the restored
file is intact but the session is dead, and the restored machine reports
`OAuth session expired and could not be refreshed`. Run `claude` and `/login`
once per machine. Every other captured credential here uses a non-rotating token
and does carry over.

| Restored | Not restored |
|---|---|
| Shell config, `.gitconfig`, editor and terminal config | **Your own project repositories** |
| SSH keys, GPG keys, AWS/kube config, CLI auth tokens | Anything uncommitted or unpushed, anywhere |
| apt / snap / npm / pipx / cargo / gem / flatpak packages | Repos with no remote |
| Node runtimes (nvm), custom CLI tools | Caches, build output, `node_modules` |
| Tooling clones only: `.oh-my-zsh`, `.nvm`, nvim plugins | |

`vars/repos.yml` holds **tooling clones only** — things like oh-my-zsh and nvim plugins that
happen to be distributed as git repos. Cloning, pushing, and pulling your own work is yours to
manage: this repo cannot know about commits that exist on one machine and nowhere else, so it
does not pretend to back them up.

Before rebuilding or discarding a machine, check what only exists there:

```bash
./scripts/validate_setup.sh   # the "Local Work Safety" section flags unpushed and remote-less repos
```

**Restoring never silently overwrites.** Every file replaced by a home restore is copied first to
`~/.dotfiles-backup/<timestamp>/`, mirroring its original path. If a restore clobbers a local edit
you had not captured, the previous version is there.

### Reaching your machines from each other

Provisioning enables `tailscaled` and turns on **Tailscale SSH**, so every machine
you provision can reach every other one:

```bash
ssh <you>@<machine-name>      # MagicDNS name, from any machine on the tailnet
```

No port forwarding, no public SSH port, and no `authorized_keys` to copy around —
the tailnet identity *is* the SSH credential, and access is revoked from the
Tailscale admin console rather than by editing every machine. Ordinary SSH on the
wire, so Termius and friends work unchanged. The `openssh-server` you already have
stays as a local-network fallback for when Tailscale is logged out or down.

Joining a tailnet needs a credential; there is no way around that. Either is fine:

```bash
sudo tailscale up --ssh                                  # once per machine, approve in a browser
printf '%s\n' tskey-auth-... > ~/.config/tailscale/authkey   # or make it unattended
TS_AUTHKEY=tskey-auth-... ./ansible-run tailnet          # or pass it for a single run
```

An auth key from <https://login.tailscale.com/admin/settings/keys> lets a new
machine join with no interaction. Keys expire after at most 90 days, so an
unattended setup needs the key refreshed occasionally; when it lapses,
provisioning prints the manual command instead of failing.

Nothing here aborts a run. A machine that cannot reach the tailnet is still a
working machine, so every task reports and continues.

### Staying in sync

`ansible-run` fetches before it provisions and warns when your clone is behind `origin`, so you do
not restore an old vault over a newer machine. It warns rather than pulls — pulling would swap the
playbook out mid-run. Update deliberately:

```bash
git pull --ff-only && ./ansible-run
DOTFILES_SKIP_FETCH=1 ./ansible-run   # offline, skip the check
```

### Secrets architecture

```
┌──────────────────────┐      SETUP_SECRETS_PASSWORD     ┌──────────────────────┐
│  vault/              │     (environment variable)       │  .bootstrap/home/    │
│  home-secrets.tar.gz │ ────────────decrypt────────────▶ │  (gitignored)        │
│  .aes256             │                                  │  - .ssh/             │
│  (committed,         │ ◀───────────encrypt───────────── │  - .gnupg/           │
│   encrypted)         │                                  │  - .aws/             │
└──────────────────────┘                                  │  - .kube/            │
                                                          │  - .zshrc            │
                                                          │  - .gitconfig        │
                                                          │  - ...               │
                                                          └──────────────────────┘
```

## Project Structure

```
.
├── install                 # One-command bootstrap entry point
├── bin/dotfiles            # Workstation bootstrap runner
├── ansible-run             # Playbook orchestrator
├── Makefile                # Common development tasks
├── justfile                # Modern task runner (macOS/Linux)
├── local.yml               # Main playbook
├── site.yml                # Site-wide playbook (multi-host)
├── inventory.ini           # Ansible inventory (localhost)
├── ansible.cfg             # Ansible configuration
├── AGENTS.md               # AI-assisted development guide
│
├── roles/
│   ├── system_setup/       # System-level configuration
│   │   ├── tasks/main.yml
│   │   ├── files/          # Static files (apt sources, wsl.conf)
│   │   ├── templates/      # Jinja2 templates
│   │   └── handlers/
│   ├── app_stack/          # Application packages and tools
│   │   └── tasks/main.yml
│   └── home_restore/       # User home restoration
│       └── tasks/main.yml
│
├── tasks/                  # Composable task includes
│   ├── core-setup.yml
│   ├── dotfiles.yml
│   ├── node-setup.yml
│   └── ssh.yml
│
├── vars/                   # Declarative machine state (version controlled)
│   ├── user-profile.yml    # User metadata
│   ├── groups.yml          # System groups
│   ├── system-locale.yml   # Locale and timezone
│   ├── installed-packages.yml  # Curated apt essentials (~40 packages)
│   ├── snap-list.yml       # Snap packages
│   ├── npm-global.yml      # Global npm packages
│   ├── pipx.yml            # pipx-installed tools
│   ├── pip-user.yml        # Hand-curated pip user-site tools (uv, jupyter, playwright, git-filter-repo, kaggle)
│   ├── cargo.yml           # Cargo-installed tools
│   ├── gem.yml             # Ruby gems
│   ├── flatpak.yml         # Flatpak applications
│   ├── repos.yml           # Tooling clones only (oh-my-zsh, nvim plugins) — not your projects
│   ├── runtimes.yml        # Node versions (nvm) — SDKMAN is no longer used
│   ├── custom-tools.yml    # One-off tool installers (claude, opencode, junie, copilot, kimi, kiro, …)
│   └── systemd-enabled-services.yml
│
├── vault/
│   ├── .gitkeep
│   └── home-secrets.tar.gz.aes256  # Encrypted secrets bundle
│
├── scripts/
│   ├── capture_bootstrap_home.sh      # Capture dotfiles/configs
│   ├── capture_software_inventory.sh  # Capture package state
│   ├── decrypt_home_bundle.sh         # Decrypt secrets vault
│   ├── encrypt_home_bundle.sh         # Encrypt secrets vault
│   ├── rotate_vault_password.sh       # Change vault password
│   ├── validate_setup.sh              # Post-provision validation
│   ├── session_sync.sh                # Sync AI sessions via private git repo
│   ├── docker_sandbox.sh              # Throwaway container from the real vault
│   ├── install_stripe.sh              # Stripe CLI installer (custom_tools)
│   └── wsl.ps1                        # Windows-side WSL up/down lifecycle
│
├── test/
│   ├── ansible_run_test.sh            # Orchestrator regression test
│   ├── home_state_test.sh             # Capture portability regression test
│   ├── docker_test.sh                 # Docker home-restore regression
│   ├── wsl_lifecycle_test.ps1         # Mocked PowerShell lifecycle tests
│   └── wsl_lifecycle_test.sh          # Cross-platform test launcher
│
├── .editorconfig                      # Editor consistency
├── .pre-commit-config.yaml            # Pre-commit hook definitions
├── .ansible-lint                      # Ansible-lint configuration
├── .yamllint                          # YAMLlint configuration
│
└── .github/
    ├── workflows/ci.yml               # CI pipeline (22.04, 24.04, and 26.04)
    ├── dependabot.yml
    ├── ISSUE_TEMPLATE/
    └── PULL_REQUEST_TEMPLATE.md
```

## Configuration Reference

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SETUP_SECRETS_PASSWORD` | For decryption | Passphrase for the encrypted secrets vault |
| `BOOTSTRAP_HOME_DIR` | No | Override bootstrap home directory (default: `.bootstrap/home`) |
| `ENCRYPTED_HOME_BUNDLE` | No | Override vault file path |
| `ANSIBLE_PLAYBOOK_FILE` | No | Override playbook file (default: `local.yml`) |
| `GITHUB_TOKEN` | No | Optional ephemeral authentication for the bootstrap repository |
| `DOTFILES_SKIP_FETCH` | No | Set to `1` to skip the "your clone is behind origin" check (offline runs) |
| `INCLUDE_PRIVATE` | No | Set to `false` to capture without SSH/GPG/cloud credentials |
| `ALLOW_REPO_OVERWRITE` | For capture | Must be `1`; guards the scripts that overwrite the repo from the host |
| `OLDPASS` | Vault rotation | Current vault password (when using `rotate_vault_password.sh`) |
| `NEWPASS` | Vault rotation | New vault password (when using `rotate_vault_password.sh`) |
| `AI_SESSIONS_REPO` | No | Session-sync repo URL (default `https://github.com/aziz0220/ai-sessions.git`) |
| `AI_SESSIONS_DIR` | No | Session-sync clone directory (default `~/.ai-sessions`) |
| `AI_SESSIONS_DAYS` | No | Sync sessions modified within this many days (default `30`; `0` = all) |
| `AI_SESSIONS_MAX_MB` | No | Skip sessions larger than this many MB (default `50`) |

### Tags

| Tag | Components |
|-----|-----------|
| `all` (default) | Everything |
| `core` | APT sources, locale, timezone, systemd services |
| `dotfiles` | Shell config, `.gitconfig`, `.ssh/config` |
| `node` | nvm + Node.js + npm global packages |
| `ssh` | SSH key deployment |
| `home` | Full home restore from bootstrap bundle |

## Development

### Prerequisites for development

```bash
make setup
make setup-precommit   # optional: automatic linting on commit
```

### Test provisioning locally with Docker

```bash
make docker-test              # Ubuntu 24.04
make docker-test DISTRO=22.04 # Ubuntu 22.04
make docker-test DISTRO=26.04 # Ubuntu 26.04
```

This builds a clean container and verifies home restoration over Ubuntu's pre-existing skeleton files. Full 22.04 and 24.04 provisioning remains covered by CI.

### Rotate vault password

```bash
bash scripts/rotate_vault_password.sh
```

### Lint and validate

```bash
make lint        # yamllint + shellcheck + ansible-lint
make validate    # YAML syntax + required files
make check       # lint + validate
make wsl-test    # mocked WSL up/down lifecycle
```

### CI locally

```bash
make ci          # Run the same checks as GitHub Actions
```

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for the security policy.

- Secrets are **never** stored in plaintext in the repository
- The bootstrap home directory (`.bootstrap/home/`) is gitignored
- Only the encrypted vault (`vault/home-secrets.tar.gz.aes256`) is committed
- Vault uses AES-256-CBC with PBKDF2 key derivation
- Rotate the vault password at any time: `bash scripts/rotate_vault_password.sh`
- CI runs full provisioning on **Ubuntu 22.04 and 24.04**, plus an **Ubuntu 26.04** home-restore regression

## License

[MIT](LICENSE) &copy; Aziz Ben Amor
