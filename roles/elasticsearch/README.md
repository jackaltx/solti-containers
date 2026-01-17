# Elasticsearch Role

Deploys Elasticsearch as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **Elasticsearch** (`docker.io/elasticsearch:8.12.1`) - Search and analytics engine
- **Elasticvue** (`docker.io/cars10/elasticvue:latest`) - Web-based data visualization GUI

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh elasticsearch prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Set required password
export ELASTIC_PASSWORD="your_secure_password"

./manage-svc.sh elasticsearch deploy
```

Deploys and starts Elasticsearch with Elasticvue GUI.

### 3. Verify

```bash
./svc-exec.sh elasticsearch verify
```

Runs health checks and functional tests.

### 4. Access

- **Elasticsearch API**: `http://localhost:9200` (direct API access)
- **Elasticvue GUI**: `http://localhost:8088` (web interface)
- **With Traefik SSL**: `https://elasticsearch.example.com` or `https://es.example.com`

## Configuration

### Environment Variables

```bash
export ELASTIC_PASSWORD="your_secure_password"  # Required for deployment
```

### Inventory Variables

```yaml
# Data and ports
elasticsearch_data_dir: "{{ lookup('env', 'HOME') }}/elasticsearch-data"
elasticsearch_port: 9200
elasticsearch_gui_port: 8088

# Service configuration
elasticsearch_image: "docker.io/elasticsearch:8.12.1"
elasticsearch_gui_image: "docker.io/cars10/elasticvue:latest"
elasticsearch_memory: "1g"                      # JVM heap size
elasticsearch_discovery_type: "single-node"     # Single node cluster

# Security settings
elasticsearch_enable_security: true             # X-Pack security
elasticsearch_password: "{{ lookup('env', 'ELASTIC_PASSWORD') }}"

# Traefik integration
elasticsearch_enable_traefik: false
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/elasticsearch-data/
├── config/          # Elasticsearch configuration files
├── data/            # Indexed data and cluster state (persistent)
├── logs/            # Elasticsearch server logs
└── certs/           # TLS certificates (if TLS enabled)
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status elasticsearch-pod

# Start service
systemctl --user start elasticsearch-pod

# Stop service
systemctl --user stop elasticsearch-pod

# Restart service
systemctl --user restart elasticsearch-pod

# Enable on boot
systemctl --user enable elasticsearch-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u elasticsearch-pod -f

# View container logs
podman logs elasticsearch-svc
podman logs elasticsearch-gui

# View last 50 lines
podman logs --tail 50 elasticsearch-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh elasticsearch remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh elasticsearch remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status elasticsearch-pod

# Check cluster health
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cluster/health

# Test indexing
curl -u elastic:$ELASTIC_PASSWORD -X POST http://localhost:9200/test/_doc \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}'

# Run verification tasks
./svc-exec.sh elasticsearch verify
```

### Data Operations

```bash
# List indices
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cat/indices?v

# Create index with test data
curl -u elastic:$ELASTIC_PASSWORD -X POST http://localhost:9200/logs/_doc \
  -H "Content-Type: application/json" \
  -d '{"message": "Application started", "level": "INFO", "timestamp": "2024-01-01T00:00:00Z"}'

# Search index
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/logs/_search?pretty

# Resource usage
podman stats elasticsearch-svc elasticsearch-gui
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh elasticsearch check_upgrade
```

**Output when updates available:**

```text
TASK [elasticsearch : Display container status]
ok: [firefly] => {
    "msg": "elasticsearch-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [elasticsearch : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: elasticsearch-svc"
}
```

**Output when up-to-date:**

```text
TASK [elasticsearch : Display container status]
ok: [firefly] => {
    "msg": "elasticsearch-svc:Up to date (abc123)"
}

TASK [elasticsearch : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh elasticsearch remove

# 2. Redeploy with latest image
./manage-svc.sh elasticsearch deploy

# 3. Verify new version
./svc-exec.sh elasticsearch verify
```

**Note**: Data in `~/elasticsearch-data/` persists across upgrades.

## Traefik Integration

When Traefik is deployed with `elasticsearch_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates:

- `elasticsearch.example.com` → `firefly.example.com`
- `es.example.com` → `firefly.example.com` (short alias)

1. Access via HTTPS:
   - `https://elasticsearch.example.com`
   - `https://es.example.com`

## Advanced Usage

### API Token Management

Create read-only and read-write API tokens for secure application access:

```bash
# Create tokens (requires separate playbook)
ansible-playbook create-elasticsearch-tokens.yml
```

This creates:

- **Read-only token**: For monitoring and search operations
- **Read-write token**: For indexing and data manipulation
- Tokens saved to `~/data/elasticsearch_api_keys.txt`

**Using API tokens:**

```bash
# Using read-only token
curl -H "Authorization: ApiKey $ES_RO_TOKEN" \
  https://elasticsearch.example.com/_cluster/health

# Using read-write token
curl -H "Authorization: ApiKey $ES_RW_TOKEN" \
  -X POST https://elasticsearch.example.com/logs/_doc \
  -H "Content-Type: application/json" \
  -d '{"message": "Test log entry", "timestamp": "2024-01-01T00:00:00Z"}'
```

### Index Management

```bash
# List all indices
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cat/indices?v

# Delete an index
curl -u elastic:$ELASTIC_PASSWORD -X DELETE http://localhost:9200/test-index

# Create index with mapping
curl -u elastic:$ELASTIC_PASSWORD -X PUT http://localhost:9200/app-logs \
  -H "Content-Type: application/json" \
  -d '{
    "mappings": {
      "properties": {
        "timestamp": {"type": "date"},
        "level": {"type": "keyword"},
        "message": {"type": "text"}
      }
    }
  }'
```

### Integration Examples

**Log Analysis Workflow:**

```python
from elasticsearch import Elasticsearch

# Connect to Elasticsearch
es = Elasticsearch(
    ['https://elasticsearch.example.com'],
    api_key=('ES_RW_TOKEN', ''),
    verify_certs=False
)

# Index log entries
es.index(
    index='application-logs',
    document={
        'timestamp': '2024-01-01T00:00:00Z',
        'level': 'ERROR',
        'message': 'Database connection failed',
        'service': 'api-server'
    }
)

# Search logs
results = es.search(
    index='application-logs',
    query={'match': {'level': 'ERROR'}},
    sort=[{'timestamp': {'order': 'desc'}}]
)
```

**Test Result Collection:**

```bash
# Index test results during CI/CD
curl -H "Authorization: ApiKey $ES_RW_TOKEN" \
  -X POST https://elasticsearch.example.com/test-results/_doc \
  -H "Content-Type: application/json" \
  -d '{
    "test_suite": "unit_tests",
    "passed": 45,
    "failed": 2,
    "duration": 120.5,
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }'
```

### Performance Tuning

**Memory Configuration:**

```yaml
# For development workloads
elasticsearch_memory: "512m"    # Minimal footprint

# For heavy indexing/search
elasticsearch_memory: "2g"      # Better performance

# For large datasets
elasticsearch_memory: "4g"      # Maximum performance
```

**System Resources:**

The role automatically configures:

- Memory lock settings (`bootstrap.memory_lock: true`)
- File descriptor limits (`ulimit nofile=65535`)
- Virtual memory settings (`vm.max_map_count=262144`)

### Resource Limits

Add resource limits in quadlet configuration:

```yaml
quadlet_options:
  - |
    [Container]
    Memory=2G
    CPUQuota=200%
```

## Troubleshooting

### Issue: Memory Errors

**Problem**: OOM errors or Elasticsearch out of memory

**Detection:**

```bash
# Check JVM heap usage
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_nodes/stats/jvm?pretty

# Monitor container resources
podman stats elasticsearch-svc
```

**Resolution**: Increase `elasticsearch_memory` setting

```yaml
elasticsearch_memory: "2g"  # or higher
```

### Issue: Connection Refused

**Problem**: Cannot connect to Elasticsearch on port 9200

**Detection:**

```bash
# Check if Elasticsearch is running
podman ps | grep elasticsearch

# Test local connectivity
curl http://localhost:9200
```

**Resolution**: Ensure Elasticsearch container is running

```bash
systemctl --user status elasticsearch-pod
podman logs elasticsearch-svc
```

### Issue: Authentication Errors

**Problem**: 401 Unauthorized or authentication failures

**Detection:**

```bash
# Verify password is set
echo $ELASTIC_PASSWORD

# Test connection
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200
```

**Resolution**: Set ELASTIC_PASSWORD environment variable before deployment

```bash
export ELASTIC_PASSWORD="your_secure_password"
./manage-svc.sh elasticsearch deploy
```

### Issue: Index Health Problems

**Problem**: Red cluster health or unavailable indices

**Detection:**

```bash
# Check cluster health
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cluster/health?pretty

# List problematic indices
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cat/indices?v&health=red
```

**Resolution**: Check disk space and logs, may need to delete and recreate index

```bash
# Check disk usage
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cat/allocation?v

# View Elasticsearch logs
podman logs elasticsearch-svc
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
elasticsearch_svc:
  hosts:
    podma:
      elasticsearch_svc_name: "elasticsearch-podma"
  vars:
    elasticsearch_port: 9200
    elasticsearch_gui_port: 8088

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml elasticsearch prepare
./manage-svc.sh -h podma -i inventory/podma.yml elasticsearch deploy
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

**Component Architecture:**

```text
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Your Apps     │───▶│  Elasticsearch   │◀───│    Elasticvue      │
│                 │    │   API (9200)     │    │   GUI (8088)       │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                              │                           │
                              └───────────────────────────┘
                                           │
                              ┌──────────────────────┐
                              │       Traefik        │
                              │   (SSL Termination)  │
                              └──────────────────────┘
                                           │
                    ┌────────────────────────────────────────┐
                    │  https://elasticsearch.example.com    │
                    │  https://es.example.com                │
                    └────────────────────────────────────────┘
```

See [docs/Claude-new-quadlet.md](../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- Ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- X-Pack security enabled by default with password authentication
- API tokens recommended for application access over password
- Elasticsearch GUI (Elasticvue) should be restricted to trusted networks

## Links

- [Elasticsearch Official Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Elasticsearch Docker Hub Image](https://hub.docker.com/_/elasticsearch)
- [Elasticvue GitHub](https://github.com/cars10/elasticvue)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs elasticsearch-svc`
2. Systemd logs: `journalctl --user -u elasticsearch-pod`
3. Verification output: `./svc-exec.sh elasticsearch verify`

For Elasticsearch application issues, consult the [official documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html).
