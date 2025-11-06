# Redis Role - Fast Key-Value Store for Testing

## Purpose

Redis provides a fast in-memory key-value store ideal for collecting test results and data during development cycles. This lightweight deployment is perfect for rapid testing iterations where filesystem operations would add unnecessary latency.

## Quick Start

```bash
# Prepare system directories and configuration
./manage-svc.sh redis prepare

# Deploy Redis with Commander GUI
./manage-svc.sh redis deploy

# Verify deployment is working
./svc-exec.sh redis verify

# Clean up (preserves data by default)
./manage-svc.sh redis remove
```

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Features

- **High Performance**: In-memory storage for fastest possible data access
- **Web GUI**: Redis Commander for easy data visualization and management
- **SSL Termination**: Automatic HTTPS via Traefik integration
- **Secure Access**: Password-protected with configurable authentication
- **Development Focused**: Optimized for rapid test iteration cycles

## Architecture

```
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
                              https://redis-ui.yourdomain.com
```

## Access Points

| Interface | URL | Purpose |
|-----------|-----|---------|
| Redis Server | `localhost:6379` | Direct Redis connection |
| Redis Commander | `http://localhost:8081` | Local web interface |
| SSL Endpoint | `https://redis-ui.{{ domain }}` | Traefik-proxied HTTPS access |

## Configuration

### Environment Variables

```bash
# Set Redis password (recommended)
export REDIS_PASSWORD="your_secure_password"
```

### Key Configuration Options

```yaml
# Memory and performance
redis_maxmemory: "256mb"                    # Maximum memory usage
redis_maxmemory_policy: "allkeys-lru"      # Eviction policy

# Security
redis_password: "{{ lookup('env', 'REDIS_PASSWORD') | default('changeme') }}"

# GUI access
redis_enable_gui: true                      # Enable Redis Commander
redis_gui_port: 8081                       # Commander port

# Data persistence
redis_data_dir: "{{ ansible_user_dir }}/redis-data"
```

## Using with Traefik SSL

When Traefik is deployed, Redis Commander automatically gets SSL termination:

```yaml
# Traefik labels automatically applied
- "Label=traefik.enable=true"
- "Label=traefik.http.routers.redis.rule=Host(`redis-ui.{{ domain }}`)"
- "Label=traefik.http.services.redis.loadbalancer.server.port=8081"
```

**Result**: Access Redis Commander securely at `https://redis-ui.yourdomain.com`

## Common Operations

### Verification Tasks

```bash
# Basic health check
./svc-exec.sh redis verify

# Check specific functionality
./svc-exec.sh redis test-connectivity
```

### Data Operations

```bash
# Direct Redis operations via container
podman exec redis-svc redis-cli -a $REDIS_PASSWORD SET test-key "test-value"
podman exec redis-svc redis-cli -a $REDIS_PASSWORD GET test-key

# View Redis info
podman exec redis-svc redis-cli -a $REDIS_PASSWORD INFO
```

### Monitoring

```bash
# View container status
systemctl --user status redis-pod

# Monitor logs
podman logs -f redis-svc

# Resource usage
podman stats redis-svc redis-gui
```

## Integration Examples

### Test Data Collection

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

### Development Workflows

```bash
# Start testing session
./manage-svc.sh redis deploy

# Run your tests (they store data in Redis)
python run_tests.py

# Analyze results via Redis Commander
open https://redis-ui.yourdomain.com

# Clean up when done
./manage-svc.sh redis remove
```

## Performance Tuning

### Memory Optimization

```yaml
# For development/testing workloads
redis_maxmemory: "128mb"        # Small footprint
redis_maxmemory_policy: "allkeys-lru"

# For data collection workloads  
redis_maxmemory: "512mb"        # More storage
redis_maxmemory_policy: "noeviction"
```

### Persistence Settings

```yaml
# Configuration in redis.conf template
save: ""                        # Disable persistence for speed
appendonly: yes                 # Enable AOF for safety
appendfsync: everysec          # Balance safety/performance
```

## Troubleshooting

### Common Issues

**Connection Refused**

```bash
# Check if Redis is running
podman ps | grep redis

# Check port binding
ss -tlnp | grep 6379
```

**Authentication Errors**

```bash
# Verify password is set
echo $REDIS_PASSWORD

# Test connection
podman exec redis-svc redis-cli -a $REDIS_PASSWORD ping
```

**Memory Issues**

```bash
# Check memory usage
podman exec redis-svc redis-cli -a $REDIS_PASSWORD INFO memory

# Monitor container resources
podman stats redis-svc
```

### Log Analysis

```bash
# Redis server logs
podman logs redis-svc | grep -i error

# Container startup issues
journalctl --user -u redis-pod -f
```

## Development Notes

- **Data Lifecycle**: Data persists between container restarts but is removed with `remove` command
- **Testing Integration**: Ideal for storing test metrics, results, and temporary data
- **Performance**: In-memory storage provides sub-millisecond access times
- **Scaling**: Single-instance deployment suitable for development workloads

## Related Services

- **Elasticsearch**: For searchable log analysis alongside Redis caching
- **Traefik**: Provides SSL termination and routing for Redis Commander
- **HashiVault**: Can store Redis passwords and connection credentials

## License

MIT

## Maintained By

Jackaltx - Part of the SOLTI containers collection for development testing workflows.
