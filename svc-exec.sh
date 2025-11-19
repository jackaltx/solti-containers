#!/bin/bash
#
# svc-exec - Execute specific tasks for services using dynamically generated Ansible playbooks
#
# Usage: svc-exec [-i INVENTORY] [-h HOST] [-K] <service> [entry] [options]
#
# Example:
#   svc-exec elasticsearch verify     # No sudo prompt
#   svc-exec -K redis configure       # With sudo prompt
#   svc-exec -h firefly mattermost    # Run on specific host
#   svc-exec -i inventory/podma.yml redis verify  # Use specific inventory
#   svc-exec mattermost               # Default entry point, no sudo
#   svc-exec redis verify -e redis_password=newpass

# Exit on error
set -e

# Configuration
ANSIBLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SOLTI_INVENTORY:-${ANSIBLE_DIR}/inventory.yml}"
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
HOST=""
SERVICE=""
ENTRY=""

# Display usage information
usage() {
    echo "Usage: $(basename $0) [-i INVENTORY] [-h HOST] [-K] <service> [entry] [options]"
    echo ""
    echo "Options:"
    echo "  -i INVENTORY     - Path to inventory file (default: \$SOLTI_INVENTORY or inventory.yml)"
    echo "  -h HOST          - Target specific host from inventory (default: uses all hosts in service group)"
    echo "  -K               - Prompt for sudo password (needed for some operations)"
    echo ""
    echo "Parameters:"
    echo "  service          - The service to manage"
    echo "  entry            - The entry point task (default: verify)"
    echo "  options          - Extra variables (-e VAR=VALUE)"
    echo ""
    echo "Services:"
    for svc in "${SUPPORTED_SERVICES[@]}"; do
        echo "  - $svc"
    done
    echo ""
    echo "Examples:"
    echo "  $(basename $0) elasticsearch verify     # No sudo prompt"
    echo "  $(basename $0) -K redis configure       # With sudo prompt"
    echo "  $(basename $0) -h firefly mattermost    # Run on specific host"
    echo "  $(basename $0) -i inventory/podma.yml redis verify  # Use specific inventory"
    echo "  $(basename $0) mattermost               # Default entry, no sudo"
    echo "  $(basename $0) redis verify -e redis_password=newpass"
    echo "  $(basename $0) -h firefly -K elasticsearch configure -e elasticsearch_memory=4g"
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
    local host_param=""

    # Add host specification if provided
    if [[ -n "$HOST" ]]; then
        host_param="hosts: $HOST"
    else
        host_param="hosts: ${service}_svc"
    fi

    # Create playbook directly with proper substitutions
    cat > "$TEMP_PLAYBOOK" << EOF
---
# Dynamic execution playbook
- name: Execute ${entry} for ${service} Service
  $host_param
  tasks:
    - name: Include roles tasks
      ansible.builtin.include_role:
        name: ${service}
        tasks_from: ${entry}
EOF

    echo "Generated ${entry} playbook for ${service}"
}

# Parse command line options
while getopts "i:h:K" opt; do
    case ${opt} in
        i)
            INVENTORY=$OPTARG
            ;;
        h)
            HOST=$OPTARG
            ;;
        K)
            USE_SUDO=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
        *)
            usage
            ;;
    esac
done

# Shift past the options
shift $((OPTIND - 1))

# Validate remaining arguments
if [[ $# -lt 1 ]]; then
    echo "Error: Service name required"
    usage
fi

# Extract parameters
SERVICE="$1"
shift

# Extract entry point (default if not provided or if it starts with -)
if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
    ENTRY="$1"
    shift
else
    ENTRY="$DEFAULT_ENTRY"
fi

# Capture any remaining arguments as extra args
EXTRA_ARGS=("$@")

# Validate service
if ! is_service_supported "$SERVICE"; then
    echo "Error: Unsupported service '$SERVICE'"
    usage
fi

# Validate inventory file exists
if [[ ! -f "$INVENTORY" ]]; then
    echo "Error: Inventory file not found: $INVENTORY"
    exit 1
fi

# Generate timestamp for files
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TEMP_PLAYBOOK="${TEMP_DIR}/${SERVICE}-${ENTRY}-${TIMESTAMP}.yml"

# Generate the playbook
generate_exec_playbook "$SERVICE" "$ENTRY"

# Display execution info
echo "Executing task: ${ENTRY} for service: ${SERVICE}"
echo "Inventory: $INVENTORY"
if [[ -n "$HOST" ]]; then
    echo "Target host: $HOST"
else
    echo "Target hosts: ${SERVICE}_svc (from inventory)"
fi
echo "Using generated playbook: $TEMP_PLAYBOOK"
if $USE_SUDO; then
    echo "Using sudo: Yes (will prompt for password)"
else
    echo "Using sudo: No"
fi
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

# Execute the playbook with or without sudo prompt
if $USE_SUDO; then
    echo "Executing with sudo privileges: ansible-playbook -K -i ${INVENTORY} ${TEMP_PLAYBOOK} ${EXTRA_ARGS[*]}"
    ansible-playbook -K -i "${INVENTORY}" "${TEMP_PLAYBOOK}" "${EXTRA_ARGS[@]}"
else
    echo "Executing: ansible-playbook -i ${INVENTORY} ${TEMP_PLAYBOOK} ${EXTRA_ARGS[*]}"
    ansible-playbook -i "${INVENTORY}" "${TEMP_PLAYBOOK}" "${EXTRA_ARGS[@]}"
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