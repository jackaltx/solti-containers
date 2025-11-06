# Gitea Role

Deploys Gitea (lightweight self-hosted Git service) as a rootless Podman container using Quadlets.

## Overview

**Service**: Gitea
**Architecture**: Single container with SQLite database
**Network**: ct-net (shared container network)
**Ports**: 3001 (HTTP), 2222 (SSH)
**SSL**: Traefik integration (git.example.com)
**Features**: Git hosting, CI/CD Actions, LFS support, SSH access

## Quick Start

```bash
# Set admin password
export GITEA_ADMIN_PASSWORD="your-secure-password"

# Prepare system (one-time)
./manage-svc.sh gitea prepare

# Deploy gitea
./manage-svc.sh gitea deploy

# Verify functionality
./svc-exec.sh gitea verify
```

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Architecture

### Single Container Design
- **Container**: gitea-svc (gitea/gitea:latest)
- **Database**: SQLite (embedded, no separate container)
- **Pod**: gitea-pod (systemd managed)
- **Network**: ct-net with internal DNS

### Data Persistence
```
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

## Configuration

### Inventory Variables

**Required**:
```yaml
gitea_admin_password: "{{ lookup('env', 'GITEA_ADMIN_PASSWORD') }}"
gitea_data_dir: "{{ ansible_env.HOME }}/gitea-data"
```

**Optional**:
```yaml
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

### Environment Variables

Set before deployment:
```bash
export GITEA_ADMIN_PASSWORD="your-secure-password"
```

## Access Methods

### Web Interface
- **Local**: http://localhost:3001
- **Traefik**: https://git.example.com (with SSL)

### Git Operations

**HTTPS Clone**:
```bash
git clone https://git.example.com/username/repo.git
```

**SSH Clone** (port 2222):
```bash
git clone ssh://git@git.example.com:2222/username/repo.git
```

**Configure SSH**:
```bash
# Add to ~/.ssh/config
Host git.example.com
    User git
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

## Features

### Git Hosting
- Unlimited repositories (public/private)
- Organization support
- Branch protection rules
- Pull requests with code review
- Issues and wikis

### CI/CD Actions
- GitHub Actions-compatible workflows
- Self-hosted runners
- Matrix builds
- Artifact storage

### Git LFS
- Large file storage (>50MB files)
- Automatic garbage collection
- Configurable retention policies

### SSH Access
- Key-based authentication
- Multiple keys per user
- Port 2222 (doesn't conflict with system SSH)

## Initial Setup

After deployment, create the admin account:

1. Access web UI: http://localhost:3001
2. Initial setup will auto-create admin user:
   - Username: `gitea_admin` (from inventory)
   - Password: `$GITEA_ADMIN_PASSWORD`
   - Email: `admin@example.com`

## Operations

### Start/Stop Service
```bash
systemctl --user start gitea-pod
systemctl --user stop gitea-pod
systemctl --user restart gitea-pod
```

### View Logs
```bash
# Container logs
podman logs gitea-svc

# Follow logs
podman logs -f gitea-svc

# Systemd journal
journalctl --user -u gitea-pod -f
```

### Check Status
```bash
# Service status
systemctl --user status gitea-pod

# Container status
podman ps --filter "pod=gitea"

# Resource usage
podman stats gitea-svc
```

### Database Backup
```bash
# Backup SQLite database
podman exec gitea-svc sqlite3 /data/gitea/gitea.db ".backup /data/gitea/gitea-backup.db"

# Copy to host
podman cp gitea-svc:/data/gitea/gitea-backup.db ~/gitea-backup-$(date +%Y%m%d).db
```

### Upgrade Gitea
```bash
# Pull latest image
podman pull docker.io/gitea/gitea:latest

# Redeploy (data preserved)
./manage-svc.sh gitea remove
./manage-svc.sh gitea deploy
```

## Troubleshooting

### Container Won't Start
```bash
# Check pod status
podman pod ps

# Check logs
podman logs gitea-svc

# Check systemd unit
systemctl --user status gitea-pod
journalctl --user -u gitea-pod -n 50
```

### Database Errors
```bash
# Check database file
podman exec gitea-svc ls -la /data/gitea/gitea.db

# Run integrity check
podman exec gitea-svc sqlite3 /data/gitea/gitea.db "PRAGMA integrity_check;"
```

### SSH Connection Issues
```bash
# Verify SSH port is listening
ss -tlnp | grep 2222

# Test SSH connection
ssh -T -p 2222 git@localhost

# Check SSH keys in gitea UI
# Settings → SSH/GPG Keys
```

### Performance Issues
```bash
# Check resource usage
podman stats gitea-svc

# Check database size
podman exec gitea-svc du -sh /data/gitea/gitea.db

# Check repository size
podman exec gitea-svc du -sh /data/git/repositories
```

### Traefik Integration Not Working
```bash
# Verify container labels
podman inspect gitea-svc | jq '.[].Config.Labels'

# Check traefik logs
podman logs traefik-svc | grep gitea

# Verify DNS resolution
curl -H "Host: git.example.com" http://localhost
```

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

## Security

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

## References

- [Gitea Documentation](https://docs.gitea.io/)
- [Gitea Actions](https://docs.gitea.io/en-us/actions/)
- [Git LFS](https://git-lfs.github.com/)
- [Container-Role-Architecture.md](../../Container-Role-Architecture.md)

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
