#!/usr/bin/env bash
#
# svc-manage - Unified service management
#
# Replaces manage-svc.sh (state management) and svc-exec.sh (task execution)
# in a single script. The old scripts are preserved and unchanged.
#
# Usage: svc-manage [-i INVENTORY] [-h HOST] [-y] [-K] <service> <command> [options]
#
# State commands (prepare/deploy/remove) run the full role via main.yml and
# always use --become (password probed automatically).
#
# Task commands (verify/configure/backup/<any>) run tasks_from inside the role
# and never use sudo unless -K is given.
#
# Examples:
#   source ~/.secrets/LabProvision && ./svc-manage.sh redis prepare
#   source ~/.secrets/LabProvision && ./svc-manage.sh redis deploy
#   ./svc-manage.sh redis verify
#   ./svc-manage.sh redis check_upgrade
#   ./svc-manage.sh -K redis configure
#   ./svc-manage.sh hashivault unseal
#   ./svc-manage.sh -h podma -i inventory/podma.yml redis deploy
#   DELETE_DATA=true ./svc-manage.sh redis remove

set -e

ANSIBLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SOLTI_INVENTORY:-}"
TEMP_DIR="${ANSIBLE_DIR}/tmp"
HOST=""
YES_FLAG=false
EXPLICIT_INVENTORY=false
USE_SUDO=false

# Internal state mapping — roles use present/absent/prepare
declare -A STATE_MAP
STATE_MAP["prepare"]="prepare"
STATE_MAP["deploy"]="present"
STATE_MAP["remove"]="absent"

SUPPORTED_STATES=("prepare" "deploy" "remove")

SUPPORTED_SERVICES=(
    "elasticsearch"
    "hashivault"
    "redis"
    "mattermost"
    "traefik"
    "minio"
    "wazuh"       # DEPRECATED — only 'remove' supported, role removed
    "grafana"
    "gitea"
    "influxdb3"
    "mongodb"
    "obsidian"
    "conduit"
)

# dns_service is a tool, not a container service — always targets localhost
DNS_TOOL="dns_service"

mkdir -p "${TEMP_DIR}"
chmod 700 "${TEMP_DIR}"

TEMP_PLAYBOOK=""
cleanup() {
    if [[ $? -eq 0 && -n "${TEMP_PLAYBOOK}" && -f "${TEMP_PLAYBOOK}" ]]; then
        rm -f "${TEMP_PLAYBOOK}"
    fi
}
trap cleanup EXIT INT TERM

usage() {
    cat << EOF
Usage: $(basename "$0") [-i INVENTORY] [-h HOST] [-y] [-K] <service> <command> [options]

Options:
  -i INVENTORY   Inventory file (default: \$SOLTI_INVENTORY or inventory/localhost.yml)
  -h HOST        Target host (default: all hosts in <service>_svc group)
  -y             Skip safety prompts
  -K             Prompt for sudo (task commands only; state commands auto-detect)

State commands (run role main.yml, always become):
  prepare        System preparation — directories, SELinux, sysctl
  deploy         Deploy and start service
  remove         Stop and remove service (set DELETE_DATA=true to also remove data)

Task commands (run tasks_from inside role, no become unless -K):
  verify         Health checks — no safety prompt, no sudo
  configure      Service-specific configuration
  backup         Backup service data
  <task>         Any task file in the role's tasks/ directory

Services:
$(printf '  %s\n' "${SUPPORTED_SERVICES[@]}")
  dns_service    Tool mode — always targets localhost

Examples:
  $(basename "$0") redis prepare
  $(basename "$0") redis deploy
  $(basename "$0") redis verify
  $(basename "$0") -K redis configure
  $(basename "$0") -h podma -i inventory/podma.yml redis deploy
  $(basename "$0") -y redis remove
  $(basename "$0") redis deploy -e redis_version=7.2
EOF
    exit 1
}

is_state() {
    local cmd="$1"
    for s in "${SUPPORTED_STATES[@]}"; do
        [[ "$s" == "$cmd" ]] && return 0
    done
    return 1
}

is_service_valid() {
    local svc="$1"
    [[ "$svc" == "$DNS_TOOL" ]] && return 0
    for s in "${SUPPORTED_SERVICES[@]}"; do
        [[ "$s" == "$svc" ]] && return 0
    done
    return 1
}

target_hosts() {
    if [[ -n "$HOST" ]]; then
        echo "$HOST"
    elif [[ "$SERVICE" == "$DNS_TOOL" ]]; then
        echo "localhost"
    else
        echo "${SERVICE}_svc"
    fi
}

get_context() {
    [[ "$HOST" == "podma" || "$INVENTORY" =~ podma ]] && echo "remote" && return
    [[ "$HOST" == "firefly" || "$INVENTORY" =~ localhost ]] && echo "localhost" && return
    echo "remote"
}

prompt_user() {
    local context="$1" command="$2"

    [[ "$YES_FLAG" == "true" ]] && return 0
    # verify is read-only — never prompt
    [[ "$command" == "verify" ]] && return 0
    # explicit inventory + explicit host = user knows what they're doing
    [[ "$EXPLICIT_INVENTORY" == "true" && -n "$HOST" ]] && return 0

    local target; target=$(target_hosts)
    case "$context" in
        localhost)
            # Soft prompt only when something was explicitly targeted
            [[ "$EXPLICIT_INVENTORY" == "true" || -n "$HOST" ]] || return 0
            read -rp "Run '${command}' for ${SERVICE} on ${target}. Continue? [Y/n] " r
            [[ "$r" =~ ^[Nn] ]] && echo "Cancelled" && return 1
            ;;
        remote)
            echo ""
            echo "WARNING: Remote target"
            echo "  Target:  ${target}"
            echo "  Service: ${SERVICE}"
            echo "  Command: ${command}"
            read -rp "Proceed? [y/N] " r
            [[ ! "$r" =~ ^[Yy] ]] && echo "Cancelled" && return 1
            ;;
    esac
    return 0
}

# Probe sudo capability. Writes diagnostics to stderr, value to stdout.
probe_sudo() {
    local target="$1"
    echo "Probing sudo on ${target}..." >&2
    if ansible -i "${INVENTORY}" "${target}" -m shell -a "sudo -n true" &>/dev/null; then
        echo "NOPASSWD — no password needed" >&2
        echo "--become"
    else
        echo "Password required" >&2
        echo "--become --ask-become-pass"
    fi
}

generate_state_playbook() {
    local state="${STATE_MAP[$COMMAND]}"
    local hosts; hosts=$(target_hosts)
    local delete_data_line=""
    if [[ "$COMMAND" == "remove" && "${DELETE_DATA:-false}" == "true" ]]; then
        delete_data_line="    ${SERVICE}_delete_data: true"
    fi
    cat > "$TEMP_PLAYBOOK" << EOF
---
# Generated by svc-manage: ${SERVICE} ${COMMAND}
- name: ${COMMAND} ${SERVICE}
  hosts: ${hosts}
  vars:
    ${SERVICE}_state: ${state}
${delete_data_line}
  roles:
    - role: ${SERVICE}
EOF
}

generate_task_playbook() {
    local hosts; hosts=$(target_hosts)
    cat > "$TEMP_PLAYBOOK" << EOF
---
# Generated by svc-manage: ${SERVICE}/${COMMAND}
- name: Execute ${COMMAND} for ${SERVICE}
  hosts: ${hosts}
  gather_facts: false
  tasks:
    - name: "${SERVICE}/${COMMAND}"
      ansible.builtin.include_role:
        name: "${SERVICE}"
        tasks_from: "${COMMAND}"
EOF
}

# --- Parse options ---
while getopts "i:h:yK" opt; do
    case $opt in
        i) INVENTORY=$OPTARG; EXPLICIT_INVENTORY=true ;;
        h) HOST=$OPTARG ;;
        y) YES_FLAG=true ;;
        K) USE_SUDO=true ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -lt 2 ]] && { echo "Error: service and command required"; usage; }

SERVICE="$1"
COMMAND="$2"
shift 2
EXTRA_ARGS=("$@")

is_service_valid "$SERVICE" || { echo "Error: unknown service '${SERVICE}'"; usage; }
[[ -n "$INVENTORY" ]] || { echo "Error: inventory required — use -i INVENTORY or set SOLTI_INVENTORY env var"; exit 1; }
[[ -f "$INVENTORY" ]] || { echo "Error: inventory not found: ${INVENTORY}"; exit 1; }

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TEMP_PLAYBOOK="${TEMP_DIR}/${SERVICE}-${COMMAND}-${TIMESTAMP}.yml"

if is_state "$COMMAND"; then
    MODE="state"
    (umask 077 && generate_state_playbook)
else
    MODE="task"
    (umask 077 && generate_task_playbook)
fi

TARGET=$(target_hosts)
echo "Service:   ${SERVICE}"
echo "Command:   ${COMMAND}  (${MODE} mode)"
echo "Inventory: ${INVENTORY}"
echo "Target:    ${TARGET}"
echo ""
echo "--- playbook ---"
cat "$TEMP_PLAYBOOK"
echo "--- end ---"
echo ""

CTX=$(get_context)
prompt_user "$CTX" "$COMMAND" || exit 0

# Determine sudo flags
# dns_service makes Linode API calls only — no system changes, no sudo needed
SUDO_FLAGS=""
if [[ "$MODE" == "state" && "$SERVICE" != "$DNS_TOOL" ]]; then
    SUDO_FLAGS=$(probe_sudo "$TARGET")
elif [[ "$USE_SUDO" == "true" ]]; then
    SUDO_FLAGS=$(probe_sudo "$TARGET")
fi

START=$(date +%s)

# Optional Matrix notification (silent on failure)
# CLAUDE:  move the ~/data/matrix-logger.conf  to ~/.secrets/matrix-logger.conf
#  Add a comment for  the room name and bot so I can keep track
#  If the that secrets file exists and matrix-log.py scripts, then do this
#  TODO SMELL For this version existance is consent to send, this could be an issue later.
if [[ -x "${ANSIBLE_DIR}/bin/matrix-log.py" ]]; then
    "${ANSIBLE_DIR}/bin/matrix-log.py" message \
        "Starting ${COMMAND}: ${SERVICE} on ${HOST:-all}" \
        --level info 2>/dev/null || true
fi

echo "Running: ansible-playbook ${SUDO_FLAGS} -i ${INVENTORY} ${TEMP_PLAYBOOK} ${EXTRA_ARGS[*]}"
# shellcheck disable=SC2086
ansible-playbook ${SUDO_FLAGS} -i "${INVENTORY}" "${TEMP_PLAYBOOK}" "${EXTRA_ARGS[@]}"
EXIT_CODE=$?

DURATION=$(( $(date +%s) - START ))

if [[ -x "${ANSIBLE_DIR}/bin/matrix-log.py" ]]; then
    STATUS=$([[ $EXIT_CODE -eq 0 ]] && echo "success" || echo "failure")
    "${ANSIBLE_DIR}/bin/matrix-log.py" deployment \
        "${SERVICE}" "${HOST:-all}" "${STATUS}" \
        --duration "${DURATION}" \
        --details "command=${COMMAND}" 2>/dev/null || true
fi

if [[ $EXIT_CODE -eq 0 ]]; then
    echo ""
    echo "Success: ${SERVICE} ${COMMAND} completed (${DURATION}s)"
    rm -f "${TEMP_PLAYBOOK}"
    exit 0
else
    echo ""
    echo "Failed: ${SERVICE} ${COMMAND} (exit ${EXIT_CODE})"
    echo "Playbook preserved for debugging: ${TEMP_PLAYBOOK}"
    exit $EXIT_CODE
fi
