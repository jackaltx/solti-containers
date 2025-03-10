# Solti Ansible Project

A comprehensive Ansible project for deploying and managing containerized services using Podman and Quadlets with systemd integration.

## Overview

The Solti project provides an infrastructure-as-code solution for deploying various services in containers. It uses a modular approach with a common `_base` role that handles the shared functionality across all services.

Key features:

- Rootless Podman container deployment
- Systemd integration using Quadlets
- Cross-platform support (RHEL/CentOS and Debian-based systems)
- Shell script wrappers for simplified management
- SELinux support for RHEL systems

## Supported Services

- **Elasticsearch**: Search and analytics engine
- **HashiVault**: Secrets management
- **Mattermost**: Team collaboration platform
- **Redis**: In-memory data store
- **Traefik**: Modern HTTP reverse proxy
- **MinIO**: S3-compatible object storage

## Quick Start

### Prerequisites

- Podman 4.x or later installed
- Systemd
- User with sudo access

### Service Management Scripts

The project includes two helper scripts to simplify service management without directly using Ansible playbooks:

#### 1. `manage-svc.sh`

This script manages the lifecycle of services through simple commands.

```bash
# Usage
./manage-svc.sh <service> <action>

# Actions: prepare, deploy, remove
```

Examples:

```bash
# Prepare the system for Elasticsearch deployment
./manage-svc.sh elasticsearch prepare

# Deploy HashiVault
./manage-svc.sh hashivault deploy

# Remove Redis (preserves data)
./manage-svc.sh redis remove
```

#### 2. `svc-exec.sh`

This script executes specific tasks for a service, such as verification or configuration tasks.

```bash
# Usage
./svc-exec.sh [-K] <service> [entry]

# -K: Use sudo (needed for some operations)
# Default entry: verify
```

Examples:

```bash
# Verify Elasticsearch installation
./svc-exec.sh elasticsearch verify

# Configure MinIO with sudo privileges
./svc-exec.sh -K minio configure

# Verify Mattermost is running
./svc-exec.sh mattermost
```

## Architecture

### The `_base` Role

The `_base` role contains shared functionality used by all service-specific roles. It handles:

1. **Directory creation and permissions**
2. **SELinux context configuration**
3. **Network setup**
4. **Container deployment via Quadlets**
5. **Systemd integration**
6. **Cleanup processes**

Each service role extends this foundation with service-specific configurations and tasks.

### Role Structure

Each service role follows the same structure:

```
roles/
├── _base/                # Common functionality
│   ├── defaults/
│   ├── tasks/
│   └── templates/
├── elasticsearch/        # Service-specific role
│   ├── defaults/
│   ├── handlers/
│   ├── tasks/
│   └── templates/
├── hashivault/
└── ...
```

### Deployment Flow

1. **Prepare**: Set up directories, SELinux contexts, and system configuration
2. **Deploy**: Create containers, configure systemd, and start services
3. **Verify**: Check if services are running correctly
4. **Remove**: Stop and remove containers, optionally delete data

## Configuration Variables

### Common Variables

These variables are used across all services:

```yaml
service_network: "ct-net"             # Container network name
service_dns_servers:                  # DNS servers for containers
  - "1.1.1.1"
  - "8.8.8.8"
service_dns_search: "example.com"     # DNS search domain
```

### Elasticsearch

```yaml
elasticsearch_state: present          # present, prepare, or absent
elasticsearch_data_dir: "~/elasticsearch-data"
elasticsearch_password: "your_secure_password"
elasticsearch_port: 9200
elasticsearch_gui_port: 8088
elasticsearch_memory: "1g"            # JVM heap size
elasticsearch_enable_security: true
elasticsearch_delete_data: false      # Set to true to delete data on removal
```

### HashiVault

```yaml
hashivault_state: present                  # present, prepare, or absent
vault_data_dir: "~/vault-data"
vault_api_port: 8200
vault_enable_ui: true
vault_delete_data: false
vault_storage_type: "file"            # file, raft, consul
```

### Mattermost

```yaml
mattermost_state: present             # present, prepare, or absent
mattermost_data_dir: "~/mattermost-data"
mattermost_postgres_password: "your_secure_password"
mattermost_port: 8065
mattermost_db_name: "mattermost"
mattermost_db_user: "mmuser"
mattermost_site_name: "Mattermost"
mattermost_delete_data: false
```

### Redis

```yaml
redis_state: present                  # present, prepare, or absent
redis_data_dir: "~/redis-data"
redis_port: 6379
redis_gui_port: 8081
redis_password: "your_secure_password"
redis_maxmemory: "256mb"
redis_maxmemory_policy: "allkeys-lru"
redis_delete_data: false
```

### Traefik

```yaml
traefik_state: present                # present, prepare, or absent
traefik_data_dir: "~/traefik-data"
traefik_http_port: 8080               # 80 if privileged
traefik_https_port: 8443              # 443 if privileged
traefik_dashboard_port: 9999
traefik_dashboard_enabled: true
traefik_enable_ssl: true
traefik_acme_email: "your@email.com"
traefik_delete_data: false
```

### MinIO

```yaml
minio_state: present                  # present, prepare, or absent
minio_data_dir: "~/minio-data"
minio_api_port: 9000
minio_console_port: 9001
minio_root_user: "minioadmin"
minio_root_password: "your_secure_password"
minio_delete_data: false
```

## Service States

Each service can be in one of these states:

- **prepare**: One-time setup of directories and system configuration
- **present**: Deploy and run the service
- **absent**: Remove the service (optionally delete data)

## Example Inventory File

The `inventory.yml` file defines hosts and service-specific variables:

```yaml
all:
  vars:
    domain: example.org
    ansible_user: youruser
    
  children:
    mylab:
      hosts:
        server1:
          ansible_host: "localhost"
          ansible_connection: local
      
      children:
        elasticsearch_svc:
          hosts:
            server1:
          vars:
            elasticsearch_data_dir: "{{ ansible_env.HOME }}/elasticsearch-data"
            elasticsearch_password: "{{ lookup('env', 'ELASTIC_PASSWORD') }}"
```

## Security Considerations

1. Passwords are set through variables or environment variables
2. TLS is supported for most services
3. SELinux contexts are properly configured on RHEL/CentOS systems
4. Services bind to localhost by default (except Traefik)
5. Data directories are created with appropriate permissions

## Troubleshooting

### Common Issues

1. **Permission denied errors**:
   - Check SELinux contexts with `ls -lZ`
   - Run `restorecon -Rv` on data directories

2. **Container won't start**:
   - Check logs with `podman logs container-name`
   - Verify systemd integration with `systemctl --user status pod-name`

3. **Network issues**:
   - Check container network with `podman network inspect ct-net`
   - Verify DNS configuration in containers

## License

MIT

## Author Information

Created by Jackaltx and Claude
