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
INVENTORY="${SOLTI_INVENTORY:-${ANSIBLE_DIR}/inventory/localhost.yml}"
TEMP_DIR="${ANSIBLE_DIR}/tmp"
HOST=""
YES_FLAG=false
EXPLICIT_INVENTORY=false

# Ensure temp directory exists with strict permissions
mkdir -p "${TEMP_DIR}"
chmod 700 "${TEMP_DIR}"

# Cleanup function to be called on exit or interrupt
cleanup() {
    # Only remove if not in failure state (unless explicitly told to)
    if [[ $? -eq 0 ]]; then
        if [[ -f "${TEMP_PLAYBOOK}" ]]; then
            rm -f "${TEMP_PLAYBOOK}"
        fi
    fi
}
trap cleanup EXIT INT TERM

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
    "mongodb"
    "obsidian"
    "conduit"
    "dns_service"
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
    echo "Usage: $(basename $0) [-i INVENTORY] [-h HOST] [-y] <service> <action> [options]"
    echo ""
    echo "Options:"
    echo "  -i INVENTORY     - Path to inventory file (default: \$SOLTI_INVENTORY or inventory.yml)"
    echo "  -h HOST          - Target specific host from inventory (default: uses all hosts in service group)"
    echo "  -y, --yes        - Skip safety prompts (for automation)"
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
    echo "  $(basename $0) -y redis deploy                              # Skip prompts"
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

# Determine target context (localhost vs remote)
get_target_context() {
    local inventory="$1"
    local host="$2"

    # If host is explicitly podma, always remote
    if [[ "$host" == "podma" ]]; then
        echo "remote"
        return 0
    fi

    # If inventory contains padma, always remote
    if [[ "$inventory" =~ padma ]]; then
        echo "remote"
        return 0
    fi

    # If host is firefly or inventory is localhost, consider localhost
    if [[ "$host" == "firefly" ]] || [[ "$inventory" =~ localhost ]]; then
        echo "localhost"
        return 0
    fi

    # Default to remote for safety
    echo "remote"
}

# Safety prompt function
prompt_user() {
    local context="$1"
    local service="$2"
    local action="$3"
    local inventory="$4"
    local host="$5"

    # Skip if --yes flag set
    if [[ "$YES_FLAG" == "true" ]]; then
        return 0
    fi

    # Skip if both inventory and host explicitly specified and they match
    # (User knows what they're doing - explicit configuration)
    if [[ "$EXPLICIT_INVENTORY" == "true" ]] && [[ -n "$host" ]]; then
        # Check if inventory and host are consistent
        if [[ "$inventory" =~ podma ]] && [[ "$host" == "podma" ]]; then
            return 0  # Explicit podma inventory + podma host = no warning
        elif [[ "$inventory" =~ localhost ]] && [[ "$host" == "firefly" ]]; then
            return 0  # Explicit localhost inventory + firefly host = no warning
        fi
    fi

    # Determine target display name
    local target_name="${host:-all hosts in ${service}_svc}"
    if [[ -z "$host" ]]; then
        if [[ "$inventory" =~ localhost ]]; then
            target_name="firefly"
        elif [[ "$inventory" =~ padma ]]; then
            target_name="podma"
        fi
    fi

    # Prompt based on context
    case "$context" in
        localhost)
            # Soft prompt only if explicit targeting (and not skipped above)
            if [[ "$EXPLICIT_INVENTORY" == "true" ]] || [[ -n "$host" ]]; then
                echo ""
                read -p "Installing ${service} locally on ${target_name}. Continue? [Y/n] " response
                if [[ "$response" =~ ^[Nn] ]]; then
                    echo "Operation cancelled by user"
                    return 1
                fi
            fi
            ;;
        remote)
            # Hard prompt for remote (only if not already skipped above)
            echo ""
            echo "⚠ WARNING: Remote deployment detected"
            echo "Target: ${target_name}"
            echo "Service: ${service}"
            echo "Action: ${action}"
            read -p "Proceed? [y/N] " response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                echo "Operation cancelled by user"
                return 1
            fi
            ;;
    esac

    return 0
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
    elif [[ "$service" == "dns_service" ]]; then
        # DNS service always runs on localhost and scans entire inventory
        host_param="hosts: localhost"
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
  vars:
    ${service}_state: ${state}
  roles:
    - role: ${service}
EOF

    echo "Generated playbook for ${service} ${action}"
}

# Parse command line arguments
while getopts "i:h:y" opt; do
    case ${opt} in
        i)
            INVENTORY=$OPTARG
            EXPLICIT_INVENTORY=true
            ;;
        h)
            HOST=$OPTARG
            ;;
        y)
            YES_FLAG=true
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

# Generate the playbook with strict permissions
(umask 077 && generate_playbook "$SERVICE" "$ACTION")

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

# Determine target context and prompt user
TARGET_CONTEXT=$(get_target_context "$INVENTORY" "$HOST")
if ! prompt_user "$TARGET_CONTEXT" "$SERVICE" "$ACTION" "$INVENTORY" "$HOST"; then
    exit 0
fi

# Determine if we need sudo for this action
# Prepare/deploy may need sudo for SELinux/sysctl
# Remove may need sudo if deleting data (container subuid ownership)
SUDO_FLAG=""
TARGET_HOST="${HOST:-${SERVICE}_svc}"
NEED_SUDO=false

if [[ "$ACTION" == "prepare" ]] || [[ "$ACTION" == "deploy" ]]; then
    # Prepare/deploy may need sudo for SELinux/sysctl operations
    NEED_SUDO=true
elif [[ "$ACTION" == "remove" ]]; then
    # Check if service has delete_data=true (may need sudo for container-owned files)
    # Check both inventory variables and environment variable
    if [[ "${DELETE_DATA}" == "true" ]] || ansible-inventory -i "${INVENTORY}" --host "${TARGET_HOST}" --yaml 2>/dev/null | grep -q "delete_data.*true"; then
        NEED_SUDO=true
    fi
fi

# Only test sudo capability if we actually need it
if [[ "$NEED_SUDO" == "true" ]]; then
    # Check if --become-password-file is already provided in extra args
    BECOME_PASS_FILE_PROVIDED=false
    for arg in "${EXTRA_ARGS[@]}"; do
        if [[ "$arg" == "--become-password-file"* ]] || [[ "$arg" == "--become-pass-file"* ]]; then
            BECOME_PASS_FILE_PROVIDED=true
            break
        fi
    done

    if [[ "$BECOME_PASS_FILE_PROVIDED" == "true" ]]; then
        echo "✓ Using --become-password-file from arguments"
        SUDO_FLAG="--become"
    else
        echo "Testing sudo capability on target..."
        if ansible -i "${INVENTORY}" "${TARGET_HOST}" -m shell -a "sudo -n true" &>/dev/null; then
            echo "✓ NOPASSWD detected - sudo password not required"
            SUDO_FLAG="--become"
        else
            echo "✗ Password required - will prompt for sudo password"
            SUDO_FLAG="--become --ask-become-pass"
        fi
    fi
else
    echo "✓ Action '${ACTION}' does not require sudo privileges"
    SUDO_FLAG=""
fi

# Matrix logging: deployment start (OPTIONAL - don't break on failure)
if [[ -x "${ANSIBLE_DIR}/bin/matrix-log.py" ]]; then
    "${ANSIBLE_DIR}/bin/matrix-log.py" message \
        "Starting ${ACTION}: ${SERVICE} on ${HOST:-all}" \
        --level info 2>/dev/null || true
fi

# Track execution time
START_TIME=$(date +%s)

# Execute playbook (sudo flags determined above based on action requirements)
echo "Executing: ansible-playbook ${SUDO_FLAG} -i ${INVENTORY} ${TEMP_PLAYBOOK} ${EXTRA_ARGS[*]}"
ansible-playbook ${SUDO_FLAG} -i "${INVENTORY}" "${TEMP_PLAYBOOK}" "${EXTRA_ARGS[@]}"

# Check execution status
EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Matrix logging: deployment complete (OPTIONAL - don't break on failure)
if [[ -x "${ANSIBLE_DIR}/bin/matrix-log.py" ]]; then
    if [[ ${EXIT_CODE} -eq 0 ]]; then
        STATUS="success"
    else
        STATUS="failure"
    fi

    "${ANSIBLE_DIR}/bin/matrix-log.py" deployment \
        "${SERVICE}" "${HOST:-all}" "${STATUS}" \
        --duration "${DURATION}" \
        --details action="${ACTION}" state="${STATE_MAP[$ACTION]}" 2>/dev/null || true
fi
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