# Contributing

Contributions are welcome! This document outlines how to contribute to this project.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Install dependencies: `make install-deps`

## Before Submitting

Run the validation checks:

```bash
# Run all checks
make test

# Or individually:
make lint          # YAML and Ansible linting
make syntax-check  # Playbook syntax validation
```

## Pull Request Guidelines

- Keep changes focused and atomic
- Update documentation if adding new features
- Ensure all CI checks pass
- Test playbooks with `--check` mode before submitting

## Code Style

- Follow existing patterns in the codebase
- Use 2-space indentation for YAML
- Keep lines under 120 characters
- Use descriptive task names in Ansible

## Secrets and Sensitive Data

- **Never** commit secrets, passwords, or private keys
- Use `*.example` files for templates
- Add sensitive patterns to `.gitignore`

## Testing Changes

```bash
# Syntax check only
ansible-playbook --syntax-check playbooks/site.yml

# Dry run against a specific node
ansible-playbook -i inventories/server/hosts.yml playbooks/bootstrap.yml --check --limit node1
```

## Questions?

Open an issue for questions or discussion about potential changes.
