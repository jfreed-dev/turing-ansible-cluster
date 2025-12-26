# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Use [GitHub Security Advisories](../../security/advisories/new) to report privately
3. Or contact the maintainer directly

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You can expect an initial response within 48 hours.

## Security Considerations

This repository contains infrastructure-as-code for deploying Kubernetes clusters. When using this code:

- **Never commit secrets** - Use the provided `*.example` files as templates
- **Review all playbooks** before running against production systems
- **Use strong passwords** - Replace all example passwords with secure values
- **Restrict network access** - The default configuration uses private IP ranges
- **Keep dependencies updated** - Regularly update Ansible collections and Helm charts
