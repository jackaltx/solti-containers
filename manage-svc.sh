#!/bin/bash
#
# manage-svc - Manage services using templated Ansible playbooks
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
LOG_DIR="${ANSIBLE_DIR}/logs"
TEMP_DIR="${ANSIBLE_DIR}/tmp"
TEMPLATE_DIR="${ANSIBLE_DIR}/templates"

# Template files
STANDARD_TEMPLATE="${TEMPLATE_DIR}/service-mgr.yml.j2"

# Ensure log and temp directories exist
mkdir -p "${LOG_DIR}" "${TEMP_DIR}"

# Supported services
SUPPORTED_SERVICES=(
    "elasticsearch"
    "hashivault"
    "redis"
    "mattermost"
    "traefik"
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
    
    # Check if template exists
    if [[ ! -f "$STANDARD_TEMPLATE" ]]; then
        echo "Error: Template file not found: $STANDARD_TEMPLATE"
        echo "Please create it with the following content:"
        echo "---"
        echo "# Works for: prepare, deploy, remove"
        echo "- name: Manage {{ service_role }} Service"
        echo "  hosts: {{ service_hosts }}"
        echo "  vars:"
        echo "    {{ service_role }}_state: {{ service_state }}"
        echo "  roles:"
        echo "    - role: {{ service_role }}"
        exit 1
    fi

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

# Generate timestamp for files and logs
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/${SERVICE}-${ACTION}-${TIMESTAMP}.log"
TEMP_PLAYBOOK="${TEMP_DIR}/${SERVICE}-${ACTION}-${TIMESTAMP}.yml"

# Generate the playbook
generate_playbook "$SERVICE" "$ACTION"

# Display execution info
echo "Managing service: $SERVICE"
echo "Action: $ACTION"
echo "Using generated playbook: $TEMP_PLAYBOOK"
echo "Log file: $LOG_FILE"
echo ""

# Display playbook content
echo "Playbook content:"
echo "----------------"
cat "${TEMP_PLAYBOOK}"
echo "----------------"
echo ""

# Do the work!
echo "Executing with sudo privileges: ansible-playbook -K -i ${INVENTORY} ${TEMP_PLAYBOOK}"
ansible-playbook -K -i "${INVENTORY}" "${TEMP_PLAYBOOK}" 2>&1 | tee "${LOG_FILE}"


# Check execution status
EXIT_CODE=${PIPESTATUS[0]}
if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo ""
    echo "Success: ${SERVICE} ${ACTION} completed successfully"
    echo "Log saved to: ${LOG_FILE}"
    exit 0
else
    echo ""
    echo "Error: ${SERVICE} ${ACTION} failed with exit code ${EXIT_CODE}"
    echo "Check log for details: ${LOG_FILE}"
    exit 1
fi
