# Elasticsearch Role - Search and Analytics Engine

## Purpose

Elasticsearch provides powerful search and analytics capabilities for development and testing. This deployment includes Elasticvue for easy data visualization and is optimized for log analysis, test result indexing, and document search during development cycles.

## Quick Start

```bash
# Set required password
export ELASTIC_PASSWORD="your_secure_password"

# Prepare system directories and configuration
./manage-svc.sh elasticsearch prepare

# Deploy Elasticsearch with Elasticvue GUI
./manage-svc.sh elasticsearch deploy

# Verify deployment and test indexing
./svc-exec.sh elasticsearch verify

# Create API tokens for applications
ansible-playbook create-elasticsearch-tokens.yml

# Clean up (preserves data by default)
./manage-svc.sh elasticsearch remove
```

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Features

- **Full-Text Search**: Advanced search capabilities for documents and logs
- **Analytics Engine**: Aggregations and analytics for test data
- **Elasticvue GUI**: Modern web interface for data visualization
- **SSL Integration**: Automatic HTTPS via Traefik
- **API Token Management**: Secure API access with role-based tokens
- **X-Pack Security**: Built-in authentication and authorization

## Architecture

```
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
                    │  https://elasticsearch.yourdomain.com │
                    │  https://es.yourdomain.com             │
                    └────────────────────────────────────────┘
```

## Access Points

| Interface | URL | Purpose |
|-----------|-----|---------|
| Elasticsearch API | `http://localhost:9200` | Direct API access |
| Elasticvue GUI | `http://localhost:8088` | Local web interface |
| SSL API | `https://elasticsearch.{{ domain }}` | Traefik-proxied HTTPS API |
| SSL API (Short) | `https://es.{{ domain }}` | Alternative HTTPS endpoint |

## Configuration

### Required Environment Variables

```bash
# Elasticsearch requires a strong password
export ELASTIC_PASSWORD="your_secure_password_here"
```

### Key Configuration Options

```yaml
# Container settings
elasticsearch_image: "docker.io/elasticsearch:8.12.1"
elasticsearch_memory: "1g"                    # JVM heap size
elasticsearch_port: 9200                      # API port
elasticsearch_gui_port: 8088                  # Elasticvue port

# Security settings
elasticsearch_enable_security: true          # X-Pack security
elasticsearch_password: "{{ lookup('env', 'ELASTIC_PASSWORD') }}"

# Data persistence
elasticsearch_data_dir: "{{ ansible_facts.user_dir }}/elasticsearch-data"

# Performance tuning
elasticsearch_discovery_type: "single-node"  # Single node cluster
```

### Optional TLS Configuration

```yaml
# Enable TLS for API (in addition to Traefik SSL)
elasticsearch_enable_tls: true
elasticsearch_tls_cert_file: "/path/to/cert.pem"
elasticsearch_tls_key_file: "/path/to/key.pem"
```

## Using with Traefik SSL

Elasticsearch automatically integrates with Traefik for SSL termination:

```yaml
# Multiple domains automatically configured
- "Label=traefik.http.routers.elasticsearch0.rule=Host(`elasticsearch.{{ domain }}`)"
- "Label=traefik.http.routers.elasticsearch1.rule=Host(`es.{{ domain }}`)"
```

**Result**: Access Elasticsearch API securely at:

- `https://elasticsearch.yourdomain.com`
- `https://es.yourdomain.com` (short alias)

## API Token Management

### Creating API Tokens

```bash
# Create read-only and read-write tokens
ansible-playbook create-elasticsearch-tokens.yml
```

This creates:

- **Read-only token**: For monitoring and search operations
- **Read-write token**: For indexing and data manipulation
- Tokens saved to `~/data/elasticsearch_api_keys.txt`

### Using API Tokens

```bash
# Using read-only token
curl -H "Authorization: ApiKey $ES_RO_TOKEN" \
  https://elasticsearch.yourdomain.com/_cluster/health

# Using read-write token  
curl -H "Authorization: ApiKey $ES_RW_TOKEN" \
  -X POST https://elasticsearch.yourdomain.com/logs/_doc \
  -H "Content-Type: application/json" \
  -d '{"message": "Test log entry", "timestamp": "2024-01-01T00:00:00Z"}'
```

## Common Operations

### Verification and Testing

```bash
# Basic health and functionality check
./svc-exec.sh elasticsearch verify

# Verify via localhost
./svc-exec.sh elasticsearch verify-localhost

# Verify via Traefik proxy (requires tokens)
./svc-exec.sh elasticsearch verify-proxy
```

### Data Operations

```bash
# Check cluster health
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cluster/health

# Create an index with test data
curl -u elastic:$ELASTIC_PASSWORD -X POST http://localhost:9200/logs/_doc \
  -H "Content-Type: application/json" \
  -d '{"message": "Application started", "level": "INFO", "timestamp": "2024-01-01T00:00:00Z"}'

# Search the index
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/logs/_search?pretty
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

## Integration Examples

### Log Analysis Workflow

```python
from elasticsearch import Elasticsearch

# Connect to Elasticsearch
es = Elasticsearch(
    ['https://elasticsearch.yourdomain.com'],
    api_key=('ES_RW_TOKEN', ''),  # Use your API key
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

### Test Result Collection

```bash
# Index test results during CI/CD
curl -H "Authorization: ApiKey $ES_RW_TOKEN" \
  -X POST https://elasticsearch.yourdomain.com/test-results/_doc \
  -H "Content-Type: application/json" \
  -d '{
    "test_suite": "unit_tests",
    "passed": 45,
    "failed": 2,
    "duration": 120.5,
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }'

# Query test trends
curl -H "Authorization: ApiKey $ES_RO_TOKEN" \
  https://elasticsearch.yourdomain.com/test-results/_search?pretty \
  -H "Content-Type: application/json" \
  -d '{
    "query": {"range": {"timestamp": {"gte": "now-7d"}}},
    "aggs": {
      "daily_results": {
        "date_histogram": {
          "field": "timestamp",
          "calendar_interval": "day"
        }
      }
    }
  }'
```

## Performance Tuning

### Memory Configuration

```yaml
# For development workloads
elasticsearch_memory: "512m"    # Minimal footprint

# For heavy indexing/search
elasticsearch_memory: "2g"      # Better performance

# For large datasets
elasticsearch_memory: "4g"      # Maximum performance
```

### System Resources

The role automatically configures:

- Memory lock settings (`bootstrap.memory_lock: true`)
- File descriptor limits (`ulimit nofile=65535`)
- Virtual memory settings (`vm.max_map_count=262144`)

## Monitoring and Maintenance

### Health Monitoring

```bash
# Container status
systemctl --user status elasticsearch-pod

# Resource usage
podman stats elasticsearch-svc elasticsearch-gui

# Elasticsearch metrics
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_nodes/stats?pretty
```

### Log Analysis

```bash
# Container logs
podman logs elasticsearch-svc | grep -i error

# Elasticsearch slow logs
podman exec elasticsearch-svc tail -f /usr/share/elasticsearch/logs/elasticsearch.log
```

### Data Management

```bash
# Check disk usage
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cat/allocation?v

# Clean up old indices
curl -u elastic:$ELASTIC_PASSWORD -X DELETE http://localhost:9200/old-logs-*
```

## Troubleshooting

### Common Issues

**Memory Errors**

```bash
# Check JVM heap usage
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_nodes/stats/jvm?pretty

# Adjust memory settings
# Edit elasticsearch_memory in inventory
```

**Connection Issues**

```bash
# Check if Elasticsearch is running
podman ps | grep elasticsearch

# Test local connectivity
curl http://localhost:9200

# Check authentication
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200
```

**Index Problems**

```bash
# Check cluster health
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cluster/health?pretty

# List problematic indices
curl -u elastic:$ELASTIC_PASSWORD http://localhost:9200/_cat/indices?v&health=red
```

## Development Workflows

### Development Testing

```bash
# Quick deployment for testing
export ELASTIC_PASSWORD="dev_password_123"
./manage-svc.sh elasticsearch deploy

# Create test index and data
curl -u elastic:$ELASTIC_PASSWORD -X POST http://localhost:9200/test/_doc \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'

# Use Elasticvue for visual inspection
open http://localhost:8088

# Clean up when done
./manage-svc.sh elasticsearch remove
```

### CI/CD Integration

```bash
# Deploy for testing
./manage-svc.sh elasticsearch deploy

# Run tests that index results
pytest tests/ --elasticsearch-url=http://localhost:9200

# Analyze results
./svc-exec.sh elasticsearch verify

# Archive and clean up
./manage-svc.sh elasticsearch remove
```

## Security Best Practices

1. **Strong Passwords**: Always set `ELASTIC_PASSWORD` to a strong value
2. **API Tokens**: Use role-specific API tokens instead of elastic user
3. **Network Access**: Elasticsearch binds to localhost by default
4. **SSL/TLS**: Use Traefik for SSL termination in development
5. **Regular Updates**: Keep Elasticsearch image updated

## Related Services

- **Redis**: Use for fast caching alongside Elasticsearch search
- **Traefik**: Provides SSL termination and routing
- **HashiVault**: Can store Elasticsearch passwords and API tokens
- **Mattermost**: Can send search results and alerts

## License

MIT

## Maintained By

Jackaltx - Part of the SOLTI containers collection for development testing workflows.
