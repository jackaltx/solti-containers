#!/usr/bin/env bash
#
# run-proxmox-tests.sh - Run molecule proxmox scenario against podma test host
#
# Targets the existing podma VM directly (no Proxmox VM provisioning).
# Flow: remove → prepare → deploy → verify → cleanup (DELETE_DATA)
#
# Usage:
#   ./run-proxmox-tests.sh --services redis
#   ./run-proxmox-tests.sh --services redis,traefik

# Source lab secrets (LAB_TLD, LINODE_TOKEN, etc.)
if [ -f ~/.secrets/LabProvision ]; then
    source ~/.secrets/LabProvision
fi

# Defaults
SERVICES="redis,traefik"
TEST_NAME="proxmox"
OUTPUT_DIR="./verify_output"
DATE_STAMP=$(date +%Y%m%d-%H%M%S)

show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS]
Run molecule proxmox scenario against the podma test host.

Options:
    -h, --help              Display this help and exit
    -s, --services SVCS    Comma-separated services to test
                           Default: redis,traefik
                           Valid: redis, traefik, hashivault, elasticsearch,
                                  minio, mattermost, grafana

Examples:
    ${0##*/} --services redis
    ${0##*/} -s redis,traefik
    ${0##*/} -s hashivault
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--services)
            SERVICES="$2"
            shift 2
            ;;
        --services=*)
            SERVICES="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate services
valid_services=("redis" "traefik" "hashivault" "elasticsearch" "minio" "mattermost" "grafana" "gitea" "influxdb3" "mongodb" "obsidian" "conduit")
IFS=',' read -ra SVCS_ARRAY <<< "$SERVICES"
for svc in "${SVCS_ARRAY[@]}"; do
    found=0
    for valid_svc in "${valid_services[@]}"; do
        if [ "$svc" = "$valid_svc" ]; then
            found=1
            break
        fi
    done
    if [ $found -eq 0 ]; then
        echo "Error: Invalid service '$svc'"
        echo "Valid services: ${valid_services[*]}"
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"
LOG_FILE="${OUTPUT_DIR}/${TEST_NAME}-test-${DATE_STAMP}.out"

export MOLECULE_SERVICES="$SERVICES"

{
    echo "=== Molecule Proxmox Test Configuration ==="
    echo "Date:     $(date)"
    echo "Services: $SERVICES"
    echo "Target:   podma"
    echo "Log:      $LOG_FILE"
    echo "==========================================="
    echo
} | tee "$LOG_FILE"

# Activate virtual environment if present
if [ -d "solti-venv" ]; then
    source solti-venv/bin/activate
elif [ -d "../solti-venv" ]; then
    source ../solti-venv/bin/activate
fi

# Re-source secrets (may not have been loaded at top if file appeared after venv)
source ~/.secrets/LabProvision 2>/dev/null || true

TEMP_OUTPUT=$(mktemp)
{
    molecule test -s proxmox 2>&1
    echo $? > "$TEMP_OUTPUT"
} | tee -a "$LOG_FILE"

TEST_EXIT_CODE=$(cat "$TEMP_OUTPUT")
rm -f "$TEMP_OUTPUT"

{
    echo
    echo "=== Test Summary ==="
    echo "Completed: $(date)"
    if [ "$TEST_EXIT_CODE" -eq 0 ]; then
        echo "Status: SUCCESS"
    else
        echo "Status: FAILED (exit $TEST_EXIT_CODE)"
    fi
} | tee -a "$LOG_FILE"

ln -sf "$(basename "${LOG_FILE}")" "${OUTPUT_DIR}/latest_proxmox_test.out"

if [ "$TEST_EXIT_CODE" -eq 0 ]; then
    echo "Tests completed successfully. Log: $LOG_FILE"
    exit 0
else
    echo "Tests failed. Log: $LOG_FILE"
    exit 1
fi
