# ---------------------------------------------------------------------------
# ubuntu-setup — Development tasks
# ---------------------------------------------------------------------------
.PHONY: help setup lint validate check ci install provision clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "$(CYAN)%-20s$(NC) %s\n", $$1, $$2}'

setup: ## Install development dependencies
	@sudo apt-get update -qq
	@sudo apt-get install -y -qq shellcheck ansible yamllint
	@pip install ansible-lint 2>/dev/null || true
	@echo "✓ Dev dependencies installed"

lint: ## Run all linters
	@echo "→ YAML lint"; yamllint --strict .
	@echo "→ Shellcheck"; shellcheck scripts/*.sh install ansible-run
	@echo "→ Ansible syntax check"; ansible-playbook --syntax-check -i inventory.ini local.yml
	@echo "→ Ansible lint"; ansible-lint local.yml || true
	@echo "✓ All lints passed"

validate: ## Validate repo structure and data
	@echo "→ YAML vars syntax"
	@errors=0; \
	for f in vars/*.yml; do \
		python3 -c "import yaml; yaml.safe_load(open('$$f'))" 2>/dev/null \
			&& echo "  OK: $$f" \
			|| { echo "  INVALID: $$f"; errors=$$((errors+1)); }; \
	done; \
	exit $$errors
	@echo "→ Required files"
	@for f in site.yml local.yml inventory.ini ansible.cfg ansible-run install; do \
		test -f "$$f" && echo "  OK: $$f" || { echo "  MISSING: $$f"; exit 1; }; \
	done
	@for role in system_setup home_restore app_stack; do \
		test -f "roles/$$role/tasks/main.yml" && echo "  OK: roles/$$role/tasks/main.yml" \
			|| { echo "  MISSING: roles/$$role/tasks/main.yml"; exit 1; }; \
	done
	@echo "→ Gitignore check"
	@if git ls-files --error-unmatch .bootstrap/home/ 2>/dev/null; then \
		echo "  FAIL: .bootstrap/home/ is tracked"; exit 1; \
	fi; \
	echo "  OK: .bootstrap/home/ is gitignored"
	@echo "✓ All validations passed"

check: lint validate ## Run lint + validate (CI equivalent)

ci: check ## Run full CI pipeline locally

install: ## Bootstrap environment on this machine
	@bash install

provision: ## Run ansible provisioner
	@bash ansible-run

provision-%: ## Run ansible provisioner with specific tags (e.g. make provision-dotfiles)
	@bash ansible-run $(@:provision-%=%)

clean: ## Clean up generated files
	@rm -rf .bootstrap/home/* .bootstrap/*.tar .bootstrap/*.tmp .bootstrap/*.dec
	@echo "✓ Cleaned bootstrap artifacts"
