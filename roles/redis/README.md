# Redis Role

Deploys Redis as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **Redis Server** (`redis:latest`) - Fast in-memory key-value store
- **Redis Commander** (optional) - Web-based GUI for data visualization

## Features

- **High Performance**: In-memory storage for fastest possible data access
- **Web GUI**: Redis Commander for easy data visualization and management
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management
- **Traefik Support**: Optional SSL termination and reverse proxy
- **Upgrade Detection**: Built-in check for image updates
- **Development Focused**: Optimized for rapid test iteration cycles

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh redis prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Set Redis password (recommended)
export REDIS_PASSWORD="your_secure_password"

./manage-svc.sh redis deploy
```

Deploys and starts the service with Redis server and Commander GUI.

### 3. Verify

```bash
./svc-exec.sh redis verify
```

Runs health checks and functional tests.

### 4. Access

- **Redis Server**: `localhost:6379` (direct connection)
- **Redis Commander**: `http://localhost:8081` (web interface)
- **With Traefik SSL**: `https://redis-ui.a0a0.org:8080`

## Configuration

### Environment Variables

```bash
export REDIS_PASSWORD="your_secure_password"  # Redis authentication (default: changeme)
```

### Inventory Variables

```yaml
# Data and ports
redis_data_dir: "{{ lookup('env', 'HOME') }}/redis-data"
redis_port: 6379
redis_gui_port: 8081

# Service configuration
redis_image: "docker.io/library/redis:latest"
redis_gui_image: "docker.io/rediscommander/redis-commander:latest"
redis_enable_gui: true
redis_maxmemory: "256mb"
redis_maxmemory_policy: "allkeys-lru"

# Traefik integration
redis_enable_traefik: false
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/redis-data/
├── config/          # Redis configuration files
├── data/            # Redis RDB/AOF files (persistent)
└── logs/            # Redis server logs
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status redis-pod

# Start service
systemctl --user start redis-pod

# Stop service
systemctl --user stop redis-pod

# Restart service
systemctl --user restart redis-pod

# Enable on boot
systemctl --user enable redis-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u redis-pod -f

# View container logs
podman logs redis-svc
podman logs redis-gui

# View last 50 lines
podman logs --tail 50 redis-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh redis remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh redis remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status redis-pod

# Check container logs
podman logs redis-svc

# Test Redis connection
podman exec redis-svc redis-cli -a $REDIS_PASSWORD ping

# Run verification tasks
./svc-exec.sh redis verify
```

### Data Operations

```bash
# Direct Redis operations via container
podman exec redis-svc redis-cli -a $REDIS_PASSWORD SET test-key "test-value"
podman exec redis-svc redis-cli -a $REDIS_PASSWORD GET test-key

# View Redis info
podman exec redis-svc redis-cli -a $REDIS_PASSWORD INFO

# Resource usage
podman stats redis-svc redis-gui
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh redis check_upgrade
```

**Output when updates available:**

```text
TASK [redis : Display container status]
ok: [firefly] => {
    "msg": "redis-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [redis : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: redis-svc"
}
```

**Output when up-to-date:**

```text
TASK [redis : Display container status]
ok: [firefly] => {
    "msg": "redis-svc:Up to date (abc123)"
}

TASK [redis : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh redis remove

# 2. Redeploy with latest image
./manage-svc.sh redis deploy

# 3. Verify new version
./svc-exec.sh redis verify
```

**Note**: Data in `~/redis-data/` persists across upgrades.

## Traefik Integration

When Traefik is deployed with `redis_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates: `redis-ui.a0a0.org` → `firefly.a0a0.org`

1. Access via HTTPS:
   - `https://redis-ui.a0a0.org:8080`

## Advanced Usage

### Integration Examples

**Test Data Collection:**

```python
import redis

# Connect to Redis
r = redis.Redis(host='localhost', port=6379, password='your_password')

# Store test results
r.set('test:result:1', json.dumps({
    'test_name': 'api_response_time',
    'result': 'pass',
    'duration': 0.25,
    'timestamp': time.time()
}))

# Retrieve and analyze
results = r.keys('test:result:*')
```

**Development Workflows:**

```bash
# Start testing session
./manage-svc.sh redis deploy

# Run your tests (they store data in Redis)
python run_tests.py

# Analyze results via Redis Commander
open https://redis-ui.a0a0.org:8080

# Clean up when done
./manage-svc.sh redis remove
```

### Performance Tuning

**Memory Optimization:**

```yaml
# For development/testing workloads
redis_maxmemory: "128mb"        # Small footprint
redis_maxmemory_policy: "allkeys-lru"

# For data collection workloads
redis_maxmemory: "512mb"        # More storage
redis_maxmemory_policy: "noeviction"
```

**Persistence Settings:**

```yaml
# Configuration in redis.conf template
save: ""                        # Disable persistence for speed
appendonly: yes                 # Enable AOF for safety
appendfsync: everysec          # Balance safety/performance
```

### Resource Limits

Add resource limits in `quadlet_rootless.yml`:

```yaml
quadlet_options:
  - |
    [Container]
    Memory=512M
    CPUQuota=100%
```

## Troubleshooting

### Issue: Connection Refused

**Problem**: Cannot connect to Redis on port 6379

**Detection:**

```bash
# Check if Redis is running
podman ps | grep redis

# Check port binding
ss -tlnp | grep 6379
```

**Resolution**: Ensure Redis container is running and port is correctly bound

```bash
systemctl --user status redis-pod
podman logs redis-svc
```

### Issue: Authentication Errors

**Problem**: NOAUTH Authentication required or wrong password

**Detection:**

```bash
# Verify password is set
echo $REDIS_PASSWORD

# Test connection
podman exec redis-svc redis-cli -a $REDIS_PASSWORD ping
```

**Resolution**: Set REDIS_PASSWORD environment variable before deployment

```bash
export REDIS_PASSWORD="your_secure_password"
./manage-svc.sh redis deploy
```

### Issue: Memory Errors

**Problem**: OOM errors or Redis running out of memory

**Detection:**

```bash
# Check memory usage
podman exec redis-svc redis-cli -a $REDIS_PASSWORD INFO memory

# Monitor container resources
podman stats redis-svc
```

**Resolution**: Increase `redis_maxmemory` or change eviction policy

```yaml
redis_maxmemory: "512mb"
redis_maxmemory_policy: "allkeys-lru"  # or "volatile-lru", "noeviction"
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
redis_svc:
  hosts:
    podma:
      redis_svc_name: "redis-podma"
  vars:
    redis_port: 6379
    redis_gui_port: 8081

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml redis prepare
./manage-svc.sh -h podma -i inventory/podma.yml redis deploy
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

**Component Architecture:**

```text
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Your Tests    │───▶│    Redis     │◀───│ Redis Commander │
│                 │    │   (Port 6379)│    │   (Port 8081)   │
└─────────────────┘    └──────────────┘    └─────────────────┘
                              │                      │
                              └──────────────────────┘
                                       │
                              ┌──────────────────┐
                              │     Traefik      │
                              │  (SSL Termination)│
                              └──────────────────┘
                                       │
                              https://redis-ui.a0a0.org:8080
```

See [docs/Claude-new-quadlet.md](../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- Ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- Password authentication required for Redis access
- Redis Commander access should be restricted to trusted networks

## Links

- [Redis Official Documentation](https://redis.io/docs/)
- [Redis Docker Hub Image](https://hub.docker.com/_/redis)
- [Redis Commander GitHub](https://github.com/joeferner/redis-commander)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs redis-svc`
2. Systemd logs: `journalctl --user -u redis-pod`
3. Verification output: `./svc-exec.sh redis verify`

For Redis application issues, consult the [official documentation](https://redis.io/docs/).

## Related Services

- **Elasticsearch**: For searchable log analysis alongside Redis caching
- **Traefik**: Provides SSL termination and routing for Redis Commander
- **HashiVault**: Can store Redis passwords and connection credentials
