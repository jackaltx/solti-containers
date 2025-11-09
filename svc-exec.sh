#!/bin/bash
#
# svc-exec - Execute specific tasks for services using dynamically generated Ansible playbooks
#
# Usage: svc-exec [-K] <service> [entry]
#
# Example:
#   svc-exec elasticsearch verify     # No sudo prompt
#   svc-exec -K redis configure       # With sudo prompt
#   svc-exec mattermost               # Default entry point, no sudo

# Exit on error
set -e

# Configuration
ANSIBLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${ANSIBLE_DIR}/inventory.yml"
TEMP_DIR="${ANSIBLE_DIR}/tmp"

# Ensure temp directory exists
mkdir -p "${TEMP_DIR}"

# Supported services
SUPPORTED_SERVICES=(
    "elasticsearch"
    "hashivault"
    "redis"
    "mattermost"
    "traefik"
    "minio"
    "wazuh"
    "grafana"
    "gitea"
    "influxdb3"
)

# Default entry point if not specified
DEFAULT_ENTRY="verify"

# Initialize variables
USE_SUDO=false
SERVICE=""
ENTRY=""

# Display usage information
usage() {
    echo "Usage: $(basename $0) [-K] <service> [entry]"
    echo ""
    echo "Options:"
    echo "  -K      - Prompt for sudo password (needed for some operations)"
    echo ""
    echo "Parameters:"
    echo "  service - The service to manage"
    echo "  entry   - The entry point task (default: verify)"
    echo ""
    echo "Services:"
    for svc in "${SUPPORTED_SERVICES[@]}"; do
        echo "  - $svc"
    done
    echo ""
    echo "Examples:"
    echo "  $(basename $0) elasticsearch verify     # No sudo prompt"
    echo "  $(basename $0) -K redis configure       # With sudo prompt"
    echo "  $(basename $0) mattermost               # Default entry, no sudo"
    exit 1
}

# Check if a service is supported
is_service_supported() {
    local service="$1"
    for svc in "${SUPPORTED_SERVICES[@]}"; do
        if [[ "$svc" == "$service" ]]; then
            return 0
        fi
    done
    return 1
}

# Generate task execution playbook 
generate_exec_playbook() {
    local service="$1"
    local entry="$2"
    
    # Create playbook directly with proper substitutions
    cat > "$TEMP_PLAYBOOK" << EOF
---
# Dynamic execution playbook
- name: Execute ${entry} for ${service} Service
  hosts: ${service}_svc
  tasks:
    - name: Include roles tasks
      ansible.builtin.include_role:
        name: ${service}
        tasks_from: ${entry}
        vars_from: main
EOF
    
    echo "Generated ${entry} playbook for ${service}"
}

# Parse command line options
while getopts "K" opt; do
    case ${opt} in
        K)
            USE_SUDO=true
            ;;
        *)
            usage
            ;;
    esac
done

# Shift past the options
shift $((OPTIND - 1))

# Validate remaining arguments
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Error: Incorrect number of arguments"
    usage
fi

# Extract parameters
SERVICE="$1"
ENTRY="${2:-$DEFAULT_ENTRY}"  # Use default if not provided

# Validate service
if ! is_service_supported "$SERVICE"; then
    echo "Error: Unsupported service '$SERVICE'"
    usage
fi

# Generate timestamp for files
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TEMP_PLAYBOOK="${TEMP_DIR}/${SERVICE}-${ENTRY}-${TIMESTAMP}.yml"

# Generate the playbook
generate_exec_playbook "$SERVICE" "$ENTRY"

# Display execution info
echo "Executing task: ${ENTRY} for service: ${SERVICE}"
echo "Using generated playbook: $TEMP_PLAYBOOK"
if $USE_SUDO; then
    echo "Using sudo: Yes (will prompt for password)"
else
    echo "Using sudo: No"
fi
echo ""

# Display playbook content
echo "Playbook content:"
echo "----------------"
cat "${TEMP_PLAYBOOK}"
echo "----------------"
echo ""

# Execute the playbook with or without sudo prompt
if $USE_SUDO; then
    echo "Executing with sudo privileges: ansible-playbook -K -i ${INVENTORY} ${TEMP_PLAYBOOK}"
    ansible-playbook -K -i "${INVENTORY}" "${TEMP_PLAYBOOK}"
else
    echo "Executing: ansible-playbook -i ${INVENTORY} ${TEMP_PLAYBOOK}"
    ansible-playbook -i "${INVENTORY}" "${TEMP_PLAYBOOK}"
fi

# Check execution status
EXIT_CODE=$?
if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo ""
    echo "Success: ${ENTRY} for ${SERVICE} completed successfully"
    
    # Remove the temporary playbook on success
    echo "Cleaning up generated playbook"
    rm -f "${TEMP_PLAYBOOK}"
    
    exit 0
else
    echo ""
    echo "Error: ${ENTRY} for ${SERVICE} failed with exit code ${EXIT_CODE}"
    echo "Generated playbook preserved for debugging: ${TEMP_PLAYBOOK}"
    exit 1
fi