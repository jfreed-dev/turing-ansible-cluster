# Turing RK1 Ansible Cluster - Development Makefile

.PHONY: help lint test syntax-check install-deps clean release \
        pre-commit pre-commit-install pre-commit-update \
        vault-init vault-edit vault-view vault-encrypt vault-decrypt \
        molecule molecule-test molecule-verify molecule-destroy

# Default target
help:
	@echo "Turing RK1 Ansible Cluster"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development:"
	@echo "  install-deps       Install development dependencies"
	@echo "  lint               Run ansible-lint and yamllint"
	@echo "  syntax-check       Syntax check all playbooks"
	@echo "  test               Run all checks (lint + syntax)"
	@echo "  clean              Clean cache files"
	@echo ""
	@echo "Pre-commit:"
	@echo "  pre-commit-install Install pre-commit hooks"
	@echo "  pre-commit         Run pre-commit on all files"
	@echo "  pre-commit-update  Update pre-commit hook versions"
	@echo ""
	@echo "Vault:"
	@echo "  vault-init         Initialize vault password file"
	@echo "  vault-edit         Edit encrypted secrets"
	@echo "  vault-view         View encrypted secrets"
	@echo "  vault-encrypt      Encrypt secrets file"
	@echo "  vault-decrypt      Decrypt secrets file (caution!)"
	@echo ""
	@echo "Molecule (role testing):"
	@echo "  molecule           Run full molecule test (ROLE=k3s_server)"
	@echo "  molecule-test      Run molecule converge only"
	@echo "  molecule-verify    Run molecule verify only"
	@echo "  molecule-destroy   Destroy molecule instances"
	@echo ""
	@echo "Release:"
	@echo "  release            Create a new release (VERSION=v1.0.0)"
	@echo ""

# Install development dependencies
install-deps:
	pip install ansible ansible-lint yamllint pre-commit shellcheck-py molecule molecule-docker

# Run linting
lint:
	@echo "Running yamllint..."
	yamllint -c .yamllint ansible/ || true
	@echo ""
	@echo "Running ansible-lint..."
	cd ansible && ansible-lint

# Syntax check all playbooks
syntax-check:
	@echo "Checking playbook syntax..."
	@cd ansible && for playbook in playbooks/*.yml; do \
		echo "  Checking $$playbook..."; \
		ansible-playbook --syntax-check "$$playbook" || exit 1; \
	done
	@echo "All playbooks passed syntax check."

# Run all tests
test: lint syntax-check
	@echo ""
	@echo "All checks passed!"

# Clean cache files
clean:
	rm -rf ansible/.ansible/tmp
	rm -rf ansible/.cache
	find . -type f -name "*.retry" -delete
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# Create a new release
release:
ifndef VERSION
	$(error VERSION is required. Usage: make release VERSION=v1.0.0)
endif
	@echo "Creating release $(VERSION)..."
	@if git rev-parse $(VERSION) >/dev/null 2>&1; then \
		echo "Error: Tag $(VERSION) already exists"; \
		exit 1; \
	fi
	git tag -a $(VERSION) -m "Release $(VERSION)"
	@echo "Tag $(VERSION) created. Push with: git push origin $(VERSION)"

# ==================== Pre-commit ====================

# Install pre-commit hooks
pre-commit-install:
	pre-commit install
	pre-commit install --hook-type commit-msg
	@echo "Pre-commit hooks installed successfully"

# Run pre-commit on all files
pre-commit:
	pre-commit run --all-files

# Update pre-commit hook versions
pre-commit-update:
	pre-commit autoupdate
	@echo "Pre-commit hooks updated. Review changes and commit."

# ==================== Ansible Vault ====================

VAULT_FILE := ansible/secrets/server.yml
VAULT_PASS := ansible/.vault_pass

# Initialize vault password file
vault-init:
	@if [ -f $(VAULT_PASS) ]; then \
		echo "Error: $(VAULT_PASS) already exists"; \
		echo "Remove it first if you want to regenerate"; \
		exit 1; \
	fi
	@openssl rand -base64 32 > $(VAULT_PASS)
	@chmod 600 $(VAULT_PASS)
	@echo "Vault password created at $(VAULT_PASS)"
	@echo "IMPORTANT: Back up this password securely!"

# Edit encrypted secrets
vault-edit:
	@if [ ! -f $(VAULT_PASS) ]; then \
		echo "Error: $(VAULT_PASS) not found. Run 'make vault-init' first"; \
		exit 1; \
	fi
	@if [ ! -f $(VAULT_FILE) ]; then \
		echo "Creating new encrypted secrets file..."; \
		cp ansible/secrets/server.yml.example $(VAULT_FILE); \
		cd ansible && ansible-vault encrypt secrets/server.yml; \
	fi
	cd ansible && ansible-vault edit secrets/server.yml

# View encrypted secrets (read-only)
vault-view:
	@if [ ! -f $(VAULT_FILE) ]; then \
		echo "Error: $(VAULT_FILE) not found"; \
		exit 1; \
	fi
	cd ansible && ansible-vault view secrets/server.yml

# Encrypt existing plaintext secrets file
vault-encrypt:
	@if [ ! -f $(VAULT_FILE) ]; then \
		echo "Error: $(VAULT_FILE) not found"; \
		exit 1; \
	fi
	@if head -1 $(VAULT_FILE) | grep -q '^\$$ANSIBLE_VAULT'; then \
		echo "File is already encrypted"; \
		exit 1; \
	fi
	cd ansible && ansible-vault encrypt secrets/server.yml
	@echo "Secrets file encrypted successfully"

# Decrypt secrets file (use with caution!)
vault-decrypt:
	@if [ ! -f $(VAULT_FILE) ]; then \
		echo "Error: $(VAULT_FILE) not found"; \
		exit 1; \
	fi
	@echo "WARNING: This will decrypt secrets to plaintext!"
	@read -p "Are you sure? (y/N) " confirm && [ "$$confirm" = "y" ] || exit 1
	cd ansible && ansible-vault decrypt secrets/server.yml
	@echo "Secrets file decrypted. Remember to re-encrypt before committing!"

# ==================== Molecule (Role Testing) ====================

# Default role for molecule tests
ROLE ?= k3s_server

# Run full molecule test cycle
molecule:
	@echo "Running molecule tests for role: $(ROLE)"
	cd ansible/roles/$(ROLE) && molecule test

# Run molecule converge only (create + converge, no destroy)
molecule-test:
	@echo "Running molecule converge for role: $(ROLE)"
	cd ansible/roles/$(ROLE) && molecule converge

# Run molecule verify only (assumes instance exists)
molecule-verify:
	@echo "Running molecule verify for role: $(ROLE)"
	cd ansible/roles/$(ROLE) && molecule verify

# Destroy molecule instances
molecule-destroy:
	@echo "Destroying molecule instances for role: $(ROLE)"
	cd ansible/roles/$(ROLE) && molecule destroy

# Run molecule tests for all roles with molecule configs
molecule-all:
	@echo "Running molecule tests for all configured roles..."
	@for role in ansible/roles/*/molecule; do \
		role_name=$$(dirname $$role | xargs basename); \
		echo "Testing role: $$role_name"; \
		cd ansible/roles/$$role_name && molecule test || exit 1; \
		cd - > /dev/null; \
	done
	@echo "All molecule tests passed!"
