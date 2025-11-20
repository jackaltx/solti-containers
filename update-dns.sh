#!/bin/bash
#
# Update Linode DNS records for deployed services
# Creates/updates CNAME records pointing to podma.a0a0.org
#

set -euo pipefail

# Configuration
DOMAIN="a0a0.org"
TARGET="podma.${DOMAIN}"
TTL_SEC=60
LINODE_API="https://api.linode.com/v4"

# Check for API token
if [ -z "${LINODE_TOKEN:-}" ]; then
    echo "Error: LINODE_TOKEN environment variable not set"
    exit 1
fi

# Services to create CNAMEs for
SERVICES=(
    "gitea-test"
    "grafana-test"
    "influxdb3-test"
    "mattermost-test"
    "minio-test"
    "minio-console-test"
    "redis-ui-test"
    "vault-test"
    "hashivault-test"
    "traefik-test"
)

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

    echo "Creating CNAME: ${name}.${DOMAIN} -> ${TARGET}"

    curl -s -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${LINODE_TOKEN}" \
        -X POST -d "{
            \"type\": \"CNAME\",
            \"name\": \"${name}\",
            \"target\": \"${TARGET}\",
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

    echo "Updating CNAME: ${name}.${DOMAIN} -> ${TARGET}"

    curl -s -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${LINODE_TOKEN}" \
        -X PUT -d "{
            \"target\": \"${TARGET}\",
            \"ttl_sec\": ${TTL_SEC}
        }" \
        "${LINODE_API}/domains/${domain_id}/records/${record_id}" | \
        jq -r '.id // "ERROR"'
}

# Main
main() {
    echo "Updating DNS for ${DOMAIN}"
    echo "Target: ${TARGET}"
    echo "TTL: ${TTL_SEC} seconds"
    echo ""

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
}

main "$@"
