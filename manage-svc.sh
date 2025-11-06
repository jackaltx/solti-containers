#!/bin/bash
#
# manage-svc - Manage services using dynamically generated Ansible playbooks
#
# Usage: manage-svc <service> <action>
#
# Example:
#   manage-svc elasticsearch prepare
#   manage-svc hashivault deploy
#   manage-svc redis remove

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
)

# Supported actions
SUPPORTED_ACTIONS=(
    "prepare"
    "deploy"
    "remove"
)

# Map actions to state values
declare -A STATE_MAP
STATE_MAP["prepare"]="prepare"
STATE_MAP["deploy"]="present"
STATE_MAP["remove"]="absent"

# Display usage information
usage() {
    echo "Usage: $(basename $0) <service> <action>"
    echo ""
    echo "Services:"
    for svc in "${SUPPORTED_SERVICES[@]}"; do
        echo "  - $svc"
    done
    echo ""
    echo "Actions:"
    for action in "${SUPPORTED_ACTIONS[@]}"; do
        echo "  - $action"
    done
    echo ""
    echo "Examples:"
    echo "  $(basename $0) elasticsearch prepare"
    echo "  $(basename $0) hashivault deploy"
    echo "  $(basename $0) redis remove"
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

# Check if an action is supported
is_action_supported() {
    local action="$1"
    for act in "${SUPPORTED_ACTIONS[@]}"; do
        if [[ "$act" == "$action" ]]; then
            return 0
        fi
    done
    return 1
}

# Generate playbook from template
generate_playbook() {
    local service="$1"
    local action="$2"
    local state="${STATE_MAP[$action]}"
    
    # Create playbook directly with the proper substitutions
    cat > "$TEMP_PLAYBOOK" << EOF
---
# Works for: prepare, deploy, remove
- name: Manage ${service} Service
  hosts: ${service}_svc
  vars:
    ${service}_state: ${state}
  roles:
    - role: ${service}
EOF
    
    echo "Generated playbook for ${service} ${action}"
}

# Validate arguments
if [[ $# -ne 2 ]]; then
    echo "Error: Incorrect number of arguments"
    usage
fi

# Extract arguments
SERVICE="$1"
ACTION="$2"

# Validate service
if ! is_service_supported "$SERVICE"; then
    echo "Error: Unsupported service '$SERVICE'"
    usage
fi

# Validate action
if ! is_action_supported "$ACTION"; then
    echo "Error: Unsupported action '$ACTION'"
    usage
fi

# Generate timestamp for files
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TEMP_PLAYBOOK="${TEMP_DIR}/${SERVICE}-${ACTION}-${TIMESTAMP}.yml"

# Generate the playbook
generate_playbook "$SERVICE" "$ACTION"

# Display execution info
echo "Managing service: $SERVICE"
echo "Action: $ACTION"
echo "Using generated playbook: $TEMP_PLAYBOOK"
echo ""

# Display playbook content
echo "Playbook content:"
echo "----------------"
cat "${TEMP_PLAYBOOK}"
echo "----------------"
echo ""

# Always use sudo for all states
echo "Executing with sudo privileges: ansible-playbook -K -i ${INVENTORY} ${TEMP_PLAYBOOK}"
ansible-playbook -K -i "${INVENTORY}" "${TEMP_PLAYBOOK}"

# Check execution status
EXIT_CODE=$?
if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo ""
    echo "Success: ${SERVICE} ${ACTION} completed successfully"
    
    # Remove the temporary playbook on success
    echo "Cleaning up generated playbook"
    rm -f "${TEMP_PLAYBOOK}"
    
    exit 0
else
    echo ""
    echo "Error: ${SERVICE} ${ACTION} failed with exit code ${EXIT_CODE}"
    echo "Generated playbook preserved for debugging: ${TEMP_PLAYBOOK}"
    exit 1
fi