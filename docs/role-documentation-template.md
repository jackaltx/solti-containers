# [Service] Role

Deploys [Service Name] as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **[Service Component 1]** (`image:tag`) - [Purpose/Description]
- **[Service Component 2]** (optional) - [Purpose/Description]

## Features

- **[Key Feature 1]**: [Description]
- **[Key Feature 2]**: [Description]
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management
- **Traefik Support**: Optional SSL termination and reverse proxy
- **Upgrade Detection**: Built-in check for image updates

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role
- [Any service-specific requirements]

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh [service] prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Set required environment variables (if any)
export SERVICE_PASSWORD="your_secure_password"

./manage-svc.sh [service] deploy
```

Deploys and starts the service with all components.

### 3. Verify

```bash
./svc-exec.sh [service] verify
```

Runs health checks and functional tests.

### 4. Access

- **[Service]**: `http://localhost:[PORT]` or `protocol://localhost:[PORT]`
- **[Admin/GUI]**: `http://localhost:[GUI_PORT]` (if applicable)
- **With Traefik SSL**: `https://[service].a0a0.org:8080`

## Configuration

### Environment Variables

```bash
export SERVICE_VAR="value"        # Description (default: default_value)
export SERVICE_PASSWORD="secret"  # Description (required)
```

### Inventory Variables

```yaml
# Data and ports
[service]_data_dir: "{{ lookup('env', 'HOME') }}/[service]-data"
[service]_port: [PORT]
[service]_gui_port: [GUI_PORT]  # If applicable

# Service configuration
[service]_image: "docker.io/[organization]/[image]:[tag]"
[service]_enable_feature: true

# Traefik integration
[service]_enable_traefik: false
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/[service]-data/
├── config/          # Service configuration files
├── data/            # Application data (persistent)
├── logs/            # Service logs (if applicable)
└── certs/           # TLS certificates (if applicable)
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status [service]-pod

# Start service
systemctl --user start [service]-pod

# Stop service
systemctl --user stop [service]-pod

# Restart service
systemctl --user restart [service]-pod

# Enable on boot
systemctl --user enable [service]-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u [service]-pod -f

# View container logs
podman logs [service]-svc

# View last 50 lines
podman logs --tail 50 [service]-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh [service] remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh [service] remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status [service]-pod

# Check container logs
podman logs [service]-svc

# Test [service] endpoint
curl -I http://127.0.0.1:[PORT]

# Run verification tasks
./svc-exec.sh [service] verify
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh [service] check_upgrade
```

**Output when updates available:**

```text
TASK [[service] : Display container status]
ok: [firefly] => {
    "msg": "[service]-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [[service] : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: [service]-svc"
}
```

**Output when up-to-date:**

```text
TASK [[service] : Display container status]
ok: [firefly] => {
    "msg": "[service]-svc:Up to date (abc123)"
}

TASK [[service] : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh [service] remove

# 2. Redeploy with latest image
./manage-svc.sh [service] deploy

# 3. Verify new version
./svc-exec.sh [service] verify
```

**Note**: Data in `~/[service]-data/` persists across upgrades.

## Traefik Integration

When Traefik is deployed with `[service]_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates: `[service].a0a0.org` → `firefly.a0a0.org`

1. Access via HTTPS:
   - `https://[service].a0a0.org:8080`

## Advanced Usage

### [Advanced Feature 1]

```bash
# [Description of advanced usage]
[command example]
```

### [Advanced Feature 2]

```yaml
# [Configuration example]
[service]_advanced_option: value
```

### Resource Limits

Add resource limits in `quadlet_rootless.yml`:

```yaml
quadlet_options:
  - |
    [Container]
    Memory=2G
    CPUQuota=200%
```

## Troubleshooting

### Issue: [Common Problem 1]

**Problem**: [Description of symptoms]

**Detection**:

```bash
[diagnostic command]
```

**Resolution**: [Steps to fix]

```bash
[solution commands]
```

### Issue: [Common Problem 2]

**Problem**: [Description]

**Detection**:

```text
Error message or output
```

**Resolution**: [Fix steps]

### Issue: [Common Problem 3]

**Problem**: [Description]

**Resolution**: [Steps]

```bash
[commands]
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
[service]_svc:
  hosts:
    podma:
      [service]_svc_name: "[service]-podma"
  vars:
    [service]_port: [PORT]  # Avoid port conflicts

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml [service] prepare
./manage-svc.sh -h podma -i inventory/podma.yml [service] deploy
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

See [docs/Claude-new-quadlet.md](../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- Ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- [Service-specific security notes]

## Links

- [Official Documentation](https://example.com)
- [Docker Hub Image](https://hub.docker.com/r/org/image)
- [GitHub Repository](https://github.com/org/repo)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs [service]-svc`
2. Systemd logs: `journalctl --user -u [service]-pod`
3. Verification output: `./svc-exec.sh [service] verify`

For [Service] application issues, consult the [official documentation](https://example.com).

---

## Template Usage Notes

**This template is optimized for ref.tools integration and follows the standardized README structure.**

### Required Customizations

1. **Replace [Service]** with actual service name throughout
2. **Replace [PORT]** with actual port numbers
3. **Update Overview** with actual components and images
4. **Add Environment Variables** section if service uses them
5. **Update Directory Structure** with actual paths
6. **Add Troubleshooting** issues you've encountered
7. **Update Links** with actual URLs

### Optional Sections

Remove if not applicable:

- Environment Variables (if service doesn't use them)
- Advanced Usage (if no advanced features)
- GUI/Admin access (if single component)

Add if applicable:

- Performance Tuning (for databases)
- Backup and Restore (for data services)
- Clustering (for distributed services)

### Testing Checklist

Before committing:

- [ ] Title matches: `# [Service] Role`
- [ ] One-line description updated
- [ ] Overview lists actual components
- [ ] Quick Start has 4 numbered steps
- [ ] All [PORT] placeholders replaced
- [ ] Directory Structure matches actual layout
- [ ] All commands tested and work
- [ ] Troubleshooting has real issues
- [ ] Security section updated
- [ ] Links point to real URLs

### Consistency with Standard

This template matches [docs/README-Template.md](README-Template.md) structure for ref.tools compatibility.
