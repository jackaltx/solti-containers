#!/bin/bash
# prepare-solti-env.sh - Setup Python virtual environment for solti-monitoring testing

# Source lab secrets if available (for LAB_DOMAIN, etc.)
if [ -f ~/.secrets/LabProvision ]; then
    echo "Sourcing lab environment variables from ~/.secrets/LabProvision"
    source ~/.secrets/LabProvision
fi

VENV_DIR="solti-venv"

# Create fresh virtual environment
echo "Creating virtual environment: $VENV_DIR"
python3 -m venv --system-site-packages "$VENV_DIR"

# Activate it
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Core packages
echo "Installing core packages..."
pip install ansible-core  # Let pip install compatible version for Python 3.14
pip install molecule
pip install molecule-plugins[podman]  # For podman driver
pip install ansible-lint
pip install proxmoxer                 # For proxmox testing
pip install requests
pip install dnspython
pip install jmespath
pip install yq                        # For inventory parsing in DNS automation

# Ansible collections
echo "Installing Ansible collections..."
ansible-galaxy collection install community.general:10.0.1

echo ""
echo "=========================================="
echo "Environment ready!"
echo "Activate with: source $VENV_DIR/bin/activate"
echo "Test with: ./run-podman-tests.sh"
echo ""
echo "DNS Automation (requires LINODE_TOKEN):"
echo "  ./update-dns.sh                 # Update hardcoded service list"
echo "  ./update-dns-auto.sh podma      # Auto-detect from inventory"
echo "  ./update-dns-auto.sh -h         # Show help"
echo "=========================================="
