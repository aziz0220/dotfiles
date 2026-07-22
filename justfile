# ---------------------------------------------------------------------------
# dotfiles — Modern task runner (https://github.com/casey/just)
# ---------------------------------------------------------------------------
set positional-arguments := true

# Show this help
default:
    @just --list

# Install development dependencies
setup:
    sudo apt-get update -qq
    sudo apt-get install -y -qq shellcheck ansible yamllint rsync
    pip install ansible-lint
    @echo "✓ Dev dependencies installed"

# Run all linters
lint:
    #!/usr/bin/env bash
    echo "→ YAML lint"; yamllint --strict .
    echo "→ Shellcheck"; shellcheck scripts/*.sh test/*.sh install ansible-run bin/dotfiles
    echo "→ Ansible syntax check"; ansible-playbook --syntax-check -i inventory.ini local.yml
    echo "→ Ansible lint"; PYTHONWARNINGS=ignore::DeprecationWarning ansible-lint local.yml
    echo "→ Regression tests"; bash test/ansible_run_test.sh
    echo "✓ All lints passed"

# Validate repo structure and data  
validate:
    #!/usr/bin/env bash
    echo "→ YAML vars syntax"
    errors=0
    for f in vars/*.yml; do
        python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null \
            && echo "  OK: $f" \
            || { echo "  INVALID: $f"; errors=$((errors+1)); }
    done
    exit $errors
    echo "✓ All validations passed"

# Run lint + validate
check: lint validate

# Provision this machine
provision:
    bash ansible-run

# Provision with specific tag (e.g., just provision-tag dotfiles)
provision-tag tag:
    bash ansible-run {{tag}}

# Test provisioning in Docker (default: ubuntu 24.04)
docker-test version="24.04":
    bash test/docker_test.sh {{version}}

# Run full CI pipeline locally
ci: check

# Rotate vault password
rotate-vault:
    bash scripts/rotate_vault_password.sh

# Set up pre-commit hooks
setup-precommit:
    pip install pre-commit 2>/dev/null || true
    pre-commit install
    @echo "✓ Pre-commit hooks installed"

# Clean up generated artifacts
clean:
    rm -rf .bootstrap/home/* .bootstrap/*.tar .bootstrap/*.tmp .bootstrap/*.dec
    @echo "✓ Cleaned bootstrap artifacts"
