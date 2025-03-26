# Wazuh Podman Deployment with Ansible

This document outlines the structure and components needed for an Ansible role to deploy Wazuh using Podman containers.

## Architecture Overview

The deployment will consist of three main containers:

- **wazuh-manager**: Core Wazuh server with manager and API
- **wazuh-indexer**: Elasticsearch-based indexer for Wazuh data
- **wazuh-dashboard**: Web UI dashboard for visualization

## Directory Structure

```
roles/
└── wazuh-podman/
    ├── defaults/
    │   └── main.yml          # Default variables
    ├── tasks/
    │   ├── main.yml          # Main tasks entry point
    │   ├── prereq.yml        # Prerequisites (podman, directories, etc)
    │   ├── certificates.yml  # Certificate generation for components
    │   ├── manager.yml       # Wazuh manager container deployment
    │   ├── indexer.yml       # Wazuh indexer container deployment
    │   ├── dashboard.yml     # Wazuh dashboard container deployment
    │   └── post_setup.yml    # Post-installation configuration
    ├── templates/
    │   ├── manager/
    │   │   ├── ossec.conf.j2 # Wazuh manager main config
    │   │   └── local_rules.xml.j2
    │   ├── indexer/
    │   │   └── elasticsearch.yml.j2
    │   ├── dashboard/
    │   │   └── opensearch_dashboards.yml.j2
    │   └── podman/
    │       ├── wazuh-manager-container.yaml.j2 # Podman container definitions
    │       ├── wazuh-indexer-container.yaml.j2
    │       └── wazuh-dashboard-container.yaml.j2
    ├── handlers/
    │   └── main.yml          # Handlers for service restarts
    └── vars/
        └── main.yml          # Internal variables
```

## Key Variables

```yaml
# Container image versions
wazuh_manager_image: "wazuh/wazuh-manager:4.7.2"
wazuh_indexer_image: "wazuh/wazuh-indexer:4.7.2"
wazuh_dashboard_image: "wazuh/wazuh-dashboard:4.7.2"

# Network configuration
wazuh_network_name: "wazuh-network"
wazuh_network_subnet: "172.18.1.0/24"

# Ports
wazuh_api_port: 55000
wazuh_manager_port: 1514
wazuh_registration_port: 1515
wazuh_dashboard_port: 8082

# Volume locations
wazuh_data_dir: "/opt/wazuh/data"
wazuh_config_dir: "/opt/wazuh/config"
wazuh_backup_dir: "/opt/wazuh/backup"

# Resource limits
wazuh_indexer_memory: "2g"
wazuh_manager_memory: "1g"
wazuh_dashboard_memory: "1g"

# Certificates
wazuh_certs_dir: "/opt/wazuh/certs"
wazuh_generate_certs: true
wazuh_ca_cert_days: 3650
wazuh_cert_days: 3650

# Security settings
wazuh_admin_password: "{{ vault_wazuh_admin_password }}"
wazuh_api_user: "wazuh-api"
wazuh_api_password: "{{ vault_wazuh_api_password }}"
```

## Implementation Steps

### 1. Prerequisites

- Ensure Podman is installed and properly configured
- Create necessary directories for data persistence
- Set up container network for Wazuh services

### 2. Certificate Generation

- Generate certificates for secure communication between:
  - Wazuh manager and agents
  - Wazuh manager and indexer
  - Wazuh indexer nodes (if clustered)
  - Wazuh dashboard and indexer

### 3. Container Deployment

For each container:

- Create configuration files from templates
- Apply resource limits
- Set up persistent volumes
- Configure network settings
- Deploy containers using Podman

### 4. Post-Setup Configuration

- Initialize the Wazuh indexer
- Set up index patterns in the dashboard
- Create initial users
- Set up agent enrollment password
- Configure basic security policies

## Container Definitions

### Example: Wazuh Manager Container

```yaml
podman_create_args:
  name: "wazuh-manager"
  image: "{{ wazuh_manager_image }}"
  state: started
  restart_policy: "always"
  memory: "{{ wazuh_manager_memory }}"
  network:
    - name: "{{ wazuh_network_name }}"
  publish:
    - "{{ wazuh_manager_port }}:1514/tcp"
    - "{{ wazuh_registration_port }}:1515/tcp"
    - "{{ wazuh_api_port }}:55000/tcp"
  volume:
    - "{{ wazuh_config_dir }}/manager/ossec.conf:/var/ossec/etc/ossec.conf:Z"
    - "{{ wazuh_config_dir }}/manager/local_rules:/var/ossec/etc/rules/local_rules.xml:Z"
    - "{{ wazuh_data_dir }}/manager:/var/ossec/data:Z"
    - "{{ wazuh_certs_dir }}:/var/ossec/certs:Z"
  env:
    INDEXER_URL: "https://wazuh-indexer:9200"
    INDEXER_USERNAME: "admin"
    INDEXER_PASSWORD: "{{ wazuh_admin_password }}"
    FILEBEAT_SSL_VERIFICATION: "none"
```

## Security Considerations

- Use Ansible Vault for sensitive information
- Apply SELinux labels to mounted volumes
- Follow principle of least privilege for container configuration
- Enable TLS for all communications
- Store certificates securely

## Backup Strategy

- Regular backup of persistent data directories
- Certificate backup
- Configuration backup
- Consider point-in-time snapshot if available

## Monitoring Integration

- Configure container health checks
- Set up logging to external systems
- Monitor container resource usage

## Scaling Considerations

- Separate roles for manager, indexer, and dashboard for larger deployments
- Document cluster setup process for future scaling
