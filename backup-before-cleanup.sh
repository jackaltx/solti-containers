#!/bin/bash
#
# backup-before-cleanup.sh - Create comprehensive backups before repo cleanup
#
# Creates timestamped backups of:
# - Full git repository (mirror)
# - Working tree snapshot
# - Stale branches bundle
# - Deleteme directories
#

set -euo pipefail

# Configuration
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${HOME}/backups/ansible/solti-containers"
REPO_NAME="solti-containers"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create backup directory
log_info "Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

# Change to repo root (in case script is called from subdirectory)
cd "$(git rev-parse --show-toplevel)"

echo ""
log_info "Starting backup process for ${REPO_NAME}"
log_info "Timestamp: ${TIMESTAMP}"
echo ""

# 1. Full git mirror backup
log_info "Step 1/4: Creating full git mirror backup..."
MIRROR_BACKUP="${BACKUP_DIR}/${REPO_NAME}-mirror-${TIMESTAMP}.git"
if git clone --mirror . "${MIRROR_BACKUP}"; then
    MIRROR_SIZE=$(du -sh "${MIRROR_BACKUP}" | cut -f1)
    log_info "✓ Mirror backup created: ${MIRROR_BACKUP} (${MIRROR_SIZE})"
else
    log_error "✗ Failed to create mirror backup"
    exit 1
fi

# 2. Working tree snapshot
log_info "Step 2/4: Creating working tree snapshot..."
SNAPSHOT_BACKUP="${BACKUP_DIR}/${REPO_NAME}-snapshot-${TIMESTAMP}.tar.gz"
if tar -czf "${SNAPSHOT_BACKUP}" \
    --exclude=.git \
    --exclude=tmp \
    --exclude=verify_output \
    --exclude='**/__pycache__' \
    --exclude='**/*.pyc' \
    .; then
    SNAPSHOT_SIZE=$(du -sh "${SNAPSHOT_BACKUP}" | cut -f1)
    log_info "✓ Snapshot created: ${SNAPSHOT_BACKUP} (${SNAPSHOT_SIZE})"
else
    log_error "✗ Failed to create snapshot"
    exit 1
fi

# 3. Stale branches bundle
log_info "Step 3/4: Creating bundle of stale branches..."
STALE_BRANCHES=(
    "old-way"
)

# Check which branches actually exist
EXISTING_BRANCHES=()
for branch in "${STALE_BRANCHES[@]}"; do
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        EXISTING_BRANCHES+=("refs/heads/${branch}")
    else
        log_warn "Branch '${branch}' does not exist, skipping"
    fi
done

if [ ${#EXISTING_BRANCHES[@]} -gt 0 ]; then
    BUNDLE_BACKUP="${BACKUP_DIR}/${REPO_NAME}-stale-branches-${TIMESTAMP}.bundle"
    if git bundle create "${BUNDLE_BACKUP}" "${EXISTING_BRANCHES[@]}"; then
        BUNDLE_SIZE=$(du -sh "${BUNDLE_BACKUP}" | cut -f1)
        log_info "✓ Branch bundle created: ${BUNDLE_BACKUP} (${BUNDLE_SIZE})"
        log_info "  Branches: ${EXISTING_BRANCHES[*]}"
    else
        log_error "✗ Failed to create branch bundle"
        exit 1
    fi
else
    log_warn "No stale branches found to bundle, skipping"
fi

# 4. Deleteme directory archive
log_info "Step 4/4: Archiving deleteme directories..."
DELETEME_FOUND=0

# Find any deleteme directories dynamically
while IFS= read -r -d '' deleteme_dir; do
    DELETEME_NAME=$(basename "${deleteme_dir}")
    DELETEME_BACKUP="${BACKUP_DIR}/${REPO_NAME}-${DELETEME_NAME}-${TIMESTAMP}.tar.gz"
    if tar -czf "${DELETEME_BACKUP}" "${deleteme_dir}"; then
        DELETEME_SIZE=$(du -sh "${DELETEME_BACKUP}" | cut -f1)
        log_info "✓ Deleteme archive created: ${DELETEME_BACKUP} (${DELETEME_SIZE})"
        DELETEME_FOUND=1
    else
        log_error "✗ Failed to create deleteme archive for ${deleteme_dir}"
        exit 1
    fi
done < <(find . -type d -name "*.deleteme" -print0 2>/dev/null)

if [ ${DELETEME_FOUND} -eq 0 ]; then
    log_warn "No deleteme directories found, skipping"
fi

# Summary
echo ""
log_info "======================================"
log_info "Backup Summary"
log_info "======================================"
log_info "Backup location: ${BACKUP_DIR}"
log_info "Total backup size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
echo ""
log_info "Created backups:"
ls -lh "${BACKUP_DIR}"/*${TIMESTAMP}* 2>/dev/null || log_warn "No timestamped backups found"
echo ""

# Restoration instructions
cat << EOF
${GREEN}Backup completed successfully!${NC}

To restore from backups:

1. Restore full repository:
   git clone ${MIRROR_BACKUP} ${REPO_NAME}-restored

2. Restore a stale branch:
   git bundle verify ${BUNDLE_BACKUP}
   git fetch ${BUNDLE_BACKUP} branch-name:branch-name

3. Extract deleteme directory:
   tar -xzf <deleteme-backup> -C /path/to/restore/

4. Extract working tree snapshot:
   tar -xzf ${SNAPSHOT_BACKUP} -C /path/to/restore/

${YELLOW}Note: Keep these backups until you've verified the cleanup worked correctly.${NC}
EOF

exit 0
