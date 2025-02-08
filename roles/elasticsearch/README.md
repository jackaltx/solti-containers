# Elasticsearch Podman Role

This role manages the installation and configuration of Elasticsearch using rootless Podman containers. It includes optional TLS support and Elasticvue as a lightweight GUI interface.

## Features

- Rootless Podman deployment
- Optional TLS/SSL encryption
- Elasticvue GUI interface
- Systemd integration using Quadlets
- Configurable resource limits
- X-Pack security features

## Requirements

- Podman 4.x or later
- Systemd
- User with sudo access
- SELinux if running on RHEL/CentOS (role handles contexts)

## Role Variables

### Installation Options

```yaml
elasticsearch_state: present  # Use 'absent' to remove
elasticsearch_force_reload: false
elasticsearch_delete_data: false  # Set to true to delete data during removal
```

### Container Settings

```yaml
elasticsearch_image: "docker.io/elasticsearch:8.12.1"
elasticsearch_elasticvue_image: "docker.io/cars10/elasticvue:latest"
elasticsearch_port: 9200
elasticsearch_gui_port: 8080
```

### Security Settings

```yaml
elasticsearch_enable_security: true
elasticsearch_password: "change_this_password"
```

### TLS Configuration

```yaml
elasticsearch_enable_tls: false
elasticsearch_tls_cert_file: ""  # Path to your certificate
elasticsearch_tls_key_file: ""   # Path to your private key
elasticsearch_tls_min_version: "TLSv1.2"
elasticsearch_tls_verify_client: "optional"
```

### Resource Settings

```yaml
elasticsearch_memory: "1g"  # JVM heap size
```

See defaults/main.yml for all available variables and their default values.

## Example Playbooks

### Basic Installation

```yaml
- hosts: servers
  roles:
    - role: elasticsearch
      vars:
        elasticsearch_password: "secure_password"
        elasticsearch_memory: "2g"
```

### With TLS Enabled

```yaml
- hosts: servers
  roles:
    - role: elasticsearch
      vars:
        elasticsearch_password: "secure_password"
        elasticsearch_enable_tls: true
        elasticsearch_tls_cert_file: "/path/to/cert.pem"
        elasticsearch_tls_key_file: "/path/to/key.pem"
```

### Removal with Data Cleanup

```yaml
- hosts: servers
  roles:
    - role: elasticsearch
      vars:
        elasticsearch_state: absent
        elasticsearch_delete_data: true
```

## Usage

After deployment:

- Elasticsearch will be available at http(s)://localhost:9200
- Elasticvue GUI will be available at <http://localhost:8080>

### Initial Setup

1. Get the cluster status:

```bash
curl -X GET "localhost:9200/_cluster/health?pretty" -u elastic:${elasticsearch_password}
```

2. Access Elasticvue GUI:
   - Open <http://localhost:8080> in your browser
   - Connect to http(s)://localhost:9200
   - Use credentials: elastic / ${elasticsearch_password}

## Security Considerations

1. Default configuration enables X-Pack security
2. TLS is optional but recommended for production
3. Change default passwords after installation
4. Configure firewall rules as needed
5. Services bind to localhost by default

## License

MIT

## Author Information

Created by jackaltx and claude.
