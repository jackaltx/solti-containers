#!/bin/bash
# prepare-solti-env.sh - Setup Python virtual environment for solti-containers testing

set -e  # Exit on error

# Source lab secrets if available (for LAB_TLD, etc.)
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

# Install from requirements.txt if available, otherwise install manually
if [ -f requirements.txt ]; then
    echo "Installing packages from requirements.txt..."
    pip install -r requirements.txt
else
    echo "No requirements.txt found, installing packages manually..."
    # Core packages
    pip install ansible-core
    pip install molecule
    pip install molecule-plugins[podman]
    pip install ansible-lint
    pip install proxmoxer
    pip install requests
    pip install dnspython
    pip install jmespath
    pip install yq

    echo ""
    echo "HINT: Generate requirements.txt with:"
    echo "  source $VENV_DIR/bin/activate && pip freeze > requirements.txt"
fi

# Ansible collections
echo "Installing Ansible collections..."
ansible-galaxy collection install community.general:10.0.1

echo ""
echo "=========================================="
echo "Environment ready at $PWD"
echo "Activate with: source $VENV_DIR/bin/activate"
echo "Test with: ./run-podman-tests.sh"
echo ""
echo "DNS Automation (requires LINODE_TOKEN):"
echo "  ./update-dns.sh                 # Update hardcoded service list"
echo "  ./update-dns-auto.sh podma      # Auto-detect from inventory"
echo "  ./update-dns-auto.sh -h         # Show help"
echo "=========================================="
