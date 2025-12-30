# Ansible Vault Setup

This document explains how to configure Ansible Vault for secure secrets management in this repository.

## Overview

Ansible Vault encrypts sensitive data (passwords, tokens, keys) so they can be safely stored in version control. This repository uses vault for:

- K3s cluster tokens
- BMC credentials
- Grafana admin passwords
- SSH keys and other secrets

## Quick Start

### 1. Create Vault Password File

```bash
cd ansible

# Generate a strong random password
openssl rand -base64 32 > .vault_pass

# Secure the file permissions
chmod 600 .vault_pass
```

> **Important:** Never commit `.vault_pass` to git. It's already in `.gitignore`.

### 2. Create Encrypted Secrets File

```bash
# Option A: Create new encrypted file from template
cp secrets/server.yml.example secrets/server.yml
ansible-vault encrypt secrets/server.yml

# Option B: Create new encrypted file interactively
ansible-vault create secrets/server.yml
```

### 3. Edit Encrypted Secrets

```bash
# Edit the encrypted file (opens in $EDITOR)
ansible-vault edit secrets/server.yml

# Or decrypt, edit, re-encrypt
ansible-vault decrypt secrets/server.yml
# ... make changes ...
ansible-vault encrypt secrets/server.yml
```

## Secrets File Structure

The `secrets/server.yml` file should contain:

```yaml
---
# SSH Configuration
ansible_ssh_private_key_file: ~/.ssh/id_rsa

# K3s cluster token (generate with: openssl rand -hex 32)
k3s_cluster_token: "your-secure-token-here"

# Turing Pi BMC credentials
tpi_bmc_host: "10.10.88.70"
tpi_bmc_username: root
tpi_bmc_password: "your-bmc-password"

# Grafana admin password
grafana_admin_password: "your-grafana-password"
```

## Using Vault with Playbooks

Once configured, playbooks automatically decrypt secrets:

```bash
# Vault password is read from .vault_pass automatically
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml

# Or specify password file explicitly
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml \
  --vault-password-file .vault_pass

# Or prompt for password (no file needed)
ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml \
  --ask-vault-pass
```

## Vault Commands Reference

| Command | Description |
|---------|-------------|
| `ansible-vault create FILE` | Create new encrypted file |
| `ansible-vault edit FILE` | Edit encrypted file in place |
| `ansible-vault view FILE` | View encrypted file contents |
| `ansible-vault encrypt FILE` | Encrypt existing plaintext file |
| `ansible-vault decrypt FILE` | Decrypt file to plaintext |
| `ansible-vault rekey FILE` | Change encryption password |
| `ansible-vault encrypt_string` | Encrypt a single string |

## Encrypting Individual Variables

For inline encrypted variables in playbooks:

```bash
# Encrypt a string
ansible-vault encrypt_string 'my-secret-value' --name 'my_variable'

# Output (paste into playbook):
# my_variable: !vault |
#   $ANSIBLE_VAULT;1.1;AES256
#   ...encrypted content...
```

## Multiple Vault Passwords

For different environments (dev/staging/prod):

```bash
# Create environment-specific password files
echo "dev-password" > .vault_pass_dev
echo "prod-password" > .vault_pass_prod

# Encrypt with vault ID
ansible-vault encrypt --vault-id dev@.vault_pass_dev secrets/dev.yml
ansible-vault encrypt --vault-id prod@.vault_pass_prod secrets/prod.yml

# Run with multiple vault IDs
ansible-playbook site.yml \
  --vault-id dev@.vault_pass_dev \
  --vault-id prod@.vault_pass_prod
```

## CI/CD Integration

For GitHub Actions, store the vault password as a secret:

```yaml
# .github/workflows/deploy.yml
- name: Create vault password file
  run: echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > ansible/.vault_pass

- name: Run playbook
  run: ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml
```

## Security Best Practices

1. **Strong passwords**: Use `openssl rand -base64 32` for vault passwords
2. **Separate passwords**: Use different vault passwords for dev/prod
3. **Rotate regularly**: Rekey vault files periodically with `ansible-vault rekey`
4. **Limit access**: Only share vault passwords with authorized team members
5. **Backup passwords**: Store vault passwords in a secure password manager
6. **Git hooks**: Use pre-commit to prevent committing unencrypted secrets

## Troubleshooting

### "Decryption failed" error

```bash
# Verify the password file exists and is readable
cat ansible/.vault_pass

# Check file permissions
ls -la ansible/.vault_pass

# Try with explicit password prompt
ansible-playbook site.yml --ask-vault-pass
```

### "No vault secrets found" error

Ensure vault_password_file path in `ansible.cfg` is correct:

```ini
[defaults]
vault_password_file = .vault_pass  # Relative to ansible/ directory
```

### Migrate from plaintext to vault

```bash
# If you have existing plaintext secrets
cd ansible

# Encrypt in place
ansible-vault encrypt secrets/server.yml

# Verify encryption
head -1 secrets/server.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256
```
