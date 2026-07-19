# Contributing

Thanks for your interest in contributing! This project aims to be a rock-solid, portable workstation bootstrap. Every contribution helps.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/aziz0220/ubuntu-setup/issues)
2. If not, open a new issue with:
   - A clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - Your OS version and Ansible version

### Suggesting Features

Open an issue with the `enhancement` label describing:
- The problem you're solving
- Your proposed solution
- Alternative approaches considered

### Pull Requests

1. **Fork** the repository
2. **Create a branch**: `git checkout -b feature/my-feature`
3. **Make your changes**
4. **Run checks**: `make check` (lint + validate)
5. **Test** your changes in CI or locally
6. **Commit** with a clear message
7. **Push** to your fork and open a PR

### PR Guidelines

- Keep changes focused — one feature/fix per PR
- Update documentation (README, comments) as needed
- Ensure CI passes on your branch
- Follow existing code style and conventions
- Add or update tests if applicable

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/ubuntu-setup.git
cd ubuntu-setup

# Install dev dependencies
make setup

# (Optional) Install pre-commit hooks for automatic linting
make setup-precommit

# Run checks
make check
```

## Code Style

- **Shell scripts**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html). Run `shellcheck` on all scripts.
- **YAML**: Use `yamllint --strict`. No trailing spaces, 2-space indentation.
- **Ansible**: Follow [Ansible best practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html). Use `ansible-lint`.
- **Commit messages**: Use [Conventional Commits](https://www.conventionalcommits.org/):
  - `feat: add support for macOS`
  - `fix: resolve nvm install race condition`
  - `docs: update README with new badges`
  - `chore: update dependencies`

## Adding a New Package or Tool

1. Add the package to the appropriate `vars/*.yml` file
2. If it needs a custom installer, add it to `vars/custom-tools.yml`
3. Run `make validate` to verify YAML syntax
4. Open a PR

## Project Structure

```
vars/                    # Declarative machine state
├── installed-packages.yml   # APT packages
├── npm-global.yml           # npm global packages
├── pipx.yml                 # pipx tools
├── cargo.yml                # Cargo tools
├── gem.yml                  # Ruby gems
├── flatpak.yml              # Flatpak apps
├── snap-list.yml            # Snap packages
├── repos.yml                # Git repos
├── custom-tools.yml         # Custom installers
├── runtimes.yml             # Runtime versions
├── groups.yml               # System groups
├── system-locale.yml        # Locale/timezone
└── user-profile.yml         # User metadata
```

## Testing with Docker

Test provisioning against a clean Ubuntu container locally:

```bash
# Test Ubuntu 24.04 (default)
make docker-test

# Test Ubuntu 22.04
make docker-test DISTRO=22.04
```

This builds a Docker image, runs the full playbook, and verifies installed components — same as CI but on your machine.

## Vault Password Rotation

If you need to change the vault password:

```bash
bash scripts/rotate_vault_password.sh
```

Then update the GitHub secret:
```bash
echo 'your-new-password' | gh secret set SETUP_SECRETS_PASSWORD --repo YOUR_USERNAME/ubuntu-setup --body @-
```

## Security

See [SECURITY.md](SECURITY.md).

## Questions?

Open a [Discussion](https://github.com/aziz0220/ubuntu-setup/discussions) or ask in a PR comment.
