# Turing RK1 Ansible Cluster - Development Makefile

.PHONY: help lint test syntax-check install-deps clean release

# Default target
help:
	@echo "Turing RK1 Ansible Cluster"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  install-deps   Install development dependencies"
	@echo "  lint           Run ansible-lint and yamllint"
	@echo "  syntax-check   Syntax check all playbooks"
	@echo "  test           Run all checks (lint + syntax)"
	@echo "  clean          Clean cache files"
	@echo "  release        Create a new release (usage: make release VERSION=v1.0.0)"
	@echo ""

# Install development dependencies
install-deps:
	pip install ansible ansible-lint yamllint

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
