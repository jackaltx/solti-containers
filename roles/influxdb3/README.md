# InfluxDB 3 Core Role

Deploys InfluxDB 3 Core as a rootless Podman container with token-based authentication and optional Traefik SSL termination.

## Overview

- **Image**: `docker.io/influxdata/influxdb:3-core`
- **Port**: 8181 (HTTP API)
- **Auth**: Token-only (no username/password)
- **Storage**: Parquet/Apache Arrow
- **SSL**: Traefik termination (container uses plain HTTP)

## Quick Start

```bash
# 1. Prepare (one-time)
./manage-svc.sh influxdb3 prepare

# 2. Deploy
./manage-svc.sh influxdb3 deploy

# 3. Configure databases and tokens
./svc-exec.sh influxdb3 configure

# 4. Verify
./svc-exec.sh influxdb3 verify
```

## Full Redeploy

Complete removal and fresh installation with latest container images. Useful for testing, upgrades, or recovering from corruption.

```bash
# Step 1: Complete removal (data + images)
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh -h podma -i inventory/podma.yml influxdb3 remove

# Step 2: Prepare system
./manage-svc.sh -h podma -i inventory/podma.yml influxdb3 prepare

# Step 3: Deploy with fresh image
./manage-svc.sh -h podma -i inventory/podma.yml influxdb3 deploy

# Step 4: Configure databases and tokens
./svc-exec.sh -h podma -i inventory/podma.yml influxdb3 configure

# Step 5: Verify deployment
./svc-exec.sh -h podma -i inventory/podma.yml influxdb3 verify
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
- Service accessible at `http://127.0.0.1:8181`

**Localhost variant** (replace `-h podma -i inventory/podma.yml` with no flags):

```bash
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh influxdb3 remove
./manage-svc.sh influxdb3 prepare
./manage-svc.sh influxdb3 deploy
./svc-exec.sh influxdb3 configure
./svc-exec.sh influxdb3 verify
```

> **Warning**: `DELETE_DATA=true` permanently destroys all databases, tokens, and time-series data. Only use for testing or fresh installations.

## Configuration

### Inventory Variables

```yaml
influxdb3_svc:
  hosts:
    firefly:
  vars:
    influxdb3_port: 8181                    # Host port (configurable)
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
```

### Token Permissions Format

```
database:DATABASE_NAME:ACTIONS
```

**Examples:**
- `database:telegraf:write` - Write-only to telegraf
- `database:metrics:read` - Read-only to metrics
- `database:logs:write,read` - Read/write to logs
- `database:*:read` - Read-only to ALL databases

## Workflow

### 1. Preparation

```bash
./manage-svc.sh influxdb3 prepare
```

Creates:
- `~/influxdb3-data/config/`
- `~/influxdb3-data/data/`
- `~/influxdb3-data/plugins/`

### 2. Deployment

```bash
./manage-svc.sh influxdb3 deploy
```

Actions:
- Templates environment file
- Deploys pod and container
- Creates operator (admin) token
- Saves token to `~/.secrets/influxdb3-secrets/admin-token.json`
- Runs basic health checks

### 3. Configuration

```bash
./svc-exec.sh influxdb3 configure
```

Creates:
- Databases from `influxdb3_databases` list
- Resource tokens from `influxdb3_tokens` list
- Saves tokens to `./data/influxdb3-tokens-firefly.yml`

### 4. Verification

```bash
./svc-exec.sh influxdb3 verify
```

Tests:
- Pod/container status
- API health endpoint
- Database creation
- Write/query operations

### 5. Removal

```bash
./manage-svc.sh influxdb3 remove
```

Removes containers, preserves data by default.

## Access Methods

### 1. Inside Container (Primary for Configuration)

```bash
# Create token
podman exec influxdb3-svc influxdb3 create token --admin

# Create database
podman exec -e INFLUXDB3_AUTH_TOKEN=${TOKEN} \
  influxdb3-svc influxdb3 create database mydb

# Query via curl inside container
podman exec influxdb3-svc \
  curl -s "http://localhost:8181/health"
```

### 2. Localhost Access (Testing)

```bash
# Health check
curl http://127.0.0.1:8181/health

# Write data (v3 API)
curl -X POST "http://127.0.0.1:8181/api/v3/write?db=telegraf" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "cpu,host=server01 usage=23.5"

# Query data
curl "http://127.0.0.1:8181/api/v3/query?db=telegraf&q=SELECT * FROM cpu" \
  -H "Authorization: Bearer ${TOKEN}"
```

### 3. External Access (Production via Traefik)

```bash
# HTTPS only (port 8080)
curl https://influxdb3.a0a0.org:8080/health

# Write via SSL
curl -X POST "https://influxdb3.a0a0.org:8080/api/v3/write?db=telegraf" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "cpu,host=server01 usage=23.5"
```

### 4. v1 API Compatibility

```bash
# v1 write (username ignored, password=token)
curl --user "ignored:${TOKEN}" \
  "http://127.0.0.1:8181/write?db=telegraf" \
  --data-binary "cpu,host=server01 value=23.5"
```

## Token Management

### Understanding Tokens vs Users

**InfluxDB 3 Core has NO user accounts** - only tokens with descriptions.

| v2 Concept | v3 Core Equivalent |
|------------|-------------------|
| Admin user with password | Operator token (`--admin`) |
| User "telegraf" | Token with description "telegraf-writer" |
| User permissions | Token permissions |

### Operator Token Location

```
~/.secrets/influxdb3-secrets/admin-token.json
```

**Important**: This token has full admin access. Store securely.

### Resource Tokens Location

```
./data/influxdb3-tokens-firefly.yml
```

Contains all created tokens with their permissions.

## Port Configuration

### Default Port

```yaml
influxdb3_port: 8181  # Localhost binding
```

### Check for Conflicts

```bash
ss -tulpn | grep :8181
```

### Override in Inventory

```yaml
influxdb3_svc:
  hosts:
    firefly:
      influxdb3_port: 8182  # Use different port
```

### Known Port Conflicts

- 8081 - Redis Commander (in use)
- 8080 - Traefik HTTPS (in use)
- 8200 - HashiVault (in use)
- 9200 - Elasticsearch (in use)

## Traefik Integration

### Automatic SSL Configuration

When `influxdb3_enable_traefik: true` (default), the container gets:

- SSL termination via Traefik
- Let's Encrypt certificate
- HTTPS access at `https://influxdb3.{{ domain }}:8080`

### Traefik Labels

Automatically applied:

```yaml
traefik.enable=true
traefik.http.routers.influxdb3.rule=Host(`influxdb3.{{ domain }}`)
traefik.http.routers.influxdb3.entrypoints=websecure
traefik.http.services.influxdb3.loadbalancer.server.port=8181
```

## Troubleshooting

### Check Service Status

```bash
systemctl --user status influxdb3-pod
journalctl --user -u influxdb3-pod -f
```

### Check Container

```bash
podman ps --filter "pod=influxdb3"
podman logs influxdb3-svc
```

### Health Check

```bash
curl http://127.0.0.1:8181/health
```

### Verify Token

```bash
cat ~/.secrets/influxdb3-secrets/admin-token.json | jq .
```

### Re-run Configuration

```bash
# Safe to run multiple times (idempotent)
./svc-exec.sh influxdb3 configure
```

### Check Traefik Integration

```bash
# Traefik dashboard
curl http://localhost:9999/api/http/routers | jq '.[] | select(.name | contains("influxdb3"))'
```

## Data Persistence

### Location

```
~/influxdb3-data/data/
```

### Backup

```bash
# Stop service
systemctl --user stop influxdb3-pod

# Backup data
tar -czf influxdb3-backup-$(date +%Y%m%d).tar.gz ~/influxdb3-data/data/

# Restart service
systemctl --user start influxdb3-pod
```

### Clean Removal

```bash
# Edit inventory.yml
influxdb3_delete_data: true

# Then remove
./manage-svc.sh influxdb3 remove
```

## Migration from InfluxDB v2

### Key Differences

| Aspect | v2 | v3 Core |
|--------|----|---------|
| Port | 8086 | 8181 |
| CLI | `influx` | `influxdb3` |
| Auth | Users + Tokens | Tokens only |
| Setup | `influx setup` | `influxdb3 create token --admin` |
| Buckets | `influx bucket create` | `influxdb3 create database` |
| Web UI | Built-in | None (use Grafana) |

### Migration Steps

1. Export v2 data (outside scope of this role)
2. Deploy InfluxDB3: `./manage-svc.sh influxdb3 deploy`
3. Create equivalent databases
4. Import data using v1 API compatibility
5. Create tokens with appropriate permissions
6. Update client applications with new tokens

## References

- [InfluxDB 3 Core Docs](https://docs.influxdata.com/influxdb3/core/)
- [Token Management](https://docs.influxdata.com/influxdb3/core/admin/tokens/)
- [API Reference](https://docs.influxdata.com/influxdb3/core/api/v3/)
- [SOLTI Container Pattern](../../docs/Solti-Container-Pattern.md)
