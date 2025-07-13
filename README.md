# Ansible Collection - jackaltx.solti_containers

A comprehensive Ansible collection for deploying and managing containerized services using Podman and Quadlets with systemd integration.

## Quick Start

```bash
# Prepare system for a service
./manage-svc.sh elasticsearch prepare

# Deploy a service
./manage-svc.sh elasticsearch deploy

# Verify deployment
./svc-exec.sh elasticsearch verify

# Remove service (preserves data)
./manage-svc.sh elasticsearch remove
```

## Overview

The SOLTI containers project provides infrastructure-as-code solutions for deploying various services in containers. It uses a modular approach with a common `_base` role that handles shared functionality across all services.

### Why This Project Exists

Modern development and testing requires lightweight, ephemeral services that can be quickly deployed, tested, and removed. Virtual machines are too heavy for rapid iteration cycles. This collection addresses the need for:

- **Consistent deployment patterns** across different services
- **Lightweight testing environments** using containers instead of VMs
- **Easy service lifecycle management** (prepare → deploy → verify → remove)
- **Standardized configuration** with security best practices
- **Rapid iteration** for development and testing workflows

## Service Philosophy

Each service serves specific testing and development needs:

- **Mattermost**: Private notification collector with mobile/desktop integration
- **HashiVault**: Comprehensive secrets management for development workflows  
- **Redis**: Fast key-value store for test result collection
- **Elasticsearch**: Search and analytics for log analysis and testing
- **Traefik**: Modern reverse proxy for container networking
- **MinIO**: S3-compatible storage for development and testing

## Key Features

- **Rootless Podman deployment** - Enhanced security without privileged containers
- **Systemd integration using Quadlets** - Modern container service management
- **Cross-platform support** - RHEL/CentOS and Debian-based systems
- **Shell script wrappers** - Simplified management without complex Ansible commands
- **SELinux support** - Proper security contexts on RHEL systems
- **Consistent patterns** - All services follow the same deployment methodology

## Supported Services

| Service | Purpose | Default Port | Status |
|---------|---------|--------------|--------|
| **Elasticsearch** | Search and analytics engine | 9200 | ✅ Production Ready |
| **HashiVault** | Secrets management | 8200 | ✅ Production Ready |
| **Mattermost** | Team collaboration platform | 8065 | ✅ Production Ready |
| **Redis** | In-memory data store | 6379 | ✅ Production Ready |
| **Traefik** | HTTP reverse proxy | 8080/8443 | ✅ Production Ready |
| **MinIO** | S3-compatible object storage | 9000/9001 | ✅ Production Ready |
| **Wazuh** | Security monitoring | 443/55000 | 🚧 In Development |

## Prerequisites

- Podman 4.x or later
- Systemd with user services enabled
- User with sudo access (for system preparation)
- SELinux (handled automatically on RHEL/CentOS)

## Management Scripts

### Service Lifecycle Management (`manage-svc.sh`)

```bash
# Prepare system for service deployment
./manage-svc.sh <service> prepare

# Deploy and start service
./manage-svc.sh <service> deploy

# Remove service (preserves data by default)
./manage-svc.sh <service> remove
```

### Service Operations (`svc-exec.sh`)

```bash
# Verify service is running correctly
./svc-exec.sh <service> verify

# Execute service-specific tasks
./svc-exec.sh <service> configure
./svc-exec.sh <service> backup

# Use sudo for privileged operations
./svc-exec.sh -K <service> <task>
```

## Example Workflows

### Setting Up a Development Environment

```bash
# Set up multiple services for development
./manage-svc.sh redis prepare
./manage-svc.sh redis deploy

./manage-svc.sh elasticsearch prepare  
./manage-svc.sh elasticsearch deploy

./manage-svc.sh mattermost prepare
./manage-svc.sh mattermost deploy

# Verify all services
./svc-exec.sh redis verify
./svc-exec.sh elasticsearch verify
./svc-exec.sh mattermost verify
```

### Testing and Cleanup

```bash
# Run tests against services
./svc-exec.sh elasticsearch verify
./svc-exec.sh redis verify

# Clean shutdown (preserves data)
./manage-svc.sh elasticsearch remove
./manage-svc.sh redis remove
./manage-svc.sh mattermost remove
```

## Architecture

### The `_base` Role Pattern

All service roles extend a common `_base` role that provides:

1. **Directory management** - Consistent data and config directories
2. **SELinux configuration** - Proper security contexts
3. **Network setup** - Container networking configuration  
4. **Systemd integration** - Service management via Quadlets
5. **Cleanup processes** - Consistent removal procedures

### Deployment States

Each service supports three primary states:

- **prepare**: One-time system setup (directories, permissions, SELinux)
- **present**: Deploy and run the service
- **absent**: Remove service (optionally delete data)

## Configuration

### Common Variables

```yaml
service_network: "ct-net"             # Container network name
service_dns_servers:                  # DNS servers for containers
  - "1.1.1.1"
  - "8.8.8.8"
service_dns_search: "example.com"     # DNS search domain
```

### Service-Specific Configuration

Each service has extensive configuration options. See individual service documentation:

- [Elasticsearch README](roles/elasticsearch/README.md)
- [HashiVault README](roles/hashivault/README.md)
- [Mattermost README](roles/mattermost/README.md)
- [Redis README](roles/redis/README.md)
- [Traefik README](roles/traefik/README.md)

## Security Best Practices

1. **Rootless containers** - All services run without root privileges
2. **Localhost binding** - Services bind to 127.0.0.1 by default
3. **Strong passwords** - Configurable via environment variables
4. **TLS support** - Available for most services
5. **SELinux integration** - Proper contexts on RHEL systems
6. **Data isolation** - Service data stored in user directories

## Development and Testing

### Adding New Services

Follow the established pattern documented in [Solti-Container-Pattern.md](docs/Solti-Container-Pattern.md):

1. Create role following the standard structure
2. Implement the four core tasks (prerequisites, containers, systemd, cleanup)
3. Add Quadlet templates for systemd integration
4. Include verification tasks
5. Update management scripts

### Testing Framework

- **Molecule testing** - See [molecule-strategy.md](molecule-strategy.md)
- **Verification tasks** - Each service includes health checks
- **Cross-platform testing** - RHEL and Debian family support

## Troubleshooting

### Common Issues

1. **SELinux contexts** - Run `sudo restorecon -Rv <data_directory>`
2. **Container networking** - Check `podman network inspect ct-net`
3. **Service status** - Use `systemctl --user status <service>-pod`
4. **Port conflicts** - Verify ports aren't already in use

### Debug Information

```bash
# Check container status
podman ps --all

# View service logs
podman logs <container-name>

# Check systemd status
systemctl --user status <service>-pod

# Verify network
podman network inspect ct-net
```

## Future Development

### Planned Services

- **Jepson** - Fuzzing framework
- **Trivy** - Vulnerability scanner
- **Additional monitoring tools**

### Roadmap

- Enhanced testing framework with Molecule
- Improved documentation and examples
- Additional platform support
- Performance optimization

## Contributing

1. Follow the established service pattern
2. Include comprehensive documentation
3. Add verification tasks for all services
4. Test on both RHEL and Debian platforms
5. Update management scripts as needed

## License

MIT

## Author Information

Created by Jackaltx with significant assistance from Claude AI for pattern development and documentation.
