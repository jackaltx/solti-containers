# Mattermost Deployment with Podman

This collection of playbooks and roles manages the deployment of Mattermost using rootless Podman containers. It supports both RHEL/CentOS and Debian-based systems.

## Features

- Rootless Podman deployment
- PostgreSQL database container
- Optional TLS support
- Systemd integration using Quadlets
- Cross-platform support (RHEL/CentOS and Debian)
- SELinux support for RHEL systems

## Prerequisites

- Ansible 2.9 or newer
- Target system running either:
  - RHEL/CentOS 9 or newer
  - Debian 12 (Bookworm) or newer
  - Ubuntu 22.04 or newer
- User with sudo access

## Quick Start

1. Prepare the host system:

```bash
ansible-playbook -K prepare-podman-host.yml
```

2. Deploy Mattermost:

```bash
ansible-playbook deploy-mattermost.yml
```

3. Remove Mattermost (keeping data):

```bash
ansible-playbook remove-mattermost.yml
```

## Configuration

### Default Variables

See `roles/mattermost/defaults/main.yml` for all available variables. Key variables include:

```yaml
mattermost_postgres_password: "change_this_password"
mattermost_port: 8065
mattermost_site_url: ""
mattermost_enable_tls: false
```

### TLS Configuration

To enable TLS, provide these variables:

```yaml
mattermost_enable_tls: true
mattermost_tls_cert_file: "/path/to/cert.pem"
mattermost_tls_key_file: "/path/to/key.pem"
```

## Platform-Specific Notes

### RHEL/CentOS

- Automatically enables required repositories (CRB)
- Configures SELinux contexts for container volumes
- Uses native podman-compose package

### Debian/Ubuntu

- Installs required dependencies via apt
- Installs podman-compose via pip
- No SELinux configuration needed

## Directory Structure

```
mattermost_data_dir/
├── config/
├── data/
├── logs/
├── plugins/
├── client/plugins/
└── postgres/
```

## Systemd Integration

The deployment uses Podman Quadlets for systemd integration. Services are installed in the user's systemd instance:

- pod-mattermost.service
- container-mattermost-db.service
- container-mattermost-svc.service

## Troubleshooting

1. DNS Issues:
   - The playbook configures DNS servers (1.1.1.1 and 8.8.8.8)
   - Check containers.conf if DNS issues persist

2. SELinux (RHEL only):
   - Container contexts are automatically set
   - Run `restorecon -Rv` on data directory if permissions issues occur

3. Podman:
   - Use `podman logs container-name` to check container logs
   - Verify user lingering is enabled: `loginctl user-status $USER`

## Maintenance

### Backup

1. Database:

```bash
podman exec mattermost-db pg_dump -U mmuser mattermost > backup.sql
```

2. Config and Data:

```bash
tar czf mattermost-data.tar.gz ~/mattermost-data
```

### Updates

1. Update container images:

```yaml
mattermost_image: "mattermost/mattermost-team-edition:latest"
mattermost_postgres_image: "postgres:13-alpine"
```

2. Redeploy:

```bash
ansible-playbook deploy-mattermost.yml
```

## License

MIT

## Author Information

Created by Jackaltx. Extended by the community.
