# Mattermost Role

Deploys Mattermost team communication platform with PostgreSQL as rootless Podman containers using the quadlet pattern.

## Overview

This role deploys:

- **Mattermost Team Edition** (`docker.io/mattermost/mattermost-team-edition:latest`) - Team communication platform
- **PostgreSQL** (`postgres:16-alpine`) - Dedicated database backend

## Features

- **Private Team Communication**: Self-hosted messaging platform
- **PostgreSQL Integration**: Dedicated database for data persistence
- **Automated Admin Setup**: Admin user creation and security lockdown
- **Security Hardening**: Registration disabled after initialization
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management
- **Traefik Support**: Optional SSL termination and reverse proxy
- **Webhook Integration**: Perfect for CI/CD notifications and automated reporting
- **Mobile/Desktop Apps**: Native client support

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role

## Quick Start

### 1. Prepare (one-time setup)

```bash
# Set required environment variables
export MM_DB_PASSWORD="your_secure_db_password"
export MM_USER="admin"
export MM_PASSWORD="your_admin_password"

./manage-svc.sh mattermost prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
./manage-svc.sh mattermost deploy
```

Deploys and starts PostgreSQL and Mattermost containers.

### 3. Verify

```bash
# Initialize admin user and lock down registration
./svc-exec.sh mattermost initialize-mattermost

# Verify deployment and security settings
./svc-exec.sh mattermost verify

# Verify user configuration
./svc-exec.sh mattermost verify-user

# Verify security lockdown
./svc-exec.sh mattermost verify-security
```

Runs health checks, creates admin user, and validates security configuration.

### 4. Access

- **Mattermost Web**: `http://localhost:8065`
- **With Traefik SSL**: `https://mattermost.example.com`
- **PostgreSQL**: Internal pod network only (port 5432)

## Configuration

### Environment Variables

```bash
# Database password (required for deploy)
export MM_DB_PASSWORD="your_secure_database_password"

# Admin user configuration (required for initialize-mattermost task)
export MM_USER="admin"                    # Admin username (default: admin)
export MM_PASSWORD="your_admin_password"  # Admin password (default: changemeplease)
```

All three variables should be set before running `initialize-mattermost`. Defaults are insecure and not recommended.

### Inventory Variables

```yaml
# Database settings
mattermost_postgres_password: "{{ lookup('env', 'MM_DB_PASSWORD') }}"
mattermost_db_name: "mattermost"
mattermost_db_user: "mmuser"

# Application settings
mattermost_port: 8065
mattermost_site_url: "http://localhost:{{ mattermost_port }}"
mattermost_site_name: "Mattermost"

# Admin user creation
mattermost_admin_email: "admin@{{ domain }}"
mattermost_admin_username: "{{ lookup('env', 'MM_USER') | default('admin') }}"
mattermost_admin_password: "{{ lookup('env', 'MM_PASSWORD') | default('changemeplease') }}"

# Security settings
mattermost_enable_user_creation: true   # Disabled after initialization
mattermost_enable_open_server: true     # Disabled after initialization

# Data persistence
mattermost_data_dir: "{{ ansible_facts.user_dir }}/mattermost-data"
```

See [defaults/main.yml](defaults/main.yml) for complete options.

### Optional TLS Configuration

```yaml
# Enable TLS for direct access (in addition to Traefik SSL)
mattermost_enable_tls: true
mattermost_tls_cert_file: "/path/to/cert.pem"
mattermost_tls_key_file: "/path/to/key.pem"
```

## Directory Structure

After deployment:

```text
~/mattermost-data/
├── config/          # Mattermost configuration (config.json)
├── data/            # Application data (uploads, plugins, etc.)
├── logs/            # Mattermost server logs
├── plugins/         # Installed plugins
└── db-data/         # PostgreSQL database files
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status mattermost-pod

# Start service
systemctl --user start mattermost-pod

# Stop service
systemctl --user stop mattermost-pod

# Restart service
systemctl --user restart mattermost-pod

# Enable on boot
systemctl --user enable mattermost-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u mattermost-pod -f

# View Mattermost container logs
podman logs mattermost-svc

# View PostgreSQL logs
podman logs mattermost-db

# View last 50 lines
podman logs --tail 50 mattermost-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh mattermost remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh mattermost remove
```

**Warning**: `DELETE_DATA=true` permanently destroys all channels, messages, users, and configuration.

## Verification

Mattermost provides three levels of verification:

### Basic Health Check

```bash
# Health and connectivity tests
./svc-exec.sh mattermost verify
```

Validates:

- Service running
- HTTP endpoint responding
- Database connectivity
- API accessibility

### User Verification

```bash
# Test user creation and authentication
./svc-exec.sh mattermost verify-user
```

Validates:

- Admin user exists
- User creation works
- Authentication succeeds
- API token generation

### Security Verification

```bash
# Comprehensive security audit
./svc-exec.sh mattermost verify-security
```

Validates:

- User registration disabled
- Open server mode disabled
- Unauthenticated access blocked
- Admin privileges working
- API security configured

### Manual Verification

```bash
# Check service status
systemctl --user status mattermost-pod

# Test API connectivity
curl http://localhost:8065/api/v4/system/ping

# Verify database
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost -c "SELECT version();"
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image versions are available
./svc-exec.sh mattermost check_upgrade
```

**Output when updates available:**

```text
TASK [mattermost : Display container status]
ok: [firefly] => {
    "msg": "mattermost-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}
ok: [firefly] => {
    "msg": "mattermost-db:UPDATE AVAILABLE - Current: xyz789 | Latest: uvw101"
}

TASK [mattermost : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: mattermost-svc, mattermost-db"
}
```

**Output when up-to-date:**

```text
TASK [mattermost : Display container status]
ok: [firefly] => {
    "msg": "mattermost-svc:Up to date (abc123)"
}
ok: [firefly] => {
    "msg": "mattermost-db:Up to date (xyz789)"
}

TASK [mattermost : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Backup database (recommended)
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  pg_dump -U mmuser mattermost > mattermost_backup_$(date +%Y%m%d).sql

# 2. Remove current deployment
./manage-svc.sh mattermost remove

# 3. Redeploy with latest images
./manage-svc.sh mattermost deploy

# 4. Verify new version
./svc-exec.sh mattermost verify
```

**Note**: Data in `~/mattermost-data/` persists across upgrades. Admin user already exists, no need to re-run initialize.

## Traefik Integration

When Traefik is deployed, Mattermost automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates: `mattermost.example.com` → `firefly.example.com`

1. Access via HTTPS:
   - `https://mattermost.example.com`

### Automatic Configuration

Traefik labels automatically applied:

```yaml
- "Label=traefik.http.routers.mattermost.rule=Host(`mattermost.{{ domain }}`)"
- "Label=traefik.http.services.mattermost.loadbalancer.server.port=8065"
```

## Advanced Usage

### Webhook Notifications

Create incoming webhooks for automated notifications:

```python
import requests

def send_notification(message, channel="testing"):
    webhook_url = "https://mattermost.example.com/hooks/your_webhook_id"

    payload = {
        "channel": channel,
        "username": "TestBot",
        "text": message,
        "icon_emoji": ":robot_face:"
    }

    response = requests.post(webhook_url, json=payload)
    return response.status_code == 200

# Send test results
send_notification("✅ All tests passed in build #123", "ci-cd")
send_notification("❌ Test failure in authentication module", "alerts")
```

### CI/CD Integration

Send build notifications with formatted attachments:

```bash
curl -X POST https://mattermost.example.com/hooks/your_webhook_id \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "ci-cd",
    "username": "BuildBot",
    "text": "🚀 Deployment to staging completed successfully",
    "attachments": [{
      "color": "good",
      "fields": [{
        "title": "Build",
        "value": "'"$BUILD_NUMBER"'",
        "short": true
      }, {
        "title": "Duration",
        "value": "'"$BUILD_DURATION"'s",
        "short": true
      }]
    }]
  }'
```

### API Client Example

Python client for programmatic access:

```python
from mattermostdriver import Driver

# Connect to Mattermost
mm = Driver({
    'url': 'https://mattermost.example.com',
    'login_id': 'admin@example.com',
    'password': 'your_admin_password',
    'scheme': 'https',
    'verify': True
})

mm.login()

# Create a channel
channel = mm.channels.create_channel({
    'team_id': 'your_team_id',
    'name': 'test-results',
    'display_name': 'Test Results',
    'type': 'O'  # Open channel
})

# Post a message
mm.posts.create_post({
    'channel_id': channel['id'],
    'message': 'Test automation results are in!'
})
```

### Database Operations

```bash
# Connect to PostgreSQL
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost

# Backup database
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  pg_dump -U mmuser mattermost > mattermost_backup.sql

# Check database size
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost -c "SELECT pg_size_pretty(pg_database_size('mattermost'));"

# Check slow queries
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 5;"
```

### User Management

```bash
# Create additional users (admin only)
curl -X POST https://mattermost.example.com/api/v4/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "username": "newuser",
    "password": "secure_password",
    "first_name": "New",
    "last_name": "User"
  }'

# Create teams
curl -X POST https://mattermost.example.com/api/v4/teams \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "development",
    "display_name": "Development Team",
    "type": "O"
  }'
```

## Troubleshooting

### Issue: Database Connection Errors

**Problem**: Mattermost cannot connect to PostgreSQL

**Detection**:

```bash
# Check PostgreSQL is running
podman ps | grep mattermost-db

# Check logs for connection errors
podman logs mattermost-svc | grep -i "database"
```

**Resolution**: Ensure PostgreSQL is healthy and credentials match

```bash
# Test database connectivity
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost -c "SELECT version();"

# Restart pod if needed
systemctl --user restart mattermost-pod
```

### Issue: Cannot Create Admin User

**Problem**: initialize-mattermost fails with user already exists

**Detection**:

```bash
# Check if admin user exists
./svc-exec.sh mattermost verify-user
```

**Resolution**: Admin user already created, skip initialization

```bash
# Reset admin password if forgotten
podman exec mattermost-svc mattermost user password admin new_password
```

### Issue: Registration Not Disabled

**Problem**: Public registration still enabled after initialization

**Detection**:

```bash
# Test registration endpoint
curl -X POST http://localhost:8065/api/v4/users \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "username": "testuser", "password": "password"}'
# Should return 501 (Not Implemented) if properly secured
```

**Resolution**: Re-run security initialization

```bash
./svc-exec.sh mattermost initialize-mattermost
./svc-exec.sh mattermost verify-security
```

### Issue: Configuration Not Persisting

**Problem**: Configuration changes lost after restart

**Detection**:

```bash
# Check if config file exists
ls -la ~/mattermost-data/config/config.json
```

**Resolution**: Ensure configuration directory is mounted and writable

```bash
# Check data directory permissions
ls -la ~/mattermost-data/

# Fix SELinux contexts (RHEL/CentOS)
sudo restorecon -Rv ~/mattermost-data/

# Restart service
systemctl --user restart mattermost-pod
```

### Issue: Permission Denied Errors

**Problem**: Cannot write to data directories

**Detection**:

```bash
# Check container logs
podman logs mattermost-svc | grep -i "permission"

# Check directory ownership
ls -lan ~/mattermost-data/
```

**Resolution**: Fix directory permissions

```bash
# Prepare task creates correct permissions
./manage-svc.sh mattermost prepare

# Manual fix if needed
chmod -R u+rwX ~/mattermost-data/
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
mattermost_svc:
  hosts:
    podma:
      mattermost_svc_name: "mattermost-podma"
  vars:
    mattermost_port: 8065

# Set environment variables
export MM_DB_PASSWORD="your_secure_db_password"
export MM_USER="admin"
export MM_PASSWORD="your_admin_password"

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml mattermost prepare
./manage-svc.sh -h podma -i inventory/podma.yml mattermost deploy
./svc-exec.sh -h podma -i inventory/podma.yml mattermost initialize-mattermost
./svc-exec.sh -h podma -i inventory/podma.yml mattermost verify
```

**Multi-Host Considerations**:

- Use unique service names to avoid conflicts
- Ensure ports don't conflict (default 8065)
- PostgreSQL is pod-internal, no port conflicts
- Each host gets independent database and data

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **Multi-container pod**: Mattermost + PostgreSQL in shared pod network
4. **State-based flow**: prepare → present → absent
5. **Security-first**: Admin creation and lockdown after deployment

**Component Architecture**:

```text
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Your Apps     │───▶│   Mattermost     │◀───│   PostgreSQL DB     │
│   (Webhooks)    │    │   Web (8065)     │    │   (Internal:5432)   │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                              │                           │
                              └───────────────────────────┘
                                           │
                              ┌──────────────────────┐
                              │       Traefik        │
                              │   (SSL Termination)  │
                              └──────────────────────┘
                                           │
                              https://mattermost.example.com
```

**Key Components**:

- **Mattermost**: Team communication frontend
- **PostgreSQL**: Database backend (pod-internal)
- **Shared Pod Network**: Containers communicate via pod networking
- **Traefik**: Optional SSL termination and routing

See [docs/Container-Role-Architecture.md](../../docs/Container-Role-Architecture.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- Mattermost port binds to `127.0.0.1` only (not publicly accessible)
- PostgreSQL accessible only within pod network (no external port)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- Admin user created with strong password (via environment variable)
- Public registration disabled after initialization
- Open server mode disabled after initialization
- Database credentials stored in environment variables

**Security Best Practices**:

1. Set strong `MM_DB_PASSWORD` before deployment
2. Set strong `MM_PASSWORD` for admin user
3. Always run `initialize-mattermost` to lock down registration
4. Use Traefik SSL for production access
5. Backup database regularly
6. Keep container images updated

## Links

- [Mattermost Official Documentation](https://docs.mattermost.com/)
- [Mattermost Docker Hub Image](https://hub.docker.com/r/mattermost/mattermost-team-edition)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Mattermost API Reference](https://api.mattermost.com/)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs mattermost-svc` and `podman logs mattermost-db`
2. Systemd logs: `journalctl --user -u mattermost-pod`
3. Verification output: `./svc-exec.sh mattermost verify`
4. Security verification: `./svc-exec.sh mattermost verify-security`

For Mattermost application issues, consult the [official documentation](https://docs.mattermost.com/).

## Related Services

- **PostgreSQL**: Bundled database backend
- **Traefik**: Provides SSL termination and routing
- **HashiVault**: Can store Mattermost database passwords and API tokens
- **Redis**: Can be used for session storage and caching
- **Elasticsearch**: Can index Mattermost messages for advanced search
