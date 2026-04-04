#!/usr/bin/env bash
# Regenerates Obsidian indices from immutable run records
# Source of truth: runs/*/run-*.md YAML frontmatter
#
# Usage: ./bin/regenerate-obsidian-indices.sh [obsidian_dir]
#
# This script uses atomic file writes (temp + mv) for NFS safety

set -euo pipefail

OBSIDIAN_DIR="${1:-./verify_output/obsidian}"
RUNS_DIR="$OBSIDIAN_DIR/runs"

# Validate directories exist
if [[ ! -d "$RUNS_DIR" ]]; then
    echo "No runs directory found at: $RUNS_DIR"
    echo "Nothing to regenerate."
    exit 0
fi

# Parse all run metadata
declare -A runs_by_platform
declare -A runs_by_service
runs_chrono=()

for run_dir in "$RUNS_DIR"/*/; do
    # Find the run summary file (run-*.md)
    index_file=$(find "$run_dir" -maxdepth 1 -name "run-*.md" | head -1)
    [[ -f "$index_file" ]] || continue

    # Extract YAML frontmatter
    timestamp=$(grep "^timestamp:" "$index_file" | cut -d' ' -f2 || echo "")
    distribution=$(grep "^distribution:" "$index_file" | cut -d' ' -f2- || echo "Unknown")
    platform=$(grep "^platform:" "$index_file" | cut -d' ' -f2 || echo "unknown")
    status=$(grep "^overall_status:" "$index_file" | cut -d' ' -f2 || echo "UNKNOWN")
    services=$(grep "^services_tested:" "$index_file" | sed 's/.*\[\(.*\)\]/\1/' | tr -d '"' || echo "")
    run_name=$(basename "$run_dir")
    index_basename=$(basename "$index_file" .md)

    # Skip if essential metadata missing
    [[ -n "$timestamp" ]] || continue

    # Store for chronological index
    runs_chrono+=("$timestamp|$distribution|$platform|$status|$run_name|$index_basename")

    # Store for platform index
    platform_key=$(echo "$distribution" | tr ' ' '-')
    runs_by_platform[$platform_key]+="$timestamp|$status|$services|$run_name|$index_basename"$'\n'

    # Store for service indices
    if [[ -n "$services" ]]; then
        IFS=',' read -ra svc_array <<< "$services"
        for svc in "${svc_array[@]}"; do
            svc=$(echo "$svc" | xargs)  # trim whitespace
            runs_by_service[$svc]+="$timestamp|$distribution|$platform|$status|$run_name|$index_basename"$'\n'
        done
    fi
done

# Generate chronological index (atomic write with NFS-safe temp file)
{
    cat <<EOF
---
type: index
index_type: chronological
last_updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---

# Test Run History

All test runs in chronological order (newest first).

[[README|← Map of Content]]

## Runs

EOF

    # Sort chronologically (newest first)
    printf '%s\n' "${runs_chrono[@]}" | sort -r | while IFS='|' read -r ts dist plat stat runname indexname; do
        # Format timestamp for display
        date_str=$(date -d "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
        status_icon="✅"
        [[ "$stat" != "PASSED" ]] && status_icon="❌"
        echo "- $status_icon $date_str - [[runs/$runname/$indexname|$dist ($plat)]] - $stat"
    done
} > "$OBSIDIAN_DIR/index.md.tmp.$$"
mv "$OBSIDIAN_DIR/index.md.tmp.$$" "$OBSIDIAN_DIR/index.md"

echo "✓ Regenerated chronological index: $OBSIDIAN_DIR/index.md"

# Generate platform-specific indices
for platform_key in "${!runs_by_platform[@]}"; do
    platform_display=$(echo "$platform_key" | tr '-' ' ')
    index_file="$OBSIDIAN_DIR/${platform_key}-Index.md"

    {
        cat <<EOF
---
type: index
index_type: platform
platform: $platform_display
last_updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---

# $platform_display Test Runs

All test runs for $platform_display platform.

[[README|← Map of Content]] | [[index|Chronological]]

## Runs

EOF

        # Sort chronologically (newest first)
        echo "${runs_by_platform[$platform_key]}" | grep -v '^$' | sort -r | while IFS='|' read -r ts stat services runname indexname; do
            [[ -n "$runname" ]] || continue
            date_str=$(date -d "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
            status_icon="✅"
            [[ "$stat" != "PASSED" ]] && status_icon="❌"
            echo "- $status_icon $date_str - [[runs/$runname/$indexname|Test Run]] - Services: $services - $stat"
        done
    } > "$index_file.tmp.$$"
    mv "$index_file.tmp.$$" "$index_file"

    echo "✓ Regenerated platform index: $index_file"
done

# Generate service-specific indices
for service in "${!runs_by_service[@]}"; do
    service_display=$(echo "$service" | sed 's/\b\(.\)/\u\1/')  # Capitalize first letter
    index_file="$OBSIDIAN_DIR/${service_display}-Service.md"

    {
        cat <<EOF
---
type: index
index_type: service
service: $service
last_updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---

# $service_display Service Test History

All test runs that included $service verification.

[[README|← Map of Content]] | [[index|Chronological]]

## Test Results by Platform

EOF

        # Group by platform
        declare -A platform_runs
        echo "${runs_by_service[$service]}" | grep -v '^$' | while IFS='|' read -r ts dist plat stat runname indexname; do
            [[ -n "$runname" ]] || continue
            platform_key=$(echo "$dist" | tr ' ' '-')
            echo "$ts|$stat|$runname|$indexname" >> "/tmp/svc_${service}_${platform_key}.$$"
        done

        # Output by platform
        for platform_file in /tmp/svc_${service}_*.$$; do
            [[ -f "$platform_file" ]] || continue
            platform_key=$(basename "$platform_file" | sed "s/svc_${service}_//" | sed 's/\..*//')
            platform_display=$(echo "$platform_key" | tr '-' ' ')

            echo
            echo "### $platform_display"
            echo

            sort -r "$platform_file" | while IFS='|' read -r ts stat runname indexname; do
                date_str=$(date -d "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
                status_icon="✅"
                [[ "$stat" != "PASSED" ]] && status_icon="❌"
                echo "- $status_icon $date_str - [[runs/$runname/${service}-service|Details]] - $stat"
            done

            rm -f "$platform_file"
        done
    } > "$index_file.tmp.$$"
    mv "$index_file.tmp.$$" "$index_file"

    echo "✓ Regenerated service index: $index_file"
done

echo
echo "Index regeneration complete. Found ${#runs_chrono[@]} test runs across ${#runs_by_platform[@]} platforms and ${#runs_by_service[@]} services."
