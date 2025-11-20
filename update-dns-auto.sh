#!/bin/bash
#
# Auto-detect services from inventory and update Linode DNS
# Creates/updates CNAME records pointing to target host
#

set -euo pipefail

# Configuration
INVENTORY="${INVENTORY:-inventory.yml}"
DOMAIN="${DOMAIN:-a0a0.org}"
TTL_SEC="${TTL_SEC:-60}"
LINODE_API="https://api.linode.com/v4"

# Check for API token
if [ -z "${LINODE_TOKEN:-}" ]; then
    echo "Error: LINODE_TOKEN environment variable not set"
    exit 1
fi

# Check for required tools
for cmd in yq jq curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed"
        exit 1
    fi
done

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] <host>

Auto-detect services from inventory and create DNS records.

OPTIONS:
    -i INVENTORY    Inventory file (default: inventory.yml)
    -d DOMAIN       Domain name (default: a0a0.org)
    -t TTL          TTL in seconds (default: 60)
    -h              Show this help

ARGUMENTS:
    host            Target host (e.g., podma) - CNAMEs will point to <host>.<domain>

EXAMPLES:
    $0 podma                    # Create CNAMEs for all podma services → podma.a0a0.org
    $0 -d example.com firefly   # Create CNAMEs for firefly services → firefly.example.com

ENVIRONMENT:
    LINODE_TOKEN    Required - Linode API token
    INVENTORY       Default inventory file
    DOMAIN          Default domain name
    TTL_SEC         Default TTL
EOF
    exit 1
}

# Parse options
while getopts "i:d:t:h" opt; do
    case ${opt} in
        i) INVENTORY=$OPTARG ;;
        d) DOMAIN=$OPTARG ;;
        t) TTL_SEC=$OPTARG ;;
        h) usage ;;
        \?) usage ;;
    esac
done
shift $((OPTIND -1))

# Check for target host
if [ $# -ne 1 ]; then
    echo "Error: Target host required"
    usage
fi

TARGET_HOST=$1
TARGET_FQDN="${TARGET_HOST}.${DOMAIN}"

echo "Auto-detecting services from ${INVENTORY}"
echo "Target: ${TARGET_FQDN}"
echo "Domain: ${DOMAIN}"
echo "TTL: ${TTL_SEC} seconds"
echo ""

# Extract service names for target host from inventory
# This looks for *_svc_name variables under the target host
extract_services() {
    local host=$1

    # Use yq to extract all service groups and their host-specific svc_name variables
    yq eval "
        .all.children.ct.children |
        to_entries |
        .[] |
        select(.key | test(\"_svc$\")) |
        select(.value.hosts.${host}) |
        .value.hosts.${host} |
        to_entries |
        .[] |
        select(.key | test(\"_svc_name\")) |
        .value
    " "${INVENTORY}" 2>/dev/null || true
}

# Get service list
SERVICES=($(extract_services "${TARGET_HOST}"))

if [ ${#SERVICES[@]} -eq 0 ]; then
    echo "No services found for host '${TARGET_HOST}' in ${INVENTORY}"
    echo ""
    echo "Available hosts:"
    yq eval '.all.children.ct.children | to_entries | .[].value.hosts | keys | .[]' "${INVENTORY}" 2>/dev/null | sort -u
    exit 1
fi

echo "Found ${#SERVICES[@]} services:"
printf '  - %s\n' "${SERVICES[@]}"
echo ""

# Get domain ID
get_domain_id() {
    curl -s -H "Authorization: Bearer ${LINODE_TOKEN}" \
        "${LINODE_API}/domains" | \
        jq -r ".data[] | select(.domain == \"${DOMAIN}\") | .id"
}

# Get existing record ID for a subdomain
get_record_id() {
    local domain_id=$1
    local name=$2

    curl -s -H "Authorization: Bearer ${LINODE_TOKEN}" \
        "${LINODE_API}/domains/${domain_id}/records" | \
        jq -r ".data[] | select(.name == \"${name}\" and .type == \"CNAME\") | .id"
}

# Create CNAME record
create_cname() {
    local domain_id=$1
    local name=$2

    echo "Creating CNAME: ${name}.${DOMAIN} → ${TARGET_FQDN}"

    curl -s -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${LINODE_TOKEN}" \
        -X POST -d "{
            \"type\": \"CNAME\",
            \"name\": \"${name}\",
            \"target\": \"${TARGET_FQDN}\",
            \"ttl_sec\": ${TTL_SEC}
        }" \
        "${LINODE_API}/domains/${domain_id}/records" | \
        jq -r '.id // "ERROR"'
}

# Update existing CNAME record
update_cname() {
    local domain_id=$1
    local record_id=$2
    local name=$3

    echo "Updating CNAME: ${name}.${DOMAIN} → ${TARGET_FQDN}"

    curl -s -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${LINODE_TOKEN}" \
        -X PUT -d "{
            \"target\": \"${TARGET_FQDN}\",
            \"ttl_sec\": ${TTL_SEC}
        }" \
        "${LINODE_API}/domains/${domain_id}/records/${record_id}" | \
        jq -r '.id // "ERROR"'
}

# Main
main() {
    # Get domain ID
    DOMAIN_ID=$(get_domain_id)
    if [ -z "${DOMAIN_ID}" ]; then
        echo "Error: Could not find domain ${DOMAIN}"
        exit 1
    fi
    echo "Domain ID: ${DOMAIN_ID}"
    echo ""

    # Process each service
    for service in "${SERVICES[@]}"; do
        record_id=$(get_record_id "${DOMAIN_ID}" "${service}")

        if [ -z "${record_id}" ]; then
            # Create new record
            result=$(create_cname "${DOMAIN_ID}" "${service}")
            if [ "${result}" = "ERROR" ]; then
                echo "  ✗ Failed to create ${service}"
            else
                echo "  ✓ Created record ID: ${result}"
            fi
        else
            # Update existing record
            result=$(update_cname "${DOMAIN_ID}" "${record_id}" "${service}")
            if [ "${result}" = "ERROR" ]; then
                echo "  ✗ Failed to update ${service}"
            else
                echo "  ✓ Updated record ID: ${result}"
            fi
        fi
    done

    echo ""
    echo "DNS update complete!"
    echo ""
    echo "Service URLs (after DNS propagation):"
    for service in "${SERVICES[@]}"; do
        echo "  https://${service}.${DOMAIN}:8080"
    done
}

main "$@"
