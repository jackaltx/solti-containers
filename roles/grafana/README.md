# Grafana Role

Deploys Grafana (open-source analytics and monitoring platform) as a rootless Podman container using Quadlets.

## Overview

**Service**: Grafana
**Architecture**: Single container with SQLite database
**Network**: ct-net (shared container network)
**Ports**: 3000 (HTTP)
**SSL**: Traefik integration (grafana.example.com)
**Features**: Dashboards, data sources, alerting, annotations

## Quick Start

```bash
# Set admin password (required env variable!)
export GRAFANA_ADMIN_PASSWORD="your-secure-password"

# Prepare system (one-time)
./manage-svc.sh grafana prepare

# Deploy grafana
./manage-svc.sh grafana deploy

# Verify functionality
./svc-exec.sh grafana verify
```

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Full Redeploy

Complete removal and fresh installation with latest container images. Useful for testing, upgrades, or recovering from corruption.

```bash
# Set admin password
export GRAFANA_ADMIN_PASSWORD="your-secure-password"

# Step 1: Complete removal (data + images)
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh -h podma -i inventory/podma.yml grafana remove

# Step 2: Prepare system
./manage-svc.sh -h podma -i inventory/podma.yml grafana prepare

# Step 3: Deploy with fresh image
./manage-svc.sh -h podma -i inventory/podma.yml grafana deploy

# Step 4: Verify deployment
./svc-exec.sh -h podma -i inventory/podma.yml grafana verify
```

**What this does**:

- **Step 1**: Removes service, data directories, AND container images
- **Step 2**: Creates fresh directory structure with proper permissions
- **Step 3**: Pulls latest container image and deploys service
- **Step 4**: Validates deployment (health checks)

**Expected results**:

- Fresh `docker.io/grafana/grafana:latest` image pulled
- Clean database with no existing dashboards or data sources
- All verification tests pass
- Service accessible at `http://127.0.0.1:3000`

**Localhost variant** (replace `-h podma -i inventory/podma.yml` with no flags):

```bash
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh grafana remove
./manage-svc.sh grafana prepare
./manage-svc.sh grafana deploy
./svc-exec.sh grafana verify
```

> **Warning**: `DELETE_DATA=true` permanently destroys all dashboards, data sources, and configuration. Only use for testing or fresh installations.

## Architecture

### Single Container Design

- **Container**: grafana-svc (grafana/grafana:latest)
- **Database**: SQLite (embedded, no separate container)
- **Pod**: grafana-pod (systemd managed)
- **Network**: ct-net with internal DNS

### Data Persistence

```
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

## Configuration

### Inventory Variables

**Required**:

```yaml
grafana_admin_password: "{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') }}"
grafana_data_dir: "{{ ansible_facts.user_dir }}/grafana-data"
```

**Optional**:

```yaml
# Ports
grafana_port: 3000                    # HTTP port

# Container
grafana_image: "docker.io/grafana/grafana:latest"

# Admin user
grafana_admin_user: "admin"

# Application settings
grafana_allow_sign_up: false          # Disable self-registration
grafana_allow_org_create: false       # Disable org creation

# Features
grafana_enable_traefik: true          # Enable Traefik SSL
grafana_analytics_reporting_enabled: false
grafana_check_for_updates: false

# Data management
grafana_delete_data: false            # Preserve data on remove
```

### Environment Variables

Set before deployment:

```bash
export GRAFANA_ADMIN_PASSWORD="your-secure-password"
```

## Access Methods

### Web Interface

- **Local**: <http://localhost:3000>
- **Traefik**: <https://grafana.example.com> (with SSL)

**Default Credentials**:

- Username: `admin`
- Password: `$GRAFANA_ADMIN_PASSWORD`

## Operations

### Start/Stop Service

```bash
systemctl --user start grafana-pod
systemctl --user stop grafana-pod
systemctl --user restart grafana-pod
```

### View Logs

```bash
# Container logs
podman logs grafana-svc

# Follow logs
podman logs -f grafana-svc

# Systemd journal
journalctl --user -u grafana-pod -f
```

### Check Status

```bash
# Service status
systemctl --user status grafana-pod

# Container status
podman ps --filter "pod=grafana"

# Resource usage
podman stats grafana-svc
```

## Integration

### Traefik SSL Termination

Grafana automatically integrates with Traefik when deployed:

- Router: `grafana.example.com` → grafana-svc:3000
- Automatic Let's Encrypt certificates
- Security headers and HTTPS redirect

### Data Sources

Configure data sources via:

1. Web UI: Configuration → Data Sources
2. Provisioning: `~/grafana-data/provisioning/datasources/`

Common data sources:

- Prometheus
- InfluxDB
- Elasticsearch
- Loki

## References

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Container-Role-Architecture.md](../../docs/Container-Role-Architecture.md)

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
