# Obsidian Role

Deploy Obsidian note-taking application as a containerized service accessible via web browser.

## Overview

This role deploys [Obsidian](https://obsidian.md) using the [LinuxServer.io](https://www.linuxserver.io/) Docker image in a rootless Podman container with systemd integration. Obsidian is a powerful knowledge base application that works on top of local Markdown files.

## Features

- **Web-based access**: Access Obsidian via browser (HTTP and HTTPS ports)
- **Local storage**: All notes stored in Markdown format on host filesystem
- **Rootless containers**: Enhanced security with user-level Podman
- **Systemd integration**: Native service management via systemd
- **Traefik support**: Optional SSL termination and reverse proxy
- **Resource limits**: Configurable memory and CPU limits

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role

## Quick Start

### 1. Prepare System (One-time)

```bash
./manage-svc.sh obsidian prepare
```

This creates:
- Data directory structure
- Container network
- SELinux contexts (on RHEL-based systems)

### 2. Deploy Service

```bash
./manage-svc.sh obsidian deploy
```

This:
- Creates Podman pod with containers
- Generates systemd units
- Starts the service
- Runs verification checks

### 3. Access Obsidian

- **HTTP**: <http://127.0.0.1:3000>
- **HTTPS**: <https://127.0.0.1:3001>

Your vaults are stored in: `~/obsidian-data/vaults/`

### 4. Remove Service

```bash
# Preserve data
./manage-svc.sh obsidian remove

# Remove everything including data
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh obsidian remove
```

## Configuration

### Inventory Variables

Configure in `inventory/localhost.yml`:

```yaml
obsidian_svc:
  hosts:
    firefly:
      obsidian_svc_name: "obsidian"
  vars:
    # Data directory
    obsidian_data_dir: "{{ lookup('env', 'HOME') }}/obsidian-data"

    # Port mappings (localhost only)
    obsidian_port: 3000        # HTTP
    obsidian_https_port: 3001  # HTTPS

    # Timezone for container
    obsidian_tz: "America/Chicago"

    # Traefik SSL integration
    obsidian_enable_traefik: true
```

### Default Values

See [defaults/main.yml](defaults/main.yml) for complete configuration options:

- **Image**: `lscr.io/linuxserver/obsidian:latest`
- **Shared memory**: 1GB (required for browser rendering)
- **User/Group**: Matches host user UID/GID
- **Network**: Connected to `ct-net` for inter-container communication

## Directory Structure

After deployment:

```text
~/obsidian-data/
├── config/          # Application configuration
└── vaults/          # Your Obsidian vaults (Markdown files)
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status obsidian-pod

# Start service
systemctl --user start obsidian-pod

# Stop service
systemctl --user stop obsidian-pod

# Restart service
systemctl --user restart obsidian-pod

# Enable on boot
systemctl --user enable obsidian-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u obsidian-pod -f

# View container logs
podman logs obsidian-svc

# View last 50 lines
podman logs --tail 50 obsidian-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh obsidian remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh obsidian remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status obsidian-pod

# Check container logs
podman logs obsidian-svc

# Test web interface
curl -I http://127.0.0.1:3010

# Run verification tasks
./svc-exec.sh obsidian verify
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh obsidian check_upgrade
```

**Output when updates available:**

```text
TASK [obsidian : Display container status]
ok: [firefly] => {
    "msg": "obsidian-svc:UPDATE AVAILABLE - Current: 6b0aeac82a38 | Latest: 8f9d2e4a3b1c"
}

TASK [obsidian : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: obsidian-svc"
}
```

**Output when up-to-date:**

```text
TASK [obsidian : Display container status]
ok: [firefly] => {
    "msg": "obsidian-svc:Up to date (6b0aeac82a38)"
}

TASK [obsidian : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh obsidian remove

# 2. Redeploy with latest image
./manage-svc.sh obsidian deploy

# 3. Verify new version
./svc-exec.sh obsidian verify
```

**Note**: Data in `~/obsidian-data/vaults/` persists across upgrades.

## Traefik Integration

When Traefik is deployed with `obsidian_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates: `obsidian.a0a0.org` → `firefly.a0a0.org`

2. Access via HTTPS:
   - <https://obsidian.a0a0.org:8080>

## Advanced Usage

### Custom Container Arguments

Pass additional arguments to the Obsidian container:

```yaml
obsidian_custom_args: "--disable-gpu"
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

### Multiple Vaults

Store multiple Obsidian vaults in the vaults directory:

```bash
mkdir -p ~/obsidian-data/vaults/personal
mkdir -p ~/obsidian-data/vaults/work
```

Each vault can be opened separately in the Obsidian interface.

## Troubleshooting

### Container Won't Start

Check shared memory allocation:

```bash
podman inspect obsidian-svc | jq '.[0].HostConfig.ShmSize'
# Should show: 1073741824 (1GB)
```

### Web Interface Not Loading

1. Check port availability:

```bash
ss -tlnp | grep -E '3000|3001'
```

2. Check container logs:

```bash
podman logs obsidian-svc
```

3. Verify network:

```bash
podman network inspect ct-net
```

### Permission Issues

Re-run prepare step to fix SELinux contexts and permissions:

```bash
./manage-svc.sh obsidian prepare
```

### Browser Performance Issues

Increase shared memory if experiencing slowness:

```yaml
# In quadlet_rootless.yml
shm_size: "2gb"  # Increase from default 1gb
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
obsidian_svc:
  hosts:
    podma:
      obsidian_svc_name: "obsidian-podma"
  vars:
    obsidian_port: 3002  # Avoid port conflicts
    obsidian_https_port: 3003

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml obsidian prepare
./manage-svc.sh -h podma -i inventory/podma.yml obsidian deploy
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

See [docs/Claude-new-quadlet.md](../../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- Ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- All vault data stored in plain Markdown (not encrypted)

## Links

- [Obsidian Website](https://obsidian.md)
- [LinuxServer.io Obsidian Image](https://hub.docker.com/r/linuxserver/obsidian)
- [LinuxServer.io Documentation](https://docs.linuxserver.io/images/docker-obsidian/)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs obsidian-svc`
2. Systemd logs: `journalctl --user -u obsidian-pod`
3. Verification output: `./svc-exec.sh obsidian verify`

For Obsidian application issues, consult the [official documentation](https://help.obsidian.md/).
