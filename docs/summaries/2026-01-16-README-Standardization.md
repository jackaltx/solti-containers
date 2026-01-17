# README Standardization Review

**Date**: 2026-01-16
**Purpose**: Establish consistent README structure for ref.tools integration
**Status**: ✅ Complete

## Motivation

User requested README review for ref.tools registration. Consistency enables:
- Predictable information location
- Automated documentation parsing
- Better developer experience
- Easier onboarding

## Analysis Results

### README Structure Comparison

**MongoDB (Reference Implementation):**
```
1. Title + Description
2. Overview
3. Quick Start (Prepare/Deploy/Verify/Access)
4. Configuration
5. Directory Structure
6. Service Management ← Early placement
7. Testing
8. Traefik Integration
9. Troubleshooting
10. Security Notes
11. Performance Tuning
12. Backup and Restore
13. References
```

**Obsidian (Current Implementation):**
```
1. Title + Description
2. Overview
3. Features
4. Requirements
5. Quick Start (Prepare/Deploy/Verify/Access)
6. Configuration
7. Directory Structure
8. Service Management ← ADDED (was missing)
9. Verification ← Detailed section
10. Upgrade Management ← NEW (MongoDB missing!)
11. Traefik Integration
12. Advanced Usage
13. Troubleshooting
14. Remote Host Deployment ← NEW (MongoDB missing!)
15. Architecture
16. Security Considerations
17. Links
18. Support
```

### Key Findings

**Obsidian is MORE complete:**
- ✅ Upgrade Management section (with check_upgrade.yml examples)
- ✅ Remote Host Deployment section (multi-host patterns)
- ✅ Detailed Verification section
- ✅ Support section
- ✅ Links section

**MongoDB is MORE database-focused:**
- Performance Tuning (database-specific)
- Backup and Restore (database-specific)
- Testing vs Verification (terminology)

**Both have:**
- Quick Start with 4 steps
- Configuration (env + inventory)
- Directory Structure
- Traefik Integration
- Troubleshooting
- Security notes

## Template Created

**File**: [docs/README-Template.md](../README-Template.md)

Defines:
- **Required sections** (must have)
- **Optional sections** (when applicable)
- **Section format guidelines**
- **Consistency checklist**
- **ref.tools integration notes**

## Changes Made

### Obsidian README
**Added**: Service Management section (between Directory Structure and Verification)

**Content:**
```markdown
## Service Management

### Start/Stop/Status
- systemctl commands

### Logs
- journalctl and podman logs commands

### Remove
- With/without data deletion
```

**Result**: Obsidian README now has all required sections + extras

## Standardized Structure

### Required Sections (Priority Order)

1. **Title + One-liner** - Service name and deployment method
2. **Overview** - What components get deployed
3. **Quick Start** - 4 numbered steps (Prepare/Deploy/Verify/Access)
4. **Configuration** - Inventory variables (+ env vars if needed)
5. **Directory Structure** - File tree with explanations
6. **Service Management** - Start/stop/logs/remove commands
7. **Troubleshooting** - Common issues with resolutions
8. **Security Considerations** - Security-relevant info

### Optional Sections (Include When Applicable)

- **Features** - If complex feature set
- **Requirements** - If special prerequisites
- **Verification** - If complex verification needed
- **Upgrade Management** - If check_upgrade.yml exists
- **Traefik Integration** - If Traefik labels configured
- **Advanced Usage** - If advanced configuration available
- **Remote Host Deployment** - If multi-host tested
- **Architecture** - If implementation details valuable
- **Performance Tuning** - If tuning options exist
- **Backup and Restore** - If backup procedures documented
- **Links** - External references
- **Support** - Where to get help

## Recommendations

### For MongoDB README
**Should add:**
1. Upgrade Management section (check_upgrade.yml exists but undocumented)
2. Remote Host Deployment section (works on podma but undocumented)

### For Other Service READMEs
**Should audit against template:**
- Redis
- Mattermost
- Elasticsearch
- Grafana
- HashiVault
- MinIO
- InfluxDB3
- Gitea

### For New Services
**Use Obsidian as reference** - it's the most complete and current.

## ref.tools Integration

Standard structure enables parsing:

### Quick Start Extraction
```yaml
service: obsidian
commands:
  prepare: "./manage-svc.sh obsidian prepare"
  deploy: "./manage-svc.sh obsidian deploy"
  verify: "./svc-exec.sh obsidian verify"
access:
  http: "http://127.0.0.1:3010"
  https: "https://127.0.0.1:3011"
```

### Configuration Options
```yaml
service: obsidian
inventory_vars:
  - obsidian_data_dir
  - obsidian_port
  - obsidian_https_port
  - obsidian_tz
  - obsidian_enable_traefik
```

### Troubleshooting Index
Each issue becomes searchable:
- Problem keywords
- Error messages
- Resolution steps

## Section Format Guidelines

### Title
```markdown
# [Service] Role
```

### One-liner
Immediately after title:
```markdown
Deploys [Service] as a rootless Podman container with systemd integration.
```

### Quick Start
Always 4 numbered steps:
```markdown
### 1. Prepare (one-time setup)
### 2. Deploy
### 3. Verify
### 4. Access
```

### Commands
Always use code blocks:
```markdown
```bash
./manage-svc.sh service action
```
```

### Directory Trees
Always show structure:
```markdown
```text
~/service-data/
├── config/     # Description
└── data/       # Description
```
```

## Consistency Checklist

For any README:

- [ ] Title matches: `# [Service] Role`
- [ ] One-line description present
- [ ] Overview lists components
- [ ] Quick Start has 4 numbered steps
- [ ] Configuration shows inventory vars
- [ ] Directory Structure is a tree
- [ ] Service Management has start/stop/logs/remove
- [ ] Troubleshooting has at least 3 issues
- [ ] Security section exists
- [ ] All commands are copy-pasteable
- [ ] Port numbers documented
- [ ] Links to official docs

## Files Modified

| File | Change |
|------|--------|
| [roles/obsidian/README.md](../../roles/obsidian/README.md) | Added Service Management section |
| [docs/README-Template.md](../README-Template.md) | Created standard template |
| [docs/summaries/2026-01-16-README-Standardization.md](2026-01-16-README-Standardization.md) | This document |

## Next Steps

### Immediate
1. ✅ Obsidian README updated
2. ✅ Template created
3. ✅ Analysis documented

### Optional
1. Update MongoDB README (add Upgrade Management + Remote Host sections)
2. Audit other service READMEs against template
3. Create automation to validate README structure
4. Add README linting to CI/CD

## Conclusion

**Obsidian README is now the gold standard** for service documentation in solti-containers collection. It includes:

- All required sections
- Complete service management commands
- Upgrade management workflow
- Multi-host deployment guidance
- Comprehensive troubleshooting
- Security considerations
- External references

Template created for future consistency. MongoDB README should be updated to match Obsidian's completeness (add Upgrade Management and Remote Host sections).

---

**Generated**: 2026-01-16T18:35:00-06:00
**Purpose**: README standardization for ref.tools integration
**Result**: Template created, Obsidian updated, consistency achieved
