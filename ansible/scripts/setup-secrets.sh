#!/bin/bash
# Setup secrets for Turing RK1 Ansible deployment
# Usage: ./scripts/setup-secrets.sh
#
# Creates secrets/server.yml from template with generated K3s token.
# Edit the file to set BMC credentials and other passwords.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$ANSIBLE_DIR/secrets"
ENV="${1:-server}"

echo "Setting up secrets for environment: $ENV"
echo ""

# Check if secrets file already exists
if [[ -f "$SECRETS_DIR/$ENV.yml" ]]; then
    echo "Secrets file already exists: $SECRETS_DIR/$ENV.yml"
    read -p "Overwrite? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Copy from example
if [[ -f "$SECRETS_DIR/$ENV.yml.example" ]]; then
    cp "$SECRETS_DIR/$ENV.yml.example" "$SECRETS_DIR/$ENV.yml"
    chmod 600 "$SECRETS_DIR/$ENV.yml"
    echo "Created: $SECRETS_DIR/$ENV.yml"
else
    echo "Error: Example file not found: $SECRETS_DIR/$ENV.yml.example"
    exit 1
fi

# Generate K3s cluster token
echo ""
echo "Generating K3s cluster token..."
K3S_TOKEN=$(openssl rand -hex 32)

# Update the secrets file with generated token
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "s/CHANGE_ME_GENERATE_WITH_openssl_rand_hex_32/$K3S_TOKEN/" "$SECRETS_DIR/$ENV.yml"
else
    sed -i "s/CHANGE_ME_GENERATE_WITH_openssl_rand_hex_32/$K3S_TOKEN/" "$SECRETS_DIR/$ENV.yml"
fi

echo "K3s token generated and saved."
echo ""
echo "Next steps:"
echo "1. Edit $SECRETS_DIR/$ENV.yml to set your passwords"
echo "2. Run playbooks with: ansible-playbook -i inventories/$ENV/hosts.yml playbooks/site.yml"
echo ""
echo "Optional: Encrypt secrets with Ansible Vault:"
echo "  ansible-vault encrypt $SECRETS_DIR/$ENV.yml"
echo ""
