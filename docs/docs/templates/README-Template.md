# README Template for Service Roles

Standard structure for service role README files in the solti-containers collection.

## Purpose

Consistent README structure enables:
- Quick onboarding for new users
- Easy reference for ref.tools integration
- Standardized documentation across all services
- Predictable information location

## Standard Structure

```markdown
# [Service] Role

One-line description of the service and deployment method.

## Overview

Brief description of what this role deploys:
- Component 1 (image:tag) - Purpose
- Component 2 (optional) - Purpose

## Quick Start

### 1. Prepare (one-time setup)
Commands and what they do.

### 2. Deploy
Commands with any required environment variables.

### 3. Verify
Verification commands.

### 4. Access
- Local URLs
- Traefik SSL URLs
- Connection strings

## Configuration

### Environment Variables (if any)
Required and optional env vars with defaults.

### Inventory Variables
Common configuration options from defaults/main.yml.

## Directory Structure
File tree showing data directories and their purpose.

## Service Management
Common systemd and podman commands:
- Start/Stop/Status
- Logs
- Remove (with/without data)

## Verification
Manual verification commands and expected output.

## Upgrade Management (if check_upgrade.yml exists)
- Check for updates command
- Example output
- Upgrade procedure

## Traefik Integration
DNS configuration and SSL setup steps.

## Advanced Usage (optional)
Advanced configuration, resource limits, custom args, etc.

## Troubleshooting
Common issues with:
- Problem description
- Detection method
- Resolution steps

## Remote Host Deployment (if multi-host tested)
Multi-host deployment considerations:
- Unique service names
- Port conflicts
- Testing workflow

## Architecture (optional)
Technical details about the implementation.

## Security Considerations
Security-relevant information:
- Port binding
- Authentication
- SELinux
- File permissions

## Links
- Official documentation
- Docker Hub images
- Related resources

## Support
Where to get help.
```

## Required Sections

These sections **must** be present in every README:

1. **Title and Description** - `# [Service] Role` + one-liner
2. **Overview** - What gets deployed
3. **Quick Start** - Steps 1-4 (Prepare, Deploy, Verify, Access)
4. **Configuration** - Inventory variables
5. **Directory Structure** - Data layout
6. **Service Management** - Common operations
7. **Troubleshooting** - At least 3 common issues
8. **Security Considerations** - Security notes

## Optional Sections

Include these when applicable:

- **Environment Variables** - If service uses them
- **Verification** - If complex verification needed
- **Upgrade Management** - If check_upgrade.yml exists
- **Traefik Integration** - If Traefik labels configured
- **Advanced Usage** - If advanced config available
- **Remote Host Deployment** - If multi-host tested
- **Architecture** - If implementation details valuable
- **Performance Tuning** - If tuning options exist
- **Backup and Restore** - If backup procedures documented
- **Links** - External references

## Section Guidelines

### Title Format
```markdown
# [Service] Role
```
Example: `# MongoDB Role`, `# Obsidian Role`

### One-liner Description
Immediately after title, describe:
- What service does
- Deployment method (Podman, quadlets, systemd)

Example:
```markdown
Deploys MongoDB as a rootless Podman container with systemd integration using the quadlet pattern.
```

### Quick Start Format
Always use numbered steps:
```markdown
### 1. Prepare (one-time setup)
### 2. Deploy
### 3. Verify
### 4. Access
```

Include:
- Exact commands (copy-pasteable)
- Brief description of what each command does
- Access URLs/connection strings

### Configuration Format

**Environment Variables** (if used):
```markdown
### Environment Variables

```bash
export SERVICE_VAR=value    # Description (default: default_value)
```
```

**Inventory Variables**:
```markdown
### Inventory Variables

```yaml
service_data_dir: "{{ lookup('env', 'HOME') }}/service-data"
service_port: 8080
service_enable_feature: true
```
```

### Troubleshooting Format

Each issue should include:
```markdown
#### Issue Name

**Problem**: Description of symptoms

**Detection**:
```
Error message or command output
```

**Resolution**: Steps to fix
```

## Consistency Checklist

Before committing, verify:

- [ ] Title matches pattern: `# [Service] Role`
- [ ] One-line description present
- [ ] All required sections included
- [ ] Quick Start has 4 numbered steps
- [ ] Commands are copy-pasteable (use \`\`\` blocks)
- [ ] Port numbers documented
- [ ] Directory structure shown as tree
- [ ] Troubleshooting has at least 3 issues
- [ ] Security considerations documented
- [ ] Links to official docs included

## Examples

### Good READMEs to Reference
- [roles/mongodb/README.md](../roles/mongodb/README.md) - Reference implementation
- [roles/obsidian/README.md](../roles/obsidian/README.md) - Recently updated
- [roles/influxdb3/README.md](../roles/influxdb3/README.md) - Complex service

### READMEs Needing Updates
Check other role READMEs against this template and update as needed.

## Maintenance

When creating or updating a README:
1. Copy this template
2. Fill in service-specific details
3. Remove optional sections if not applicable
4. Add custom sections after Architecture if needed
5. Run through consistency checklist
6. Test all commands before committing

## Integration with ref.tools

This standard structure enables ref.tools to:
- Extract Quick Start commands
- Parse configuration options
- Index troubleshooting solutions
- Generate usage examples
- Build cross-references

Consistency = Better tooling integration!
