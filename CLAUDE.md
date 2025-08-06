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
```

### Syntax Validation
```bash
# Test role syntax
ansible-playbook --syntax-check roles/<service>/tasks/main.yml

# Dry run
ansible-playbook --check -i inventory.yml <playbook>
```

## Architecture Overview

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
- Domain: `domain: a0a0.org` (used for SSL/TLS)

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
- Generated playbooks preserved in `tmp/` directory on failure
- Use `-vvv` flag with ansible-playbook for verbose output
- Check systemd user services: `systemctl --user status`
- Verify SELinux contexts on RHEL: `ls -Z ~/service-data/`

## File Locations

### Key Files
- `inventory.yml`: Service configuration and variables
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