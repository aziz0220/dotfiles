<div align="center">
  <h1>Dotfiles</h1>
  <p><strong>One command to restore your entire development environment — dotfiles, secrets, packages, tools, and repos.</strong></p>

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

Provision any Ubuntu machine — WSL2, cloud VM, bare metal, or VM — with your complete development environment in a single command. Your dotfiles, SSH keys, GPG keys, cloud credentials, packages, CLI tools, runtimes, and repos are restored from an encrypted, version-controlled source of truth.

## Features

- **One-command bootstrap** — `curl -fsSL https://raw.githubusercontent.com/aziz0220/dotfiles/main/install | bash`
- **Encrypted secrets** — SSH keys, GPG keys, AWS credentials, kube config stored in AES-256-CBC + PBKDF2 vault
- **Declarative machine state** — packages, snaps, npm/pipx/cargo/gem packages, repos, runtimes all captured as version-controlled YAML
- **Idempotent** — safe to run multiple times; only installs what's missing
- **Tagged execution** — run only what you need: `./ansible-run dotfiles`, `./ansible-run node`, etc.
- **Auto-detecting** — detects username, home, UID/GID, shell at runtime
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

# Capture installed packages, snap, npm/pipx/cargo/gem/flatpak
ALLOW_REPO_OVERWRITE=1 ./scripts/capture_software_inventory.sh
```

### Validate setup

```bash
./scripts/validate_setup.sh
```

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
│  │ - timezone │    │ - npm/pipx  │    │ - SSH/GPG   │   │
│  │ - services │    │ - runtimes  │    │ - repos     │   │
│  └────────────┘    │ - cargo/gem │    └────────────┘   │
│                    │ - flatpak   │                       │
│                    └──────────────┘                      │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Data Sources                                     │   │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │   │
│  │  │ vars/*.yml│  │ vault/   │  │ vars/repos.yml │  │   │
│  │  │(captured │  │(encrypted│  │(git repo list)  │  │   │
│  │  │ state)   │  │ secrets) │  │                 │  │   │
│  │  └──────────┘  └──────────┘  └────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
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
│   ├── installed-packages.yml  # apt packages
│   ├── snap-list.yml       # Snap packages
│   ├── npm-global.yml      # Global npm packages
│   ├── pipx.yml            # pipx-installed tools
│   ├── cargo.yml           # Cargo-installed tools
│   ├── gem.yml             # Ruby gems
│   ├── flatpak.yml         # Flatpak applications
│   ├── repos.yml           # Git repositories to clone
│   ├── runtimes.yml        # Node/SDKMAN runtime versions
│   ├── custom-tools.yml    # One-off tool installers
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
│   └── validate_setup.sh              # Post-provision validation
│
├── test/
│   ├── ansible_run_test.sh            # Orchestrator regression test
│   └── docker_test.sh                 # Docker home-restore regression
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
| `OLDPASS` | Vault rotation | Current vault password (when using `rotate_vault_password.sh`) |
| `NEWPASS` | Vault rotation | New vault password (when using `rotate_vault_password.sh`) |

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
