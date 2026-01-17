# InfluxDB3 Role

Deploys InfluxDB 3 Core as a rootless Podman container with token-based authentication and optional Traefik SSL termination.

## Overview

This role deploys:

- **InfluxDB 3 Core** (`docker.io/influxdata/influxdb:3-core`) - Modern time-series database with Apache Arrow/Parquet storage
- **Port**: 8087 (HTTP API, changed from default 8181 to avoid Redis conflict)
- **Auth**: Token-only (no username/password)
- **Storage**: Apache Arrow/Parquet format (not compatible with InfluxDB v2)

## Features

- **Token-Based Authentication**: Operator and resource tokens instead of user accounts
- **Modern Storage Engine**: Parquet files for efficient compression and queries
- **v1 API Compatibility**: Legacy endpoints for backward compatibility
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management via quadlets
- **Traefik Support**: Optional SSL termination and reverse proxy
- **Upgrade Detection**: Built-in check for image updates

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh influxdb3 prepare
```

Creates directories (`~/influxdb3-data/config/`, `data/`, `plugins/`), applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
./manage-svc.sh influxdb3 deploy
```

Deploys container, creates operator (admin) token, saves to `~/.secrets/influxdb3-secrets/admin-token.json`, and runs health checks.

### 3. Configure

```bash
./svc-exec.sh influxdb3 configure
```

Creates databases and resource tokens from inventory definitions. Saves tokens to `./data/influxdb3-tokens-<hostname>.yml`.

### 4. Verify

```bash
./svc-exec.sh influxdb3 verify
```

Runs health checks, tests database creation, and validates write/query operations.

### 5. Access

- **Local HTTP API**: `http://127.0.0.1:8087`
- **Health endpoint**: `http://127.0.0.1:8087/health`
- **With Traefik SSL**: `https://influxdb3.a0a0.org:8080`
- **v3 Write API**: `http://127.0.0.1:8087/api/v3/write?db=DATABASE`
- **v3 Query API**: `http://127.0.0.1:8087/api/v3/query?db=DATABASE&q=QUERY`

## Configuration

### Inventory Variables

```yaml
influxdb3_svc:
  hosts:
    firefly:
  vars:
    influxdb3_port: 8087                    # Host port (configurable)
    influxdb3_data_dir: "~/influxdb3-data"  # Data directory

    # Databases to create
    influxdb3_databases:
      - name: "telegraf"
      - name: "metrics"

    # Tokens to create (these act like "users")
    influxdb3_tokens:
      - description: "telegraf-writer"
        permissions: "database:telegraf:write"
      - description: "grafana-reader"
        permissions: "database:*:read"

    # Traefik integration
    influxdb3_enable_traefik: false
```

See [defaults/main.yml](defaults/main.yml) for complete options.

### Token Permissions Format

```text
database:DATABASE_NAME:ACTIONS
```

**Examples:**

- `database:telegraf:write` - Write-only to telegraf database
- `database:metrics:read` - Read-only to metrics database
- `database:logs:write,read` - Read/write to logs database
- `database:*:read` - Read-only to ALL databases

**Note**: InfluxDB 3 Core has NO user accounts - only tokens with descriptions and permissions.

## Directory Structure

After deployment:

```text
~/influxdb3-data/
├── config/          # Configuration files (currently unused)
├── data/            # Parquet files (persistent storage)
└── plugins/         # Plugin directory (currently unused)
```

Token storage locations:

```text
~/.secrets/influxdb3-secrets/
└── admin-token.json                    # Operator (admin) token

./data/
└── influxdb3-tokens-<hostname>.yml     # Resource tokens
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status influxdb3-pod

# Start service
systemctl --user start influxdb3-pod

# Stop service
systemctl --user stop influxdb3-pod

# Restart service
systemctl --user restart influxdb3-pod

# Enable on boot
systemctl --user enable influxdb3-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u influxdb3-pod -f

# View container logs
podman logs influxdb3-svc

# View last 50 lines
podman logs --tail 50 influxdb3-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh influxdb3 remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh influxdb3 remove
```

**Warning**: `DELETE_DATA=true` permanently destroys all databases, tokens, and time-series data.

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status influxdb3-pod

# Check container logs
podman logs influxdb3-svc

# Health check
curl http://127.0.0.1:8087/health

# Verify operator token
cat ~/.secrets/influxdb3-secrets/admin-token.json | jq .

# Run verification tasks
./svc-exec.sh influxdb3 verify
```

### Data Operations

```bash
# Inside container (primary for configuration)
podman exec influxdb3-svc influxdb3 create token --admin
podman exec -e INFLUXDB3_AUTH_TOKEN=${TOKEN} influxdb3-svc influxdb3 create database mydb

# Localhost HTTP access (testing)
TOKEN=$(jq -r '.token' ~/.secrets/influxdb3-secrets/admin-token.json)

# Write data (v3 API)
curl -X POST "http://127.0.0.1:8087/api/v3/write?db=telegraf" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "cpu,host=server01 usage=23.5"

# Query data
curl "http://127.0.0.1:8087/api/v3/query?db=telegraf&q=SELECT * FROM cpu" \
  -H "Authorization: Bearer ${TOKEN}"

# v1 API compatibility (username ignored, password=token)
curl --user "ignored:${TOKEN}" \
  "http://127.0.0.1:8087/write?db=telegraf" \
  --data-binary "cpu,host=server01 value=23.5"
```

### Resource Usage

```bash
# Monitor container resources
podman stats influxdb3-svc

# Check disk usage
du -sh ~/influxdb3-data/data/
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh influxdb3 check_upgrade
```

**Output when updates available:**

```text
TASK [influxdb3 : Display container status]
ok: [firefly] => {
    "msg": "influxdb3-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [influxdb3 : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: influxdb3-svc"
}
```

**Output when up-to-date:**

```text
TASK [influxdb3 : Display container status]
ok: [firefly] => {
    "msg": "influxdb3-svc:Up to date (abc123)"
}

TASK [influxdb3 : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh influxdb3 remove

# 2. Redeploy with latest image
./manage-svc.sh influxdb3 deploy

# 3. Reconfigure (databases and tokens)
./svc-exec.sh influxdb3 configure

# 4. Verify new version
./svc-exec.sh influxdb3 verify
```

**Note**: Data in `~/influxdb3-data/data/` persists across upgrades. Tokens must be recreated.

### Full Redeploy

Complete removal and fresh installation with latest images. Useful for testing, upgrades, or recovering from corruption.

```bash
# Step 1: Complete removal (data + images)
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh influxdb3 remove

# Step 2: Prepare system
./manage-svc.sh influxdb3 prepare

# Step 3: Deploy with fresh image
./manage-svc.sh influxdb3 deploy

# Step 4: Configure databases and tokens
./svc-exec.sh influxdb3 configure

# Step 5: Verify deployment
./svc-exec.sh influxdb3 verify
```

**What this does**:

- **Step 1**: Removes service, data directories, AND container images
- **Step 2**: Creates fresh directory structure with proper permissions
- **Step 3**: Pulls latest container image, deploys service, creates admin token
- **Step 4**: Creates databases and resource tokens from inventory
- **Step 5**: Validates deployment (health checks, write/query tests)

**Expected results**:

- Fresh `docker.io/influxdata/influxdb:3-core` image pulled
- Clean databases with no existing data
- New admin token saved to `~/.secrets/influxdb3-secrets/admin-token.json`
- Resource tokens saved to `./data/influxdb3-tokens-*.yml`
- All verification tests pass
- Service accessible at `http://127.0.0.1:8087`

## Traefik Integration

When Traefik is deployed with `influxdb3_enable_traefik: true`, the service automatically gets SSL termination.

### Automatic SSL Configuration

The container gets:

- SSL termination via Traefik
- Let's Encrypt certificate
- HTTPS access at `https://influxdb3.{{ domain }}:8080`

### Traefik Labels

Automatically applied to container:

```yaml
traefik.enable=true
traefik.http.routers.influxdb3.rule=Host(`influxdb3.{{ domain }}`)
traefik.http.routers.influxdb3.entrypoints=websecure
traefik.http.services.influxdb3.loadbalancer.server.port=8087
```

### External Access

```bash
# HTTPS only (port 8080)
TOKEN=$(jq -r '.token' ~/.secrets/influxdb3-secrets/admin-token.json)
curl https://influxdb3.a0a0.org:8080/health

# Write via SSL
curl -X POST "https://influxdb3.a0a0.org:8080/api/v3/write?db=telegraf" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "cpu,host=server01 usage=23.5"
```

## Advanced Usage

### Token Management

**Understanding Tokens vs Users:**

InfluxDB 3 Core has NO user accounts - only tokens with descriptions.

| v2 Concept | v3 Core Equivalent |
|------------|-------------------|
| Admin user with password | Operator token (`--admin`) |
| User "telegraf" | Token with description "telegraf-writer" |
| User permissions | Token permissions |

**Operator Token Location:**

```bash
~/.secrets/influxdb3-secrets/admin-token.json
```

**Important**: This token has full admin access. Store securely.

**Resource Tokens Location:**

```bash
./data/influxdb3-tokens-<hostname>.yml
```

Contains all created tokens with their permissions.

**Re-run Configuration:**

```bash
# Safe to run multiple times (idempotent)
./svc-exec.sh influxdb3 configure
```

### Port Configuration

**Default Port:**

```yaml
influxdb3_port: 8087  # Localhost binding
```

**Check for Conflicts:**

```bash
ss -tulpn | grep :8087
```

**Override in Inventory:**

```yaml
influxdb3_svc:
  hosts:
    firefly:
      influxdb3_port: 8182  # Use different port
```

**Known Port Conflicts:**

- 8081 - Redis Commander (in use)
- 8080 - Traefik HTTPS (in use)
- 8181 - InfluxDB3 default (conflicts with Redis)
- 8200 - HashiVault (in use)
- 9200 - Elasticsearch (in use)

### Data Persistence

**Location:**

```bash
~/influxdb3-data/data/
```

**Backup:**

```bash
# Stop service
systemctl --user stop influxdb3-pod

# Backup data
tar -czf influxdb3-backup-$(date +%Y%m%d).tar.gz ~/influxdb3-data/data/

# Restart service
systemctl --user start influxdb3-pod
```

**Clean Removal:**

```yaml
# Set in inventory.yml
influxdb3_delete_data: true
```

```bash
# Then remove
./manage-svc.sh influxdb3 remove
```

## Troubleshooting

### Issue: Service Won't Start

**Problem**: Pod fails to start or crashes immediately

**Detection:**

```bash
systemctl --user status influxdb3-pod
journalctl --user -u influxdb3-pod -f
```

**Resolution**: Check container logs for errors

```bash
podman logs influxdb3-svc
```

### Issue: Health Check Fails

**Problem**: `curl http://127.0.0.1:8087/health` returns connection refused

**Detection:**

```bash
# Check if container is running
podman ps | grep influxdb3

# Check port binding
ss -tlnp | grep 8087
```

**Resolution**: Ensure container is running and port is correctly bound

```bash
systemctl --user status influxdb3-pod
podman logs influxdb3-svc
```

### Issue: Invalid Token

**Problem**: API requests return 401 Unauthorized

**Detection:**

```bash
# Verify token exists
cat ~/.secrets/influxdb3-secrets/admin-token.json | jq .

# Test token
TOKEN=$(jq -r '.token' ~/.secrets/influxdb3-secrets/admin-token.json)
curl -H "Authorization: Bearer ${TOKEN}" http://127.0.0.1:8087/health
```

**Resolution**: Recreate operator token

```bash
podman exec influxdb3-svc influxdb3 create token --admin
```

### Issue: Traefik Integration Not Working

**Problem**: HTTPS access fails or SSL certificate issues

**Detection:**

```bash
# Check Traefik dashboard
curl http://localhost:9999/api/http/routers | jq '.[] | select(.name | contains("influxdb3"))'

# Check container labels
podman inspect influxdb3-svc | jq '.[0].Config.Labels'
```

**Resolution**: Verify Traefik is running and labels are correct

```bash
systemctl --user status traefik-pod
./manage-svc.sh influxdb3 deploy  # Reapply labels
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
influxdb3_svc:
  hosts:
    podma:
      influxdb3_svc_name: "influxdb3-podma"
  vars:
    influxdb3_port: 8087

# Deployment workflow
./manage-svc.sh -h podma -i inventory/podma.yml influxdb3 prepare
./manage-svc.sh -h podma -i inventory/podma.yml influxdb3 deploy
./svc-exec.sh -h podma -i inventory/podma.yml influxdb3 configure
./svc-exec.sh -h podma -i inventory/podma.yml influxdb3 verify
```

**Localhost variant** (replace `-h podma -i inventory/podma.yml` with no flags):

```bash
./manage-svc.sh influxdb3 prepare
./manage-svc.sh influxdb3 deploy
./svc-exec.sh influxdb3 configure
./svc-exec.sh influxdb3 verify
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

**Component Architecture:**

```text
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Telegraf      │───▶│  InfluxDB3   │◀───│    Grafana      │
│   (Metrics)     │    │  (Port 8087) │    │ (Visualization) │
└─────────────────┘    └──────────────┘    └─────────────────┘
                              │
                    ┌─────────┴──────────┐
                    │                    │
              ┌───────────┐      ┌──────────────┐
              │  Parquet  │      │  Traefik SSL │
              │   Files   │      │ (Port 8080)  │
              └───────────┘      └──────────────┘
                                         │
                              https://influxdb3.a0a0.org:8080
```

See [docs/Solti-Container-Pattern.md](../../docs/Solti-Container-Pattern.md) for complete pattern documentation.

## Migration from InfluxDB v2

### Key Differences

| Aspect | v2 | v3 Core |
|--------|----|---------|
| Port | 8086 | 8087 |
| CLI | `influx` | `influxdb3` |
| Auth | Users + Tokens | Tokens only |
| Setup | `influx setup` | `influxdb3 create token --admin` |
| Buckets | `influx bucket create` | `influxdb3 create database` |
| Web UI | Built-in | None (use Grafana) |
| Storage | TSM | Parquet/Arrow |

### Migration Steps

1. Export v2 data (outside scope of this role)
2. Deploy InfluxDB3: `./manage-svc.sh influxdb3 deploy`
3. Configure databases: `./svc-exec.sh influxdb3 configure`
4. Import data using v1 API compatibility
5. Create tokens with appropriate permissions
6. Update client applications with new tokens and API endpoints

**Note**: v3 Core is NOT compatible with v2 data files. Migration requires export/import.

## Security Considerations

- Containers run rootless under your user account
- Ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- Token-based authentication required for all API access
- Operator token has full admin privileges - store securely in `~/.secrets/`
- Resource tokens should follow principle of least privilege
- No web UI reduces attack surface (use Grafana for visualization)

## Links

- [InfluxDB 3 Core Documentation](https://docs.influxdata.com/influxdb3/core/)
- [Token Management Guide](https://docs.influxdata.com/influxdb3/core/admin/tokens/)
- [API v3 Reference](https://docs.influxdata.com/influxdb3/core/api/v3/)
- [InfluxDB Docker Hub Image](https://hub.docker.com/_/influxdb)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs influxdb3-svc`
2. Systemd logs: `journalctl --user -u influxdb3-pod`
3. Verification output: `./svc-exec.sh influxdb3 verify`

For InfluxDB application issues, consult the [official documentation](https://docs.influxdata.com/influxdb3/core/).

## Related Services

- **Telegraf**: Metrics collection agent that writes to InfluxDB3
- **Grafana**: Visualization platform for InfluxDB3 data
- **Traefik**: Provides SSL termination and routing for InfluxDB3 API
- **Loki**: Complementary log aggregation (use both for complete observability)
