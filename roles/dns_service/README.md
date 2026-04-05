# DNS Service Role

Manages DNS records for container services using the Linode DNS API.

> **Migration Note**: This role replaces the deprecated `update-dns.sh` and `update-dns-auto.sh` bash scripts (removed Jan 2026). The dns_service role provides the same functionality with better integration, verification capabilities, and support for multiple inventories.

## Overview

The `dns_service` role automatically creates/updates/removes DNS CNAME records for all services deployed on a host. It integrates with the existing `manage-svc.sh` and `svc-exec.sh` workflow.

## Features

- **Auto-discovery**: Finds all `*_svc_name` variables in inventory
- **Idempotent**: Uses `linode.cloud` collection for reliable DNS management
- **State-based**: Follows same prepare/deploy/remove pattern as other services
- **Verification**: Check DNS propagation status
- **Multi-host**: Manage DNS for different inventories independently

## Requirements

- Linode DNS provider account
- `linode.cloud` Ansible collection
- `LINODE_TOKEN` environment variable

### Install Collection

```bash
ansible-galaxy collection install linode.cloud
```

## Usage

### Lifecycle Management (manage-svc.sh)

**Prepare** - Check requirements:
```bash
./manage-svc.sh -i inventory/podma.yml dns_service prepare
```

**Deploy** - Create DNS records for all services:
```bash
export LINODE_TOKEN="your-api-token"
./manage-svc.sh -i inventory/podma.yml dns_service deploy
```

**Remove** - Delete all DNS records:
```bash
./manage-svc.sh -i inventory/podma.yml dns_service remove
```

### Task Execution (svc-exec.sh)

**Sync** - Update DNS records (idempotent):
```bash
./svc-exec.sh -i inventory/podma.yml dns_service sync
```

**Verify** - Check DNS propagation:
```bash
./svc-exec.sh -i inventory/podma.yml dns_service verify
```

## How It Works

1. **Auto-discovery**: Scans inventory for `*_svc_name` variables on target host
2. **CNAME Creation**: Creates `service-name.domain.com → host.domain.com`
3. **Idempotent**: Updates existing records, creates missing ones
4. **Verification**: Uses `dig` to check DNS propagation

## Example Workflow

```bash
# Initial setup for podma host
export LINODE_TOKEN="your-token-here"

# Deploy services
./manage-svc.sh -i inventory/podma.yml redis deploy
./manage-svc.sh -i inventory/podma.yml elasticsearch deploy
./manage-svc.sh -i inventory/podma.yml traefik deploy

# Create DNS records for all deployed services
./manage-svc.sh -i inventory/podma.yml dns_service deploy

# Verify DNS propagation
./svc-exec.sh -i inventory/podma.yml dns_service verify

# Later: Add new service and sync DNS
./manage-svc.sh -i inventory/podma.yml mattermost deploy
./svc-exec.sh -i inventory/podma.yml dns_service sync

# When decommissioning host
./manage-svc.sh -i inventory/old-host.yml dns_service remove
```

## Variables

### Defaults (roles/dns_service/defaults/main.yml)

```yaml
dns_provider: linode              # Currently only Linode supported
dns_ttl: 60                       # TTL in seconds
dns_target_host: "{{ inventory_hostname }}.{{ domain }}"
dns_verify_timeout: 300           # Max wait for propagation (seconds)
dns_verify_interval: 10           # Check interval (seconds)
dns_debug: false                  # Enable debug output
```

### Required Variables

- `domain` - Domain name (from inventory group_vars/all.yml)
- `LINODE_TOKEN` - API token (environment variable)

### Discovered Variables

The role automatically discovers service names from inventory:
- `elasticsearch_svc_name` → Creates `elasticsearch-test.a0a0.org`
- `redis_svc_name` → Creates `redis-ui-test.a0a0.org`
- `mattermost_svc_name` → Creates `mattermost-test.a0a0.org`

## DNS Record Structure

For host `podma` with domain `a0a0.org`:

```
redis-ui-test.a0a0.org         → CNAME podma.a0a0.org
elasticsearch-test.a0a0.org    → CNAME podma.a0a0.org
mattermost-test.a0a0.org       → CNAME podma.a0a0.org
```

Combined with Traefik SSL termination:
```
https://redis-ui-test.a0a0.org:8080 → Traefik → redis container
```

## Integration with Inventory

The role works with the standard inventory structure:

```yaml
# inventory/podma.yml
all:
  vars:
    domain: a0a0.org

  children:
    mylab:
      hosts:
        podma:
          ansible_host: "podma.a0a0.org"

      children:
        redis_svc:
          hosts:
            podma:
              redis_svc_name: "redis-ui-test"

        elasticsearch_svc:
          hosts:
            podma:
              elasticsearch_svc_name: "elasticsearch-test"
```

## Troubleshooting

**Collection not found**:
```bash
ansible-galaxy collection install linode.cloud
```

**API token error**:
```bash
export LINODE_TOKEN="your-api-token"
# Test token
curl -H "Authorization: Bearer $LINODE_TOKEN" https://api.linode.com/v4/domains
```

**No services discovered**:
- Check inventory has `*_svc_name` variables defined
- Verify host is in service group (`redis_svc`, `elasticsearch_svc`, etc.)

**DNS not propagating**:
- TTL is 60 seconds by default
- Use `./svc-exec.sh dns_service verify` to check status
- Wait up to 5 minutes for global propagation

## Future Enhancements

- Support for A records (direct IP mapping)
- Multiple DNS providers (Cloudflare, Route53)
- Automatic wildcard certificate management
- DNS backup/restore functionality
