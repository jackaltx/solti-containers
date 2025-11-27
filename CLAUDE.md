# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Commands

### Service Management
```bash
# Primary lifecycle commands
./manage-svc.sh <service> prepare   # System preparation (one-time per service)
./manage-svc.sh <service> deploy    # Deploy and start service
./manage-svc.sh <service> remove    # Remove service (preserves data by default)

# Task execution
./svc-exec.sh <service> verify      # Execute verification tasks
./svc-exec.sh <service> configure   # Run service-specific tasks
./svc-exec.sh -K <service> <task>   # Use sudo for privileged operations
```

**Important**: `manage-svc.sh` automatically prompts for sudo password (`-K` flag is built-in) for two critical reasons:

1. **Technical**: Containers create files with elevated ownership that your user cannot modify
2. **Workflow**: Enables iterative development - deploy/remove cycles preserve data, allowing you to "iterate until you get it right" without losing test data (elasticsearch indices, mattermost channels, etc.)

Data persists by default. Set `<SERVICE>_DELETE_DATA=true` in inventory.yml for full cleanup.

### Supported Services
- redis, elasticsearch, hashivault, mattermost, traefik, minio, grafana, wazuh

### Testing & Verification
```bash
# Verify service status
systemctl --user status <service>-pod

# Check container logs
podman logs <service>-svc

# Verify network connectivity
podman network inspect ct-net

# Check all running containers
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Monitor resource usage
podman stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

### Syntax Validation
```bash
# Test role syntax
ansible-playbook --syntax-check roles/<service>/tasks/main.yml

# Dry run with inventory
ansible-playbook --check -i inventory.yml <playbook>

# Test with specific host
ansible-playbook --syntax-check roles/<service>/tasks/main.yml --limit firefly

# Validate YAML files
yamllint roles/<service>/tasks/main.yml
```

### Incremental Lint Remediation

**Strategy**: Fix lint errors incrementally to avoid overwhelming noise while progressing toward zero errors.

**Workflow**:
```bash
# Fix a batch of lint errors (10 by default)
/lint-fix

# Fix specific number of errors
/lint-fix 20

# Fix all remaining errors (before PR to main)
/lint-fix --all
```

**Key Principles**:
- **Test branch**: Allows warnings (incremental fixes)
- **Main branch**: Requires zero errors (strict mode)
- **Priority**: CRITICAL → IMPORTANT → MINOR → TRIVIAL
- **Batching**: Fix 10-15 errors per sync to test branch
- **Tracking**: `.lint-progress.yml` monitors progress

**Configuration Files**:
- `.markdownlintrc`: Relaxed line-length to 160 chars
- `.ansible-lint`: Trivial rules in warn_list (don't block CI)
- `.yamllint`: Line-length warning at 160 chars
- `.github/workflows/lint.yml`: Conditional strictness by branch

**Error Categories**:
1. **CRITICAL** (fix immediately): Syntax errors, load failures
2. **IMPORTANT** (best practices): no-changed-when, command-instead-of-module, risky-file-permissions
3. **MINOR** (style): truthy values (yes/no vs true/false), task name casing
4. **TRIVIAL** (formatting): comment spacing, braces, trailing spaces, line length

**Progress Tracking**:
- Baseline: ~1,800 errors (Nov 2025)
- Target: 0 errors by Dec 2025
- Rate: 10-15 fixes per test branch sync
- Status: See `.lint-progress.yml`

**Before PR to Main**:
1. Run `/lint-fix --all` to clear remaining errors
2. Verify all linters pass: `yamllint . && ansible-lint && markdownlint "**/*.md"`
3. Create PR (CI enforces zero errors on main branch)

## Architecture Overview

### The Three Architectural Pillars

SOLTI containers is built on three core innovations that work together (detailed in Container-Role-Architecture.md):

1. **Podman Quadlets** - Modern container-to-systemd integration
   - Single declarative file replaces two-step container creation + systemd generation
   - Filename becomes service identity (elasticsearch.pod → elasticsearch-pod.service)
   - Native systemd integration with standard `systemctl` commands

2. **Dynamic Playbook Generation** - Inventory-driven automation
   - `manage-svc.sh` generates playbooks on-the-fly from templates
   - Single script handles all services and actions (prepare/deploy/remove)
   - Eliminates hundreds of lines of duplicate playbook code
   - Generated playbooks preserved on failure for debugging

3. **Role Inheritance Pattern** - Shared functionality via `_base` role
   - Service properties define structure, `_base` role uses them generically
   - Common functionality written once, inherited by all services
   - 98% reduction in boilerplate code per service
   - Bugs fixed in `_base` fix all services instantly

**Result**: Consistent patterns, minimal code duplication, rapid service deployment.

### The SOLTI Pattern
This collection follows a standardized container deployment pattern with these core components:

1. **_base role**: Common functionality for all services
   - Directory creation and permissions
   - Network setup (ct-net)
   - SELinux configuration
   - Cleanup operations

2. **Service-specific roles**: Each service follows standard structure:
   - `tasks/main.yml`: Entry point that includes prepare → prerequisites → quadlet_rootless → verify
   - `tasks/prepare.yml`: Includes _base/prepare for common setup
   - `tasks/prerequisites.yml`: Service-specific setup (config files, directories)
   - `tasks/quadlet_rootless.yml`: Container deployment using Quadlets + systemd
   - `tasks/verify.yml`: Health checks and functionality tests

3. **Management Layer**:
   - `manage-svc.sh`: Dynamic playbook generation for lifecycle management
   - `svc-exec.sh`: Task execution wrapper
   - `inventory.yml`: Service configuration and variables

### Container Technology Stack
- **Podman**: Rootless containers with systemd integration
- **Quadlets**: Systemd unit files for container services
- **ct-net**: Shared container network with DNS resolution
- **User services**: All containers run under user accounts with `loginctl enable-linger`

### Directory Structure
```
~/<service>-data/           # Service data (preserved on remove)
├── config/                 # Configuration files
├── data/                   # Application data
├── logs/                   # Service logs
└── certs/                  # TLS certificates (if applicable)
```

### State Management
Services use a state-driven approach:
- `prepare`: System preparation and directory creation
- `present`: Deploy and start containers
- `absent`: Stop and remove containers (data preserved unless `<SERVICE>_DELETE_DATA=true`)

## Key Configuration

### Inventory Variables
- Service hosts defined under `<service>_svc` groups
- Common variables: `<service>_data_dir`, `<service>_password`, `<service>_delete_data`
- Network: `service_network: "ct-net"`, DNS servers configured
- Domain: `domain: example.com` (used for SSL/TLS, configurable in inventory.yml)

### Security Model
- Rootless containers with user privileges
- Localhost binding (127.0.0.1) by default
- Traefik provides SSL termination for external access
- HashiVault integration for secrets management
- SELinux contexts applied on RHEL systems

### SSL/TLS Integration
When Traefik is deployed, services automatically get SSL termination:
- Wildcard DNS: `*.domain` → localhost
- Automatic Let's Encrypt certificates
- Internal service-to-service communication

## Development Patterns

### Adding New Services
1. Follow the standard role structure in `docs/Solti-Container-Pattern.md`
2. Implement required task files: main.yml, prepare.yml, prerequisites.yml, quadlet_rootless.yml, verify.yml
3. Add service to `SUPPORTED_SERVICES` array in management scripts
4. Update inventory.yml with service-specific variables
5. Include Traefik labels for SSL integration

### Service Dependencies
- Services depend on container network (ct-net) created by _base role
- Traefik should be deployed first for SSL termination
- HashiVault provides centralized secrets management
- Services can reference each other by container names within ct-net

### Troubleshooting
```bash
# Generated playbooks preserved in tmp/ directory on failure
ls -la tmp/<service>-*.yml

# Use verbose output for debugging
ansible-playbook -vvv <playbook>

# Check systemd user services
systemctl --user status
systemctl --user list-units --type=service --state=failed

# Verify SELinux contexts on RHEL
ls -Z ~/<service>-data/
seinfo --type | grep container

# Check service-specific logs
journalctl --user -u <service>-pod -f

# Verify container configuration
podman inspect <service>-svc | jq '.[] | {Name, State, Config}'

# Check network connectivity between containers
podman exec <service>-svc ping <other-service>-svc

# Debug privilege issues
./manage-svc.sh <service> prepare --become --ask-become-pass
```

## File Locations

### Key Files
- `inventory.yml`: Service configuration and variables
  - **Shared core vars** (sync with solti-platforms): domain, mylab_nolog, ansible_user, ansible_ssh_private_key_file, mylab_non_ssh
  - **Container-specific vars**: service_network, service_dns_servers, service_dns_search, test_index, test_doc
  - mylab_nolog controls debug output in roles
- `ansible.cfg`: Ansible settings and vault configuration
- `roles/_base/`: Common functionality used by all services
- `tmp/`: Generated playbooks (preserved on failure for debugging)

### Templates
Service-specific Jinja2 templates in `roles/<service>/templates/`:
- Configuration files (`.conf.j2`, `.ini.j2`, `.yml.j2`)
- Environment files (`.env.j2`)
- Quadlet definitions (for systemd container units)

### Management Scripts
- `manage-svc.sh`: Service lifecycle (prepare/deploy/remove)
- `svc-exec.sh`: Task execution (verify/configure/backup)
- Both scripts generate temporary playbooks dynamically