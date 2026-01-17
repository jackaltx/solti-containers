# Traefik Role

Deploys Traefik as a rootless Podman container with systemd integration using the quadlet pattern for centralized SSL termination in development environments.

## Overview

This role deploys:

- **Traefik** (`traefik:v3.3`) - Modern reverse proxy and load balancer with automatic SSL
- **Let's Encrypt Integration** - Automatic SSL certificate provisioning via DNS challenge
- **Service Discovery** - Automatic routing configuration via container labels

## Features

- **Centralized SSL Termination**: Let's Encrypt handles all SSL certificates
- **Automatic Renewals**: No manual certificate management
- **Service Discovery**: Detects services via Podman labels
- **Real HTTPS Testing**: Test with actual certificates instead of self-signed
- **Production-like Routing**: Simulate real deployment scenarios
- **Development Optimized**: Simplified configuration for rapid iteration

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role
- **Real domain** with DNS hosted at a supported provider (Linode DNS by default)
- DNS API token for Let's Encrypt DNS challenge

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh traefik prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Set DNS API token for Let's Encrypt
export LINODE_TOKEN="your_linode_api_token"

# Configure wildcard DNS to point to your host
# *.yourdomain.com → 192.168.1.100

./manage-svc.sh traefik deploy
```

Deploys Traefik with Let's Encrypt integration and service discovery.

### 3. Verify

```bash
# Quick health check
./svc-exec.sh traefik test

# Full verification with routing details
./svc-exec.sh traefik verify

# Diagnostic mode (detailed API inspection)
./svc-exec.sh traefik verify1
```

Expected output from `test`:

```text
✅ Traefik API responding
Dashboard: http://localhost:9999
Version: 3.3.3
```

Expected output from `verify`:

```text
🚀 TRAEFIK STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
API: ✅ ONLINE
Routes: 8
Services: 6

redis-ui.yourdomain.com ➜ redis
mattermost.yourdomain.com ➜ mattermost

🔗 CONNECTIVITY TESTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
redis-ui.yourdomain.com ➜ ✅ 200
mattermost.yourdomain.com ➜ 🔒 401
```

### 4. Access

- **Dashboard**: `http://localhost:9999` (management interface)
- **HTTP/HTTPS Traffic**: Port 8080 (`0.0.0.0:8080`)
- **HTTPS Alternative**: Port 8443 (`0.0.0.0:8443`)
- **Service URLs**: `https://<service>.yourdomain.com:8080`

## Configuration

### Environment Variables

```bash
export LINODE_TOKEN="your_api_token"    # DNS provider API token for Let's Encrypt
```

### Inventory Variables

```yaml
# Data and ports
traefik_data_dir: "{{ lookup('env', 'HOME') }}/traefik-data"
traefik_http_port: 8080
traefik_https_port: 8443
traefik_dashboard_port: 9999

# Service configuration
traefik_image: "docker.io/library/traefik:v3.3"
traefik_log_level: "INFO"
traefik_acme_email: "admin@{{ domain }}"

# DNS provider (default: Linode)
traefik_dns_provider: "linode"

# Development mode
traefik_insecure_api: true    # Dashboard without authentication
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/traefik-data/
├── config/              # Traefik configuration files
│   ├── traefik.yaml     # Main configuration
│   └── dynamic/         # Dynamic configuration
│       └── middleware.yaml  # Security headers
├── acme/                # Let's Encrypt certificates
│   └── acme.json        # Certificate storage (600 permissions)
└── logs/                # Access and error logs
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status traefik-pod

# Start service
systemctl --user start traefik-pod

# Stop service
systemctl --user stop traefik-pod

# Restart service
systemctl --user restart traefik-pod

# Enable on boot
systemctl --user enable traefik-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u traefik-pod -f

# View container logs
podman logs traefik-svc

# Filter for ACME certificate logs
podman logs traefik-svc | grep -i acme

# View last 50 lines
podman logs --tail 50 traefik-svc
```

### Remove

```bash
# Preserve certificates and configuration
./manage-svc.sh traefik remove

# Delete all data including certificates
TRAEFIK_DELETE_DATA=true ./manage-svc.sh traefik remove
```

**Warning**: Deleting ACME data requires re-requesting certificates from Let's Encrypt (subject to rate limits).

## Verification

### Verification Commands

Three verification levels are available:

**Quick Test** (`./svc-exec.sh traefik test`):

- Verifies API is responding
- Shows dashboard URL and version

**Standard Verification** (`./svc-exec.sh traefik verify`):

- Shows routing table
- Tests connectivity to configured services
- Displays HTTP status codes

**Diagnostic Mode** (`./svc-exec.sh traefik verify1`):

- Detailed API structure inspection
- Troubleshooting output for debugging

### Manual Verification

```bash
# Check service status
systemctl --user status traefik-pod

# Verify API endpoint
curl -s http://localhost:9999/api/overview | jq

# List all routers
curl -s http://localhost:9999/api/http/routers | jq

# List all services
curl -s http://localhost:9999/api/http/services | jq

# Test specific route
curl -H 'Host: myservice.yourdomain.com' http://localhost:8080

# View dashboard in browser
open http://localhost:9999
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh traefik check_upgrade
```

**Output when updates available:**

```text
TASK [traefik : Display container status]
ok: [firefly] => {
    "msg": "traefik-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}
```

**Output when up-to-date:**

```text
TASK [traefik : Display container status]
ok: [firefly] => {
    "msg": "traefik-svc:Up to date (abc123)"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh traefik remove

# 2. Redeploy with latest image
./manage-svc.sh traefik deploy

# 3. Verify new version
./svc-exec.sh traefik verify
```

**Note**: ACME certificates in `~/traefik-data/acme/` persist across upgrades.

## Traefik Integration

### Service Label Configuration

Add these labels to your service containers for automatic routing:

```yaml
quadlet_options:
  - "Label=traefik.enable=true"
  - "Label=traefik.http.routers.myservice.rule=Host(`myservice.{{ domain }}`)"
  - "Label=traefik.http.routers.myservice.entrypoints=websecure"
  - "Label=traefik.http.routers.myservice.service=myservice"
  - "Label=traefik.http.services.myservice.loadbalancer.server.port=8080"
  - "Label=traefik.http.routers.myservice.middlewares=secHeaders@file"
```

**Result**: Service accessible at `https://myservice.yourdomain.com:8080` with automatic SSL

### Redis Commander Example

```yaml
# In redis role quadlet configuration
quadlet_options:
  - "Label=traefik.enable=true"
  - "Label=traefik.http.routers.redis.rule=Host(`redis-ui.{{ domain }}`)"
  - "Label=traefik.http.routers.redis.entrypoints=websecure"
  - "Label=traefik.http.routers.redis.service=redis"
  - "Label=traefik.http.services.redis.loadbalancer.server.port=8081"
  - "Label=traefik.http.routers.redis.middlewares=secHeaders@file"
```

**Result**: Redis Commander gets HTTPS at `https://redis-ui.yourdomain.com:8080`

### DNS Configuration

**Wildcard DNS Setup:**

1. Configure DNS A record: `*.yourdomain.com` → `your_host_ip`
2. Set DNS API token for Let's Encrypt DNS challenge
3. Deploy Traefik to automatically provision certificates

**Supported DNS Providers:**

- Linode (default)
- Cloudflare
- AWS Route53
- Google Cloud DNS
- 100+ other providers

To change provider, update `traefik.yaml.j2` template.

## Advanced Usage

### Custom Middleware

Security headers middleware is configured by default in `dynamic/middleware.yaml`:

```yaml
http:
  middlewares:
    secHeaders:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
```

### Port Configuration

| Port | Purpose | Binding | Configuration |
|------|---------|---------|---------------|
| 8080 | HTTP/HTTPS | `0.0.0.0:8080` | Main entrypoint for web traffic |
| 8443 | HTTPS Alt | `0.0.0.0:8443` | Alternative HTTPS port |
| 9999 | Dashboard | `127.0.0.1:9999` | Management UI (localhost only) |

### Let's Encrypt Rate Limits

Be aware of Let's Encrypt rate limits:

- 50 certificates per registered domain per week
- 5 duplicate certificates per week
- Use staging environment for testing: set `traefik_acme_staging: true`

## Troubleshooting

### Issue: No Routes Showing

**Problem**: Services not appearing in Traefik dashboard

**Detection:**

```bash
# Check if containers have proper labels
podman inspect myservice | jq '.Config.Labels'

# Verify Traefik can see services
./svc-exec.sh traefik verify1
```

**Resolution**: Ensure containers have correct Traefik labels and are on `ct-net`

```bash
# Verify container network
podman inspect myservice | jq '.[0].NetworkSettings.Networks'

# Check Traefik logs for discovery errors
podman logs traefik-svc | grep -i error
```

### Issue: SSL Certificate Errors

**Problem**: Certificate not being issued or renewed

**Detection:**

```bash
# Check ACME logs
podman logs traefik-svc | grep -i acme

# Verify DNS provider token
echo $LINODE_TOKEN

# Check certificate storage
ls -la ~/traefik-data/acme/
cat ~/traefik-data/acme/acme.json | jq
```

**Resolution**: Verify DNS API token and check rate limits

```bash
# Test DNS provider credentials
# Ensure LINODE_TOKEN is set before deployment
export LINODE_TOKEN="your_token"

# Use staging environment for testing
# Set in inventory: traefik_acme_staging: true

# Check Let's Encrypt status
curl https://letsencrypt.status.io/
```

### Issue: Connectivity Problems

**Problem**: Cannot access services through Traefik

**Detection:**

```bash
# Test specific route
curl -H 'Host: myservice.yourdomain.com' http://localhost:8080

# Check router configuration
curl -s http://localhost:9999/api/http/routers | jq

# View dashboard
open http://localhost:9999
```

**Resolution**: Verify routing rules and service health

```bash
# Check service is running
podman ps | grep myservice

# Verify service port matches label
podman port myservice-svc

# Test direct service access
curl http://localhost:service_port
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml
traefik_svc:
  hosts:
    podma:
      traefik_svc_name: "traefik-podma"
  vars:
    traefik_http_port: 8080
    traefik_https_port: 8443
    traefik_dashboard_port: 9999

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml traefik prepare
./manage-svc.sh -h podma -i inventory/podma.yml traefik deploy

# Verify
./svc-exec.sh -h podma -i inventory/podma.yml traefik verify
```

**Note**: Each remote host needs its own DNS configuration and API token.

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

### How It Works

```text
Internet → Your Domain → Traefik → Your Apps
                          ↓
                    Let's Encrypt
                    (Real SSL Certs)
```

**Flow:**

1. **Container Discovery**: Traefik discovers services via Podman labels
2. **Automatic SSL**: Let's Encrypt provides certificates via DNS challenge
3. **Routing**: Traffic automatically routed to correct service with HTTPS

**Component Architecture:**

```text
┌─────────────────┐
│  Let's Encrypt  │
└────────┬────────┘
         │ DNS Challenge
         ▼
┌─────────────────┐     ┌──────────────┐
│     Traefik     │────▶│  Dashboard   │
│  (Port 8080)    │     │ (Port 9999)  │
└────────┬────────┘     └──────────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌─────────┐ ┌─────────┐
│ Redis   │ │Mattermost│
│ Service │ │ Service │
└─────────┘ └─────────┘
```

See [docs/Container-Role-Architecture.md](../../docs/Container-Role-Architecture.md) for complete pattern documentation.

## Security Considerations

### Development Focus

This configuration is optimized for **development ease**, not production security:

- Dashboard is publicly accessible (insecure mode)
- No rate limiting configured
- No advanced security features enabled
- Single-container deployment (not HA)

### Security Features

- Containers run rootless under your user account
- Dashboard binds to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Real SSL certificates from Let's Encrypt
- Security headers middleware included (HSTS, XSS protection, etc.)
- ACME certificate storage protected with 600 permissions

### Production Hardening

For production use, consider:

- Enable dashboard authentication
- Configure rate limiting
- Add IP whitelisting
- Implement access logs analysis
- Use certificate pinning
- Deploy with high availability

## Links

- [Traefik Official Documentation](https://doc.traefik.io/traefik/)
- [Traefik Docker Hub Image](https://hub.docker.com/_/traefik)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Traefik DNS Providers](https://doc.traefik.io/traefik/https/acme/#providers)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs traefik-svc`
2. Systemd logs: `journalctl --user -u traefik-pod`
3. Verification output: `./svc-exec.sh traefik verify`
4. Dashboard: `http://localhost:9999`

For Traefik application issues, consult the [official documentation](https://doc.traefik.io/traefik/).

## Related Services

- **Redis**: Add SSL termination to Redis Commander web interface
- **Mattermost**: Secure Mattermost deployments with automatic HTTPS
- **Elasticsearch**: SSL-enabled Elasticsearch access
- **Grafana**: HTTPS access to monitoring dashboards
- **All container services**: Any service with Traefik labels gets automatic SSL
