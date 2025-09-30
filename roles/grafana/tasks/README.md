# README.md

# Grafana Podman Role

This role manages the installation and configuration of Grafana using rootless Podman containers. It provides a complete visualization platform for metrics, logs, and other data sources.

## Features

- Rootless Podman deployment
- Systemd integration using Quadlets
- Configurable data sources and dashboards
- SQLite database backend (lightweight for development)
- Built-in provisioning support
- Traefik integration for reverse proxy
- SELinux support for RHEL systems

## Requirements

- Podman 4.x or later
- Systemd with user services enabled
- User with sudo access
- SELinux if running on RHEL/CentOS (role handles contexts)

## Role Variables

### Installation Options

```yaml
grafana_state: present  # Use 'absent' to remove
grafana_force_reload: false
grafana_delete_data: false  # Set to true to delete data during removal
```

### Container Settings

```yaml
grafana_image: "docker.io/grafana/grafana:latest"
grafana_port: 3000
grafana_domain: "grafana.{{ domain }}"
```

### Security Settings

```yaml
grafana_admin_user: "admin"
grafana_admin_password: "{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') | default('changeme') }}"
grafana_allow_sign_up: false
grafana_allow_org_create: false
```

### Database Settings

```yaml
grafana_database_type: "sqlite3"  # Lightweight for development
grafana_database_path: "/var/lib/grafana/grafana.db"
```

See defaults/main.yml for all available variables and their default values.

## Example Playbooks

### Basic Installation

```yaml
- hosts: servers
  roles:
    - role: grafana
      vars:
        grafana_admin_password: "secure_password"
```

### With Custom Configuration

```yaml
- hosts: servers
  roles:
    - role: grafana
      vars:
        grafana_admin_password: "secure_password"
        grafana_allow_sign_up: true
        grafana_smtp_enabled: true
        grafana_smtp_host: "smtp.example.com:587"
```

### Removal with Data Cleanup

```yaml
- hosts: servers
  roles:
    - role: grafana
      vars:
        grafana_state: absent
        grafana_delete_data: true
```

## Usage

After deployment:

- Grafana will be available at <http://localhost:3000>
- Default credentials: admin / your_configured_password
- Configuration file: ~/grafana-data/config/grafana.ini
- Data directory: ~/grafana-data/data

### Initial Setup

1. Access the web interface at <http://localhost:3000>
2. Log in with admin credentials
3. Configure data sources (Prometheus, InfluxDB, etc.)
4. Import or create dashboards

### Adding Data Sources

Data sources can be configured via:

1. Web interface (Data Sources menu)
2. Provisioning files in ~/grafana-data/provisioning/datasources/

### Dashboard Management

Dashboards can be:

1. Created in the web interface
2. Imported from Grafana.com
3. Provisioned via configuration files

## Integration

# CLAUDE:  this needs a strucure to create a group of defaults

### With Prometheus

```yaml
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://localhost:9090
  isDefault: true
```

### With Traefik

The role automatically configures Traefik labels for reverse proxy access when Traefik is available.

## Troubleshooting

### Common Issues

1. **Permission Issues**: Ensure proper ownership of data directories
2. **Database Lock**: Stop Grafana before backing up SQLite database
3. **Plugin Installation**: Use GF_INSTALL_PLUGINS environment variable

### Useful Commands

```bash
# Check container status
podman ps --filter "pod=grafana"

# View logs
podman logs grafana-svc

# Access container
podman exec -it grafana-svc /bin/bash

# Check service status
systemctl --user status grafana-pod
```

## Security Considerations

1. Change default admin password
2. Disable sign-up for production environments
3. Configure proper firewall rules
4. Use HTTPS in production (via Traefik or direct TLS)
5. Regular backup of dashboard configurations

## License

MIT

## Author Information
