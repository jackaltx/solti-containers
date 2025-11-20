# Mattermost Role - Team Communication Platform

## Purpose

Mattermost provides a private team communication platform ideal for collecting notifications, test results, and debugging information during development. This deployment includes PostgreSQL database and is perfect for creating dedicated channels for automated reporting and team coordination.

## Quick Start

```bash
# Set required database password
export MM_DB_PASSWORD="your_secure_db_password"

# Prepare system directories and configuration
./manage-svc.sh mattermost prepare

# Deploy Mattermost with PostgreSQL
./manage-svc.sh mattermost deploy

# Initialize admin user and lock down registration
./svc-exec.sh mattermost initialize-mattermost

# Verify deployment and security settings
./svc-exec.sh mattermost verify

# Verify user configuration
./svc-exec.sh mattermost verify-user

# Verify security configuration
./svc-exec.sh mattermost verify-security

# Clean up (preserves data by default)
./manage-svc.sh mattermost remove
```

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Features

- **Private Communication**: Self-hosted team messaging platform
- **PostgreSQL Integration**: Dedicated database for data persistence
- **Admin User Creation**: Automated admin account setup
- **Security Lockdown**: Automatic registration disabling after setup
- **SSL Integration**: Automatic HTTPS via Traefik
- **Mobile/Desktop Apps**: Native client support
- **Webhook Integration**: Perfect for automated notifications

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Your Apps     │───▶│   Mattermost     │◀───│   PostgreSQL DB     │
│   (Webhooks)    │    │   Web (8065)     │    │   (Internal)        │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                              │                           │
                              └───────────────────────────┘
                                           │
                              ┌──────────────────────┐
                              │       Traefik        │
                              │   (SSL Termination)  │
                              └──────────────────────┘
                                           │
                              https://mattermost.yourdomain.com
```

## Access Points

| Interface | URL | Purpose |
|-----------|-----|---------|
| Mattermost Web | `http://localhost:8065` | Local web interface |
| SSL Endpoint | `https://mattermost.{{ domain }}` | Traefik-proxied HTTPS access |
| PostgreSQL | `internal:5432` | Database (pod-internal only) |

## Configuration

### Required Environment Variables

```bash
# Database password (required)
export MM_DB_PASSWORD="your_secure_database_password"

# Optional: Admin user configuration
export MM_USER="admin"
export MM_PASSWORD="your_admin_password"
```

### Key Configuration Options

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

### Optional TLS Configuration

```yaml
# Enable TLS for direct access (in addition to Traefik SSL)
mattermost_enable_tls: true
mattermost_tls_cert_file: "/path/to/cert.pem"
mattermost_tls_key_file: "/path/to/key.pem"
```

## Using with Traefik SSL

Mattermost automatically integrates with Traefik for SSL termination:

```yaml
# Traefik labels automatically applied
- "Label=traefik.http.routers.mattermost.rule=Host(`mattermost.{{ domain }}`)"
- "Label=traefik.http.services.mattermost.loadbalancer.server.port=8065"
```

**Result**: Access Mattermost securely at `https://mattermost.yourdomain.com`

## Security Initialization

### Admin User Creation and Lockdown

```bash
# Initialize with admin user and disable public registration
./svc-exec.sh mattermost initialize
```

This process:

1. Creates first admin user (becomes system admin automatically)
2. Disables user registration for security
3. Disables open server mode
4. Updates configuration to prevent unauthorized access

### Security Verification

```bash
# Verify security settings are properly configured
./svc-exec.sh mattermost verify-security
```

Tests performed:

- Confirms user registration is disabled
- Verifies open server mode is disabled
- Tests that unauthenticated users cannot create accounts
- Confirms admin user can still create users
- Validates API security settings

## Common Operations

### Verification and Testing

```bash
# Basic health and functionality check
./svc-exec.sh mattermost verify

# Test with user creation and security validation
./svc-exec.sh mattermost verify-user

# Comprehensive security audit
./svc-exec.sh mattermost verify-security
```

### User Management

```bash
# Access via web interface at https://mattermost.yourdomain.com
# Or use the API:

# Create additional users (admin only)
curl -X POST https://mattermost.yourdomain.com/api/v4/users \
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
curl -X POST https://mattermost.yourdomain.com/api/v4/teams \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "development",
    "display_name": "Development Team",
    "type": "O"
  }'
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
```

## Integration Examples

### Webhook Notifications

```python
import requests

def send_notification(message, channel="testing"):
    webhook_url = "https://mattermost.yourdomain.com/hooks/your_webhook_id"
    
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

```bash
# Send build notifications
curl -X POST https://mattermost.yourdomain.com/hooks/your_webhook_id \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "ci-cd",
    "username": "BuildBot",
    "text": "🚀 Deployment to staging completed successfully",
    "attachments": [{
      "color": "good",
      "fields": [{
        "title": "Build",
        "value": "'$BUILD_NUMBER'",
        "short": true
      }, {
        "title": "Duration",
        "value": "'$BUILD_DURATION's",
        "short": true
      }]
    }]
  }'
```

### API Client Example

```python
from mattermostdriver import Driver

# Connect to Mattermost
mm = Driver({
    'url': 'https://mattermost.yourdomain.com',
    'login_id': 'admin@example.com',
    'password': 'your_admin_password',
    'scheme': 'https',
    'verify': False  # For development
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

## Development Workflows

### Development Communication Setup

```bash
# Deploy for team communication
export MM_DB_PASSWORD="dev_secure_password"
./manage-svc.sh mattermost deploy
./svc-exec.sh mattermost initialize

# Create development channels
# - Access web interface at https://mattermost.yourdomain.com
# - Create channels: #general, #development, #testing, #alerts

# Set up webhooks for automated notifications
# - Go to Integrations > Incoming Webhooks
# - Create webhooks for each notification type
```

### Testing Notification Systems

```bash
# Deploy test instance
./manage-svc.sh mattermost deploy
./svc-exec.sh mattermost initialize

# Test webhook integration
curl -X POST http://localhost:8065/hooks/webhook_id \
  -H "Content-Type: application/json" \
  -d '{"text": "Test notification from development"}'

# Clean up
./manage-svc.sh mattermost remove
```

## Monitoring and Maintenance

### Health Monitoring

```bash
# Container status
systemctl --user status mattermost-pod

# Resource usage
podman stats mattermost-svc mattermost-db

# Mattermost system status
curl https://mattermost.yourdomain.com/api/v4/system/ping
```

### Log Analysis

```bash
# Mattermost application logs
podman logs mattermost-svc | grep -i error

# PostgreSQL logs
podman logs mattermost-db

# Real-time monitoring
podman logs -f mattermost-svc
```

### Performance Tuning

```bash
# Database performance
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost -c "SELECT * FROM pg_stat_activity;"

# Check slow queries
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 5;"
```

## Troubleshooting

### Common Issues

**Database Connection Errors**

```bash
# Check PostgreSQL is running
podman ps | grep mattermost-db

# Test database connectivity
podman exec -e PGPASSWORD="$MM_DB_PASSWORD" mattermost-db \
  psql -U mmuser -d mattermost -c "SELECT version();"
```

**Configuration Issues**

```bash
# Check Mattermost configuration
podman exec mattermost-svc cat /mattermost/config/config.json

# Restart with new configuration
systemctl --user restart mattermost-pod
```

**Permission Problems**

```bash
# Check data directory permissions
ls -la ~/mattermost-data/

# Fix SELinux contexts (RHEL/CentOS)
sudo restorecon -Rv ~/mattermost-data/
```

### Security Troubleshooting

```bash
# Verify security settings
./svc-exec.sh mattermost verify-security

# Check user registration status
curl https://mattermost.yourdomain.com/api/v4/users \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "username": "testuser", "password": "password"}'
# Should return 501 (Not Implemented) if properly secured
```

## Security Best Practices

1. **Strong Passwords**: Set secure database and admin passwords
2. **Registration Lockdown**: Always run initialization to disable public registration
3. **HTTPS Only**: Use Traefik SSL termination for production access
4. **Regular Backups**: Backup PostgreSQL database regularly
5. **Update Management**: Keep Mattermost image updated for security patches

## Related Services

- **HashiVault**: Can store Mattermost database passwords and API tokens
- **Traefik**: Provides SSL termination and routing
- **Redis**: Can be used for session storage and caching
- **Elasticsearch**: Can index Mattermost messages for search

## License

MIT

## Maintained By

Jackaltx - Part of the SOLTI containers collection for development testing workflows.
