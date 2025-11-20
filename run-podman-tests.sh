#!/usr/bin/env bash

# Source lab secrets if available (for LAB_DOMAIN, etc.)
if [ -f ~/.secrets/LabProvision ]; then
    source ~/.secrets/LabProvision
fi

# Default values
SERVICES="redis,traefik"
TEST_NAME="podman"
OUTPUT_DIR="./verify_output"
DATE_STAMP=$(date +%Y%m%d-%H%M%S)
PLATFORM=""

# Help function
show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS]
Run molecule tests for specified container services.

Options:
    -h, --help              Display this help and exit
    -s, --services SVCS    Specify services to test (comma-separated)
                           Default: redis,traefik
                           Valid: redis, traefik, hashivault, elasticsearch,
                                  minio, mattermost, grafana
    -n, --name NAME        Specify test name
                           Default: podman
    -p, --platform PLAT    Specify platform (uut-deb12, uut-rocky9, uut-ct2, or all)
                           Default: all
                           uut-deb12 = Debian 12
                           uut-rocky9 = Rocky 9
                           uut-ct2 = Ubuntu 24

Example:
    ${0##*/} --services traefik,hashivault --platform uut-deb12
    ${0##*/} -s redis -p uut-rocky9
    ${0##*/} --services "traefik,hashivault" --name vault_test
EOF
}

# Parse arguments
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
        -n|--name)
            TEST_NAME="$2"
            shift 2
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate services
valid_services=("redis" "traefik" "hashivault" "elasticsearch" "minio" "mattermost" "grafana")
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
        echo "Valid services are: ${valid_services[*]}"
        exit 1
    fi
done

# Validate platform if specified
if [ -n "$PLATFORM" ]; then
    valid_platforms=("uut-deb12" "uut-rocky9" "uut-ct2" "all")
    found=0
    for valid_plat in "${valid_platforms[@]}"; do
        if [ "$PLATFORM" = "$valid_plat" ]; then
            found=1
            break
        fi
    done
    if [ $found -eq 0 ]; then
        echo "Error: Invalid platform '$PLATFORM'"
        echo "Valid platforms are: ${valid_platforms[*]}"
        exit 1
    fi
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate log filename
LOG_FILE="${OUTPUT_DIR}/${TEST_NAME}-test-${DATE_STAMP}.out"

# Export environment variables
export MOLECULE_SERVICES="$SERVICES"
export MOLECULE_TEST_NAME="$TEST_NAME"
if [ -n "$PLATFORM" ]; then
    export MOLECULE_PLATFORM_NAME="$PLATFORM"
fi

# Print test configuration
{
    echo "=== Molecule Test Configuration ==="
    echo "Date: $(date)"
    echo "Services: $SERVICES"
    echo "Platform: ${PLATFORM:-all}"
    echo "Test name: $TEST_NAME"
    echo "Output file: $LOG_FILE"
    echo "=================================="
    echo
} | tee "$LOG_FILE"

# Activate virtual environment if it exists
if [ -d "solti-venv" ]; then
    source solti-venv/bin/activate
elif [ -d "../solti-venv" ]; then
    source ../solti-venv/bin/activate
fi

# Source development secrets (development environment only)
# Long-term: migrate to HashiCorp Vault when key env vars are not set
source ~/.secrets/LabProvision 2>/dev/null || true
source ~/.secrets/LabGiteaToken 2>/dev/null || true

# Run the tests and capture output
# Using a temporary file to capture the exit code
TEMP_OUTPUT=$(mktemp)
{
    molecule test -s podman 2>&1
    echo $? > "$TEMP_OUTPUT"
} | tee -a "$LOG_FILE"

# Read the exit code
TEST_EXIT_CODE=$(cat "$TEMP_OUTPUT")
rm -f "$TEMP_OUTPUT"

# Append test summary to log
{
    echo
    echo "=== Test Summary ==="
    echo "Completed at: $(date)"
    if [ "$TEST_EXIT_CODE" -eq 0 ]; then
        echo "Status: SUCCESS"
    else
        echo "Status: FAILED - Exit code $TEST_EXIT_CODE"
    fi
} | tee -a "$LOG_FILE"

# Create a symlink to latest log (use basename to avoid nested paths)
ln -sf "$(basename "${LOG_FILE}")" "${OUTPUT_DIR}/latest_test.out"

# Exit with the correct status
if [ "$TEST_EXIT_CODE" -eq 0 ]; then
    echo "Tests completed successfully. Log saved to $LOG_FILE"
    exit 0
else
    echo "Tests failed. Log saved to $LOG_FILE"
    exit 1
fi
