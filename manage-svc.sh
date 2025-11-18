#!/bin/bash
#
# manage-svc - Manage services using dynamically generated Ansible playbooks
#
# Usage: manage-svc [-i INVENTORY] [-h HOST] <service> <action>
#
# Example:
#   manage-svc elasticsearch prepare
#   manage-svc -h firefly hashivault deploy
#   manage-svc -i inventory/podma.yml redis deploy
#   manage-svc redis remove

# Exit on error
set -e

# Configuration
ANSIBLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SOLTI_INVENTORY:-${ANSIBLE_DIR}/inventory.yml}"
TEMP_DIR="${ANSIBLE_DIR}/tmp"
HOST=""

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
    "wazuh"       # DEPRECATED - only 'remove' action supported
    "grafana"
    "gitea"
    "influxdb3"
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
    echo "Usage: $(basename $0) [-i INVENTORY] [-h HOST] <service> <action> [options]"
    echo ""
    echo "Options:"
    echo "  -i INVENTORY     - Path to inventory file (default: \$SOLTI_INVENTORY or inventory.yml)"
    echo "  -h HOST          - Target specific host from inventory (default: uses all hosts in service group)"
    echo "  -e VAR=VALUE     - Set extra variables (can be used multiple times)"
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
    echo "  $(basename $0) -h firefly hashivault deploy"
    echo "  $(basename $0) -i inventory/podma.yml redis deploy"
    echo "  $(basename $0) redis remove"
    echo "  $(basename $0) mattermost deploy -e mattermost_version=8.1.0"
    echo "  $(basename $0) -h firefly elasticsearch prepare -e elasticsearch_memory=2g"
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
    local host_param=""

    # Add host specification if provided
    if [[ -n "$HOST" ]]; then
        host_param="hosts: $HOST"
    else
        host_param="hosts: ${service}_svc"
    fi

    # Create playbook directly with the proper substitutions
    cat > "$TEMP_PLAYBOOK" << EOF
---
# Dynamically generated playbook
# Works for: prepare, deploy, remove
- name: Manage ${service} Service
  $host_param
  become: true
  vars:
    ${service}_state: ${state}
  roles:
    - role: ${service}
EOF

    echo "Generated playbook for ${service} ${action}"
}

# Parse command line arguments
while getopts "i:h:" opt; do
    case ${opt} in
        i)
            INVENTORY=$OPTARG
            ;;
        h)
            HOST=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done

# Shift past the options
shift $((OPTIND - 1))

# Validate arguments
if [[ $# -lt 2 ]]; then
    echo "Error: Incorrect number of arguments"
    usage
fi

# Extract arguments
SERVICE="$1"
ACTION="$2"
shift 2

# Remaining arguments are extra vars
EXTRA_ARGS=("$@")

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

# Validate inventory file exists
if [[ ! -f "$INVENTORY" ]]; then
    echo "Error: Inventory file not found: $INVENTORY"
    exit 1
fi

# Generate timestamp for files
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TEMP_PLAYBOOK="${TEMP_DIR}/${SERVICE}-${ACTION}-${TIMESTAMP}.yml"

# Generate the playbook
generate_playbook "$SERVICE" "$ACTION"

# Display execution info
echo "Managing service: $SERVICE"
echo "Action: $ACTION"
echo "Inventory: $INVENTORY"
if [[ -n "$HOST" ]]; then
    echo "Target host: $HOST"
else
    echo "Target hosts: ${SERVICE}_svc (from inventory)"
fi
echo "Using generated playbook: $TEMP_PLAYBOOK"
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    echo "Extra arguments: ${EXTRA_ARGS[*]}"
fi
echo ""

# Display playbook content
echo "Playbook content:"
echo "----------------"
cat "${TEMP_PLAYBOOK}"
echo "----------------"
echo ""

# Ask for confirmation
read -p "Execute this playbook? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "Operation cancelled"
    exit 0
fi

# Always use sudo for all states
echo "Executing with sudo privileges: ansible-playbook -K -i ${INVENTORY} ${TEMP_PLAYBOOK} ${EXTRA_ARGS[*]}"
ansible-playbook -K -i "${INVENTORY}" "${TEMP_PLAYBOOK}" "${EXTRA_ARGS[@]}"

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