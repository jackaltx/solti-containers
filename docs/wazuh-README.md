# Wazuh Podman Role

This role manages the installation, configuration, and lifecycle of Wazuh using rootless Podman containers. It follows the standard SOLTI container pattern, providing consistent deployment, configuration, and management across all services.

## Features

- Rootless Podman deployment
- Three-container architecture (manager, indexer, dashboard)
- Self-signed certificate generation
- Systemd integration using Quadlets
- SELinux support for RHEL-based systems
- Automatic post-setup configuration

## Requirements

- Podman 4.x or later
- Systemd
- User with sudo access
- SELinux if running on RHEL/CentOS (role handles contexts)

## Role Variables

### Installation Options

```yaml
wazuh_state: present  # Use 'absent' to remove
wazuh_force_reload: false
wazuh_delete_data: false  # Set to true to delete data during removal
```

### Container Settings

```yaml
wazuh_manager_image: "docker.io/wazuh/wazuh-manager:4.7.2"
wazuh_indexer_image: "docker.io/wazuh/wazuh-indexer:4.7.2"
wazuh_dashboard_image: "docker.io/wazuh/wazuh-dashboard:4.7.2"
```

### Directory Settings

```yaml
wazuh_data_dir: "{{ ansible_facts.user_dir }}/wazuh-data"
```

### Port Settings

```yaml
wazuh_api_port: 55000
wazuh_manager_port: 1514
wazuh_registration_port: 1515
wazuh_dashboard_port: 443
wazuh_indexer_port: 9200
```

### Security Settings

```yaml
wazuh_admin_password: "{{ lookup('env', 'WAZUH_ADMIN_PASSWORD') | default('changeme') }}"
wazuh_api_user: "wazuh-api"
wazuh_api_password: "{{ lookup('env', 'WAZUH_API_PASSWORD') | default('changeme') }}"
```

See `defaults/main.yml` for all available variables and their default values.

## Example Playbooks

### Basic Installation

```yaml
- hosts: servers
  roles:
    - role: wazuh
      vars:
        wazuh_admin_password: "secure_password"
        wazuh_api_password: "secure_api_password"
        wazuh_data_dir: "/opt/wazuh-data"
```

### With TLS/SSL and Custom Ports

```yaml
- hosts: servers
  roles:
    - role: wazuh
      vars:
        wazuh_admin_password: "secure_password"
        wazuh_api_password: "secure_api_password"
        wazuh_api_port: 9000
        wazuh_dashboard_port: 8443
        wazuh_generate_certs: true
```

### Remove Wazuh with Data Cleanup

```yaml
- hosts: servers
  roles:
    - role: wazuh
      vars:
        wazuh_state: absent
        wazuh_delete_data: true
```

## Usage

After deployment:

- Wazuh Dashboard will be available at `https://localhost:8080` or `https://wazuh.your-domain.com`
- Wazuh API will be available at `https://localhost:55000`
- Login with configured API credentials

### Initial Setup

1. Get the service status:

```bash
systemctl --user status wazuh-pod
```

2. Verify the installation:

```bash
./svc-exec.sh wazuh verify
```

This command will run several checks to verify that all Wazuh components are running correctly, including:

- Pod and container status
- Wazuh Manager status
- Wazuh Indexer health check
- Wazuh API connectivity
- Wazuh Dashboard accessibility
- Agent enrollment status

3. Check detailed logs:

```bash
podman logs wazuh-manager
podman logs wazuh-indexer
podman logs wazuh-dashboard
```

### Adding Agents

1. Get the agent enrollment key:

```bash
podman exec wazuh-manager /var/ossec/bin/manage_agents -s
```

2. Use this key when installing agents on your systems

## Security Considerations

1. Default configuration enables encryption between components
2. All passwords should be changed from defaults
3. Configure firewall rules as needed
4. Services bind to localhost by default for security

## Backup Strategy

The following directories should be backed up:

- `{{ wazuh_data_dir }}/data/` - Holds the application data
- `{{ wazuh_data_dir }}/config/` - Contains configuration files
- `{{ wazuh_data_dir }}/certs/` - Contains TLS certificates

Example backup command:

```bash
tar -czf wazuh-backup.tar.gz ${WAZUH_DATA_DIR}/data ${WAZUH_DATA_DIR}/config ${WAZUH_DATA_DIR}/certs
```

## Maintenance and Troubleshooting

### Service Management Commands

```bash
# Check service status
systemctl --user status wazuh-pod
systemctl --user status container-wazuh-manager
systemctl --user status container-wazuh-indexer
systemctl --user status container-wazuh-dashboard

# Restart services
systemctl --user restart wazuh-pod

# Verify deployment
./svc-exec.sh wazuh verify

# Get detailed verification with debug output
./svc-exec.sh wazuh verify -v
```

You can use the svc-exec.sh script for additional operations:

```bash
# Run just the post-setup configuration (if needed)
./svc-exec.sh wazuh post_setup

# Generate/regenerate certificates
./svc-exec.sh wazuh certificates

# Get agent registration key
./svc-exec.sh wazuh registration_key
```

### Common Issues

1. **Indexer won't start**:
   - Check memory allocation (`wazuh_indexer_memory`)
   - Verify that `vm.max_map_count` is at least 262144

2. **Dashboard can't connect to indexer or manager**:
   - Verify the certificates in `{{ wazuh_data_dir }}/certs/`
   - Check network connectivity between containers

3. **SELinux issues**:
   - Run `sudo restorecon -Rv {{ wazuh_data_dir }}`

## License

MIT

## Author Information

Created by jackaltx and claude.
