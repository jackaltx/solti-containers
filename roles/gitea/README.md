# Gitea Role

Deploys Gitea as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **Gitea Server** (`gitea/gitea:latest`) - Lightweight self-hosted Git service
- **PostgreSQL** (future) - Optional database backend for production

**Key Features:**

- Git hosting with unlimited repositories (public/private)
- CI/CD Actions (GitHub Actions-compatible workflows)
- Git LFS (Large File Storage) support
- SSH access on port 2222
- Pull requests, code review, issues, wikis
- Traefik SSL integration

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh gitea prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Set admin password (required)
export GITEA_ADMIN_PASSWORD="your-secure-password"

./manage-svc.sh gitea deploy
```

Deploys and starts Gitea with SQLite database.

### 3. Verify

```bash
./svc-exec.sh gitea verify
```

Runs 17 health checks including HTTP, SSH, and git operations.

### 4. Access

- **Web UI**: `http://localhost:3001`
- **Traefik SSL**: `https://git.example.com` (with Traefik deployed)
- **SSH Clone**: `ssh://git@git.example.com:2222/username/repo.git`
- **HTTPS Clone**: `https://git.example.com/username/repo.git`

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Configuration

### Environment Variables

```bash
export GITEA_ADMIN_PASSWORD="your-secure-password"  # Admin password (required)
```

### Inventory Variables

```yaml
# Required
gitea_admin_password: "{{ lookup('env', 'GITEA_ADMIN_PASSWORD') }}"
gitea_data_dir: "{{ ansible_facts.user_dir }}/gitea-data"

# Ports
gitea_port: 3001                    # HTTP port
gitea_ssh_port: 2222                # SSH port

# Container
gitea_image: "docker.io/gitea/gitea:latest"

# Application settings
gitea_app_name: "Gitea"
gitea_domain: "git.{{ domain }}"
gitea_root_url: "https://git.{{ domain }}"
gitea_disable_registration: false   # Allow self-registration
gitea_require_signin: true          # Require login to view

# Features
gitea_enable_ssh: true              # Enable SSH git access
gitea_enable_actions: true          # Enable CI/CD pipelines
gitea_enable_lfs: true              # Enable Git LFS
gitea_enable_tls: true              # Enable Traefik SSL

# Data management
gitea_delete_data: false            # Preserve data on remove
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/gitea-data/
├── config/
│   ├── app.ini          # Main configuration
│   └── gitea.env        # Environment variables
├── data/
│   ├── gitea/           # Application data
│   │   ├── gitea.db     # SQLite database
│   │   ├── sessions/    # User sessions
│   │   ├── avatars/     # User avatars
│   │   ├── attachments/ # Issue/PR attachments
│   │   └── log/         # Application logs
│   └── git/
│       ├── repositories/ # Git repositories
│       └── lfs/         # Large file storage
└── logs/                # Container logs
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status gitea-pod

# Start service
systemctl --user start gitea-pod

# Stop service
systemctl --user stop gitea-pod

# Restart service
systemctl --user restart gitea-pod

# Enable on boot
systemctl --user enable gitea-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u gitea-pod -f

# View container logs
podman logs gitea-svc

# Follow logs
podman logs -f gitea-svc

# View last 50 lines
podman logs --tail 50 gitea-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh gitea remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh gitea remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status gitea-pod

# Check container logs
podman logs gitea-svc

# Test web interface
curl -I http://localhost:3001

# Test SSH access
ssh -T -p 2222 git@localhost

# Run verification tasks
./svc-exec.sh gitea verify
```

### Git Operations

```bash
# Create test repository via web UI, then:

# HTTPS clone
git clone http://localhost:3001/gitea_admin/test-repo.git

# SSH clone
git clone ssh://git@localhost:2222/gitea_admin/test-repo.git

# Configure SSH for easier access
cat >> ~/.ssh/config <<EOF
Host git.example.com
    User git
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
EOF
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh gitea check_upgrade
```

**Output when updates available:**

```text
TASK [gitea : Display container status]
ok: [localhost] => {
    "msg": "gitea-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [gitea : Summary of upgrade status]
ok: [localhost] => {
    "msg": "UPDATES AVAILABLE for: gitea-svc"
}
```

**Output when up-to-date:**

```text
TASK [gitea : Display container status]
ok: [localhost] => {
    "msg": "gitea-svc:Up to date (abc123)"
}

TASK [gitea : Summary of upgrade status]
ok: [localhost] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Backup database (optional but recommended)
podman exec gitea-svc sqlite3 /data/gitea/gitea.db ".backup /data/gitea/gitea-backup.db"
podman cp gitea-svc:/data/gitea/gitea-backup.db ~/gitea-backup-$(date +%Y%m%d).db

# 2. Remove current deployment
./manage-svc.sh gitea remove

# 3. Redeploy with latest image
./manage-svc.sh gitea deploy

# 4. Verify new version
./svc-exec.sh gitea verify
```

**Note**: Data in `~/gitea-data/` persists across upgrades.

## Traefik Integration

When Traefik is deployed with `gitea_enable_tls: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates: `git.example.com` → `firefly.a0a0.org`

1. Access via HTTPS:
   - `https://git.example.com:8080` (web UI)
   - `ssh://git@git.example.com:2222` (SSH clone)

## Advanced Usage

### Initial Setup

After first deployment, the admin account is auto-created:

1. Access web UI: `http://localhost:3001`
2. Login credentials:
   - Username: `gitea_admin` (from inventory)
   - Password: `$GITEA_ADMIN_PASSWORD`
   - Email: `admin@example.com`

### CI/CD Actions

Deploy self-hosted runners for CI/CD workflows:

1. In Gitea UI: Settings → Actions → Runners
2. Generate runner token
3. Deploy runner container (future enhancement)

**Features:**

- GitHub Actions-compatible workflows
- Matrix builds
- Artifact storage
- Self-hosted runners

### Git LFS

Enable large file storage for repositories:

```bash
# Configure Git LFS
git lfs install

# Track large files
git lfs track "*.psd"
git lfs track "*.zip"

# Commit and push
git add .gitattributes
git commit -m "Enable Git LFS"
git push
```

**Features:**

- Large file storage (>50MB files)
- Automatic garbage collection
- Configurable retention policies

### Webhooks

Configure webhooks for external services:

```bash
# In repository settings: Settings → Webhooks
# Add webhook URL for:
- Mattermost notifications
- Discord/Slack integration
- Custom HTTP endpoints
```

### Database Backup

```bash
# Backup SQLite database
podman exec gitea-svc sqlite3 /data/gitea/gitea.db ".backup /data/gitea/gitea-backup.db"

# Copy to host
podman cp gitea-svc:/data/gitea/gitea-backup.db ~/gitea-backup-$(date +%Y%m%d).db

# Full backup (data directory)
tar -czf gitea-backup-$(date +%Y%m%d).tar.gz ~/gitea-data/

# Repositories only
tar -czf gitea-repos-$(date +%Y%m%d).tar.gz ~/gitea-data/data/git/repositories/
```

### Restore Procedure

```bash
# Stop service
./manage-svc.sh gitea remove

# Restore data directory
tar -xzf gitea-backup-20260116.tar.gz -C ~/

# Redeploy
./manage-svc.sh gitea deploy
```

## Troubleshooting

### Issue: Container Won't Start

**Problem**: Gitea pod fails to start or crashes immediately

**Detection:**

```bash
# Check pod status
podman pod ps

# Check logs
podman logs gitea-svc

# Check systemd unit
systemctl --user status gitea-pod
journalctl --user -u gitea-pod -n 50
```

**Resolution**: Check logs for specific errors, verify data directory permissions

### Issue: Database Errors

**Problem**: SQLite database corruption or integrity issues

**Detection:**

```bash
# Check database file
podman exec gitea-svc ls -la /data/gitea/gitea.db

# Run integrity check
podman exec gitea-svc sqlite3 /data/gitea/gitea.db "PRAGMA integrity_check;"
```

**Resolution**: Restore from backup or reinitialize database

### Issue: SSH Connection Fails

**Problem**: Cannot clone repositories via SSH

**Detection:**

```bash
# Verify SSH port is listening
ss -tlnp | grep 2222

# Test SSH connection
ssh -T -p 2222 git@localhost

# Expected output: "Hi there, gitea_admin! You've successfully authenticated..."
```

**Resolution**: Verify SSH keys are added in Gitea UI (Settings → SSH/GPG Keys)

### Issue: Performance Degradation

**Problem**: Slow repository operations or high resource usage

**Detection:**

```bash
# Check resource usage
podman stats gitea-svc

# Check database size
podman exec gitea-svc du -sh /data/gitea/gitea.db

# Check repository size
podman exec gitea-svc du -sh /data/git/repositories
```

**Resolution**: Consider database cleanup, repository archival, or PostgreSQL backend

### Issue: Traefik Integration Not Working

**Problem**: Cannot access Gitea via SSL domain

**Detection:**

```bash
# Verify container labels
podman inspect gitea-svc | jq '.[].Config.Labels'

# Check traefik logs
podman logs traefik-svc | grep gitea

# Verify DNS resolution
curl -H "Host: git.example.com" http://localhost
```

**Resolution**: Ensure Traefik is deployed, DNS is configured, and `gitea_enable_tls: true`

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
gitea_svc:
  hosts:
    podma:
      gitea_svc_name: "gitea-podma"
  vars:
    gitea_http_port: 3000
    gitea_ssh_port: 2222

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml gitea prepare
./manage-svc.sh -h podma -i inventory/podma.yml gitea deploy
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

**Component Architecture:**

```text
┌─────────────────┐
│   Git Clients   │
│  (HTTP/SSH)     │
└────────┬────────┘
         │
┌────────▼────────┐
│  Gitea Service  │
│  (Port 3000)    │
│  (Port 2222)    │
└────────┬────────┘
         │
┌────────▼────────┐
│    Traefik      │
│ (SSL Termination)│
└────────┬────────┘
         │
    git.a0a0.org:8080
```

See [docs/Claude-new-quadlet.md](../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Integration

### Traefik SSL Termination

Gitea automatically integrates with Traefik when deployed:

- Router: `git.example.com` → gitea-svc:3000
- Automatic Let's Encrypt certificates
- Security headers and HTTPS redirect

### Actions Runners

Deploy self-hosted runners for CI/CD:

```bash
# In Gitea UI: Settings → Actions → Runners
# Generate runner token
# Deploy runner container (future enhancement)
```

### Webhook Integration

Configure webhooks for external services:

- Mattermost notifications
- Discord/Slack integration
- Custom HTTP endpoints

## Security Considerations

### Authentication

- Password-based login (default)
- SSH key authentication for git
- 2FA support (optional)
- OAuth2 providers (future)

### Access Control

- User/Organization/Repository levels
- Branch protection rules
- Required reviews for PRs
- Deploy keys (read-only access)

### Network Security

- Localhost binding (127.0.0.1)
- Traefik SSL termination
- Internal DNS within ct-net
- No direct external exposure

## Data Management

### Backup Strategy

```bash
# Full backup (data directory)
tar -czf gitea-backup-$(date +%Y%m%d).tar.gz ~/gitea-data/

# Database only
podman exec gitea-svc sqlite3 /data/gitea/gitea.db ".backup /data/gitea/backup.db"

# Repositories only
tar -czf gitea-repos-$(date +%Y%m%d).tar.gz ~/gitea-data/data/git/repositories/
```

### Restore Procedure

```bash
# Stop service
./manage-svc.sh gitea remove

# Restore data directory
tar -xzf gitea-backup-20250106.tar.gz -C ~/

# Redeploy
./manage-svc.sh gitea deploy
```

### Data Cleanup

```bash
# Remove service but keep data (default)
./manage-svc.sh gitea remove

# Remove service AND data
# Set in inventory.yml: gitea_delete_data: true
./manage-svc.sh gitea remove
```

## Links

- [Gitea Official Documentation](https://docs.gitea.io/)
- [Gitea Actions](https://docs.gitea.io/en-us/actions/)
- [Git LFS](https://git-lfs.github.com/)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs gitea-svc`
2. Systemd logs: `journalctl --user -u gitea-pod`
3. Verification output: `./svc-exec.sh gitea verify`

For Gitea application issues, consult the [official documentation](https://docs.gitea.io/).

## Service Properties

```yaml
service_properties:
  root: "gitea"
  name: "gitea-pod"
  pod_key: "gitea.pod"
  quadlets:
    - "gitea-svc.container"
    - "gitea.pod"
  data_dir: "{{ gitea_data_dir }}"
  config_dir: "config"
  dirs:
    - { path: "", mode: "0755" }
    - { path: "config", mode: "0775" }
    - { path: "data", mode: "0775" }
    - { path: "data/gitea", mode: "0775" }
    - { path: "data/git", mode: "0775" }
    - { path: "logs", mode: "0775" }
```
