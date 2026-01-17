# Grafana Role

Deploys Grafana as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **Grafana Server** (`grafana/grafana:latest`) - Open-source analytics and monitoring platform

## Features

- **Interactive Dashboards**: Build visualizations from multiple data sources
- **Data Source Support**: InfluxDB, Prometheus, Loki, Elasticsearch, and more
- **Alerting**: Configure alerts based on metrics and log data
- **Provisioning**: Auto-deploy dashboards and data sources via configuration
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management
- **Traefik Support**: Optional SSL termination and reverse proxy
- **Upgrade Detection**: Built-in check for image updates

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh grafana prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Set admin password (required)
export GRAFANA_ADMIN_PASSWORD="your-secure-password"

./manage-svc.sh grafana deploy
```

Deploys and starts the service with Grafana server.

### 3. Verify

```bash
./svc-exec.sh grafana verify
```

Runs health checks and functional tests.

### 4. Access

- **Web Interface**: `http://localhost:3000`
- **With Traefik SSL**: `https://grafana.example.com`
- **Default Credentials**: `admin` / `$GRAFANA_ADMIN_PASSWORD`

## Configuration

### Environment Variables

```bash
export GRAFANA_ADMIN_PASSWORD="your-secure-password"  # Grafana admin password (required)
```

### Inventory Variables

```yaml
# Data and ports
grafana_data_dir: "{{ lookup('env', 'HOME') }}/grafana-data"
grafana_port: 3000

# Service configuration
grafana_image: "docker.io/grafana/grafana:latest"
grafana_admin_user: "admin"
grafana_allow_sign_up: false
grafana_allow_org_create: false
grafana_analytics_reporting_enabled: false
grafana_check_for_updates: false

# Traefik integration
grafana_enable_traefik: true

# Data management
grafana_delete_data: false
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/grafana-data/
├── config/
│   └── grafana.ini      # Main configuration
├── data/
│   └── grafana.db       # SQLite database (dashboards, users, etc.)
├── logs/                # Application logs
├── plugins/             # Installed plugins
└── provisioning/
    ├── dashboards/      # Auto-provisioned dashboards
    ├── datasources/     # Auto-provisioned data sources
    └── notifiers/       # Auto-provisioned alerting
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status grafana-pod

# Start service
systemctl --user start grafana-pod

# Stop service
systemctl --user stop grafana-pod

# Restart service
systemctl --user restart grafana-pod

# Enable on boot
systemctl --user enable grafana-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u grafana-pod -f

# View container logs
podman logs grafana-svc

# View last 50 lines
podman logs --tail 50 grafana-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh grafana remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh grafana remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status grafana-pod

# Check container logs
podman logs grafana-svc

# Test web interface
curl -s http://localhost:3000/api/health | jq

# Run verification tasks
./svc-exec.sh grafana verify
```

### Dashboard Operations

```bash
# List dashboards via API (requires authentication)
curl -u admin:$GRAFANA_ADMIN_PASSWORD http://localhost:3000/api/search

# View datasources
curl -u admin:$GRAFANA_ADMIN_PASSWORD http://localhost:3000/api/datasources

# Resource usage
podman stats grafana-svc
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh grafana check_upgrade
```

**Output when updates available:**

```text
TASK [grafana : Display container status]
ok: [firefly] => {
    "msg": "grafana-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [grafana : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: grafana-svc"
}
```

**Output when up-to-date:**

```text
TASK [grafana : Display container status]
ok: [firefly] => {
    "msg": "grafana-svc:Up to date (abc123)"
}

TASK [grafana : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh grafana remove

# 2. Redeploy with latest image
./manage-svc.sh grafana deploy

# 3. Verify new version
./svc-exec.sh grafana verify
```

**Note**: Data in `~/grafana-data/` persists across upgrades.

## Traefik Integration

When Traefik is deployed with `grafana_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates: `grafana.example.com` → `firefly.example.com`

1. Access via HTTPS:
   - `https://grafana.example.com`

## Advanced Usage

### Dashboard Provisioning

Auto-deploy dashboards by placing JSON files in:

```text
~/grafana-data/provisioning/dashboards/
```

Example provisioning config:

```yaml
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/provisioning/dashboards
```

### Data Source Provisioning

Auto-configure data sources in:

```text
~/grafana-data/provisioning/datasources/
```

Example InfluxDB datasource:

```yaml
apiVersion: 1
datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb-svc:8086
    jsonData:
      version: Flux
      organization: myorg
      defaultBucket: metrics
    secureJsonData:
      token: ${INFLUX_TOKEN}
```

### Plugin Installation

Install plugins by mounting them to:

```text
~/grafana-data/plugins/
```

Or configure via environment variable in inventory:

```yaml
grafana_install_plugins:
  - grafana-piechart-panel
  - grafana-worldmap-panel
```

## Troubleshooting

### Issue: Cannot Login

**Problem**: Login fails with "Invalid username or password"

**Detection:**

```bash
# Check admin password is set
echo $GRAFANA_ADMIN_PASSWORD

# Check logs for authentication errors
podman logs grafana-svc | grep -i auth
```

**Resolution**: Ensure password was set before deployment

```bash
export GRAFANA_ADMIN_PASSWORD="your-secure-password"
./manage-svc.sh grafana deploy
```

### Issue: Dashboard Not Showing Data

**Problem**: Dashboard panels show "No Data" or blank graphs

**Detection:**

```bash
# Check datasource connection
curl -u admin:$GRAFANA_ADMIN_PASSWORD http://localhost:3000/api/datasources

# Test datasource connectivity
podman exec grafana-svc ping influxdb-svc
```

**Resolution**: Verify data source configuration and network connectivity

1. Check datasource settings in Grafana UI
2. Verify target service is running on ct-net
3. Test query manually in data source explore view

### Issue: Permission Errors

**Problem**: Cannot write to data directory or logs

**Detection:**

```bash
# Check directory permissions
ls -la ~/grafana-data/

# Check SELinux contexts (RHEL-based systems)
ls -Z ~/grafana-data/
```

**Resolution**: Re-run prepare to fix permissions

```bash
./manage-svc.sh grafana prepare
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
grafana_svc:
  hosts:
    podma:
      grafana_svc_name: "grafana-podma"
  vars:
    grafana_port: 3000

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml grafana prepare
./manage-svc.sh -h podma -i inventory/podma.yml grafana deploy
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
│   Dashboards    │───▶│   Grafana    │◀───│  Data Sources   │
│                 │    │  (Port 3000) │    │  (InfluxDB,     │
└─────────────────┘    └──────────────┘    │   Loki, etc.)   │
                              │             └─────────────────┘
                              │
                              │
                              │
                       ┌──────────────────┐
                       │     Traefik      │
                       │  (SSL Termination)│
                       └──────────────────┘
                              │
                       https://grafana.example.com
```

**Single Container Design:**

- **Container**: grafana-svc (grafana/grafana:latest)
- **Database**: SQLite (embedded, no separate container)
- **Pod**: grafana-pod (systemd managed)
- **Network**: ct-net with internal DNS

See [docs/Container-Role-Architecture.md](../../docs/Container-Role-Architecture.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- Ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- Admin password required for authentication
- Disable anonymous access via `grafana_allow_sign_up: false`
- Plugin installation restricted to admin users
- API access requires authentication

## Links

- [Grafana Official Documentation](https://grafana.com/docs/grafana/latest/)
- [Grafana Docker Hub Image](https://hub.docker.com/r/grafana/grafana)
- [Dashboard Provisioning Docs](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs grafana-svc`
2. Systemd logs: `journalctl --user -u grafana-pod`
3. Verification output: `./svc-exec.sh grafana verify`

For Grafana application issues, consult the [official documentation](https://grafana.com/docs/grafana/latest/).

## Service Properties

```yaml
service_properties:
  root: "grafana"
  name: "grafana-pod"
  pod_key: "grafana.pod"
  quadlets:
    - "grafana-svc.container"
    - "grafana.pod"
  data_dir: "{{ grafana_data_dir }}"
  config_dir: "config"
  delete_data: "{{ lookup('env', 'DELETE_DATA') | default(false) | bool }}"
  delete_images: "{{ lookup('env', 'DELETE_IMAGES') | default(false) | bool }}"
  container_image: "{{ grafana_image }}"
  dirs:
    - { path: "", mode: "0750" }
    - { path: "config", mode: "0750" }
    - { path: "data", mode: "0750" }
    - { path: "logs", mode: "0750" }
    - { path: "plugins", mode: "0750" }
    - { path: "provisioning", mode: "0750" }
    - { path: "provisioning/dashboards", mode: "0750" }
    - { path: "provisioning/datasources", mode: "0750" }
    - { path: "provisioning/notifiers", mode: "0750" }
```
