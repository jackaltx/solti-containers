# Elasticsearch Role Testing Guide

## Quick Test Commands

### 1. Prepare (One-time Setup)

```bash
./manage-svc.sh elasticsearch prepare
```

**Expected Results:**

- Creates `~/elasticsearch-data/` directory structure
- Creates container network `ct-net`
- Applies SELinux contexts (RHEL-based systems)
- Configures `vm.max_map_count=262144` (required for Elasticsearch)

### 2. Set Password

```bash
export ELASTIC_PASSWORD="your_secure_password"
echo $ELASTIC_PASSWORD  # Verify it's set
```

**Expected Results:**

- Environment variable set for deployment
- Password will be used for `elastic` superuser account

### 3. Deploy Service

```bash
./manage-svc.sh elasticsearch deploy
```

**Expected Results:**

- Creates Podman pod named `elasticsearch`
- Creates containers `elasticsearch-svc` and `elasticsearch-gui`
- Generates systemd unit `elasticsearch-pod.service`
- Starts service automatically
- Elasticsearch initializes (30-60 seconds)
- Runs verification checks

### 4. Verify Deployment

```bash
# Automated verification
./svc-exec.sh elasticsearch verify

# Manual checks
systemctl --user status elasticsearch-pod
podman ps --filter pod=elasticsearch
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200
curl http://127.0.0.1:8088  # Elasticvue GUI
```

**Expected Results:**

- Pod status: Running
- Containers status: Up (elasticsearch-svc, elasticsearch-gui)
- HTTP response: 200 OK with cluster info JSON
- Elasticvue accessible via browser
- Cluster health: green or yellow

### 5. Check Cluster Health

```bash
# Cluster health summary
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_cluster/health?pretty

# Detailed cluster info
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/?pretty
```

**Expected Results:**

```json
{
  "cluster_name": "elasticsearch",
  "status": "green",
  "timed_out": false,
  "number_of_nodes": 1,
  "number_of_data_nodes": 1,
  "active_primary_shards": 0,
  "active_shards": 0,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 0
}
```

### 6. Create Test Index

```bash
# Create index with test document
curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/test-logs/_doc \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "level": "INFO",
    "message": "Test log entry",
    "service": "verification"
  }'

# Verify index created
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_cat/indices?v
```

**Expected Results:**

```text
health status index      uuid   pri rep docs.count docs.deleted store.size pri.store.size
yellow open   test-logs  abc123   1   1          1            0      4.5kb          4.5kb
```

Note: Status "yellow" is normal for single-node cluster (no replicas)

### 7. Search Test Data

```bash
# Search all documents
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/test-logs/_search?pretty

# Search with query
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/test-logs/_search?pretty \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"level": "INFO"}}}'
```

**Expected Results:**

- Documents returned in `hits.hits[]` array
- Total count in `hits.total.value`
- Scores calculated for query matches

### 8. Check Memory Usage

```bash
# JVM heap usage
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_nodes/stats/jvm?pretty | \
  grep -A 5 heap_used_percent

# Container memory stats
podman stats --no-stream elasticsearch-svc --format "{{.Name}}\t{{.MemUsage}}"
```

**Expected Results:**

- JVM heap: 25-75% used (healthy range)
- Container memory: < configured limit (default 1GB)

### 9. Access Elasticvue GUI

```bash
# Open in browser
xdg-open http://127.0.0.1:8088

# Or check it's responding
curl -I http://127.0.0.1:8088
```

**Expected Results:**

- HTTP 200 response
- Elasticvue interface loads in browser
- Can connect to `http://localhost:9200` with username `elastic` and password

### 10. Check Logs

```bash
# Container logs
podman logs elasticsearch-svc | tail -50

# Systemd logs
journalctl --user -u elasticsearch-pod -n 50

# Follow logs in real-time
podman logs -f elasticsearch-svc
```

**Expected Results:**

- No `ERROR` or `FATAL` messages
- `started` message visible
- Cluster state: `green` or `yellow`

### 11. Remove Service

```bash
# Preserve data
./manage-svc.sh elasticsearch remove

# Verify removal
systemctl --user status elasticsearch-pod  # Should fail
podman ps -a | grep elasticsearch          # Should be empty

# Check data preserved
ls -la ~/elasticsearch-data/               # Should still exist
```

### 12. Complete Cleanup

```bash
# Remove data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh elasticsearch remove

# Verify complete removal
ls ~/elasticsearch-data/                   # Should not exist
podman images | grep elasticsearch         # Should be empty
```

## Common Test Scenarios

### Scenario 1: Port Conflicts

If ports 9200 or 8088 are already in use:

```bash
# Check what's using the ports
ss -tlnp | grep -E '9200|8088'

# Override in inventory
# Edit inventory/localhost.yml:
elasticsearch_port: 9201
elasticsearch_gui_port: 8089
```

### Scenario 2: Memory Configuration

Test with different memory settings:

```bash
# Edit inventory/localhost.yml:
elasticsearch_memory: "512m"  # Minimal (development)
# OR
elasticsearch_memory: "2g"    # Heavy workload
# OR
elasticsearch_memory: "4g"    # Large datasets

# Redeploy
./manage-svc.sh elasticsearch remove
./manage-svc.sh elasticsearch deploy

# Verify memory setting
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_nodes/stats/jvm?pretty | \
  grep heap_max_in_bytes
```

### Scenario 3: Index Mapping

Create index with explicit mapping:

```bash
curl -u elastic:$ELASTIC_PASSWORD -X PUT http://127.0.0.1:9200/app-logs \
  -H "Content-Type: application/json" \
  -d '{
    "mappings": {
      "properties": {
        "timestamp": {"type": "date"},
        "level": {"type": "keyword"},
        "message": {"type": "text"},
        "service": {"type": "keyword"},
        "duration_ms": {"type": "integer"}
      }
    }
  }'

# Verify mapping
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/app-logs/_mapping?pretty
```

### Scenario 4: Remote Host Deployment

```bash
# Add to inventory/podma.yml
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

### Scenario 5: Traefik Integration

```bash
# Enable Traefik (edit inventory)
elasticsearch_enable_traefik: true

# Update DNS
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly

# Access via HTTPS
curl -I -k -u elastic:$ELASTIC_PASSWORD https://elasticsearch.a0a0.org:8080
curl -I -k https://es.a0a0.org:8080  # Short alias
```

### Scenario 6: Bulk Document Indexing

```bash
# Create bulk indexing script
cat > /tmp/bulk-index.sh << 'EOF'
#!/bin/bash
for i in {1..100}; do
  curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/test-bulk/_doc \
    -H "Content-Type: application/json" \
    -d '{
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "counter": '$i',
      "message": "Bulk test document '$i'"
    }' -s -o /dev/null
  echo "Indexed document $i"
done
EOF

chmod +x /tmp/bulk-index.sh
/tmp/bulk-index.sh

# Check index stats
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_cat/indices/test-bulk?v
```

## Verification Checklist

After deployment, verify:

- [ ] Pod running: `systemctl --user is-active elasticsearch-pod`
- [ ] Containers up: `podman ps --filter name=elasticsearch`
- [ ] Port 9200 listening: `ss -tlnp | grep 9200`
- [ ] Port 8088 listening: `ss -tlnp | grep 8088`
- [ ] Cluster health green/yellow: `curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_cluster/health`
- [ ] Can create index: Successfully POSTs to `/_doc` endpoint
- [ ] Can search data: `/_search` returns results
- [ ] Elasticvue accessible: Browser loads GUI
- [ ] JVM heap healthy: 25-75% usage
- [ ] Data persists: Index survives restart
- [ ] Logs accessible: `podman logs elasticsearch-svc`
- [ ] Traefik labels correct (if enabled)

## Troubleshooting Tests

### Test 1: Container Health

```bash
podman inspect elasticsearch-svc | jq '.[0].State'
```

Expected: `"Status": "running"`, `"Running": true`, `"ExitCode": 0`

### Test 2: Network Connectivity

```bash
podman exec elasticsearch-svc ping -c 2 1.1.1.1
```

Expected: Successful ping

### Test 3: Volume Mounts

```bash
podman inspect elasticsearch-svc | jq '.[0].Mounts[] | select(.Destination == "/usr/share/elasticsearch/data")'
```

Expected: Source path matches `~/elasticsearch-data/data`

### Test 4: Environment Variables

```bash
podman inspect elasticsearch-svc | jq '.[0].Config.Env' | grep -E 'ES_JAVA_OPTS|ELASTIC_PASSWORD|discovery.type'
```

Expected:

- `ES_JAVA_OPTS=-Xms1g -Xmx1g`
- `ELASTIC_PASSWORD=<password>`
- `discovery.type=single-node`

### Test 5: Memory Limits

```bash
sysctl vm.max_map_count
```

Expected: `262144` (required by Elasticsearch)

### Test 6: Authentication

```bash
# Should succeed
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200 -w "%{http_code}\n" -o /dev/null -s

# Should fail (401)
curl http://127.0.0.1:9200 -w "%{http_code}\n" -o /dev/null -s
```

Expected: First command 200, second command 401

### Test 7: Index Operations

```bash
# Create, read, update, delete
INDEX_ID=$(curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/crud-test/_doc \
  -H "Content-Type: application/json" \
  -d '{"status": "created"}' -s | jq -r '._id')

curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/crud-test/_doc/$INDEX_ID -s | jq '.found'

curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/crud-test/_update/$INDEX_ID \
  -H "Content-Type: application/json" \
  -d '{"doc": {"status": "updated"}}' -s | jq '.result'

curl -u elastic:$ELASTIC_PASSWORD -X DELETE http://127.0.0.1:9200/crud-test/_doc/$INDEX_ID -s | jq '.result'
```

Expected: `found: true`, `result: "updated"`, `result: "deleted"`

## Performance Testing

### Startup Time

```bash
systemctl --user stop elasticsearch-pod
time systemctl --user start elasticsearch-pod

# Wait for ready
until curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200 -s -o /dev/null; do
  echo "Waiting..."
  sleep 2
done
```

Expected: Ready within 30-60 seconds

### Indexing Throughput

```bash
# Index 1000 documents
START=$(date +%s)
for i in {1..1000}; do
  curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/perf-test/_doc \
    -H "Content-Type: application/json" \
    -d '{"index": '$i', "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
    -s -o /dev/null
done
END=$(date +%s)
DURATION=$((END - START))
RATE=$((1000 / DURATION))

echo "Indexed 1000 docs in ${DURATION}s (${RATE} docs/sec)"
```

Expected: > 50 docs/sec on modest hardware

### Search Performance

```bash
# Time search query
time curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/perf-test/_search?size=100 \
  -s -o /dev/null
```

Expected: < 200ms for simple queries

### Container Memory Usage

```bash
podman stats --no-stream elasticsearch-svc --format "{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

Expected:

- Idle: ~400-600MB
- Under load: < configured limit (1GB default)

### JVM Garbage Collection

```bash
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_nodes/stats/jvm?pretty | \
  jq '.nodes[].jvm.gc.collectors'
```

Expected: GC time < 5% of uptime

## Functional Testing

### Index Lifecycle

```bash
# Create index
curl -u elastic:$ELASTIC_PASSWORD -X PUT http://127.0.0.1:9200/lifecycle-test

# Add documents
for i in {1..10}; do
  curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/lifecycle-test/_doc \
    -H "Content-Type: application/json" \
    -d '{"doc_num": '$i'}' -s -o /dev/null
done

# Refresh index
curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/lifecycle-test/_refresh

# Verify count
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/lifecycle-test/_count

# Delete index
curl -u elastic:$ELASTIC_PASSWORD -X DELETE http://127.0.0.1:9200/lifecycle-test

# Verify deleted
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/lifecycle-test -w "%{http_code}\n" -s
```

Expected: 10 documents, 404 after deletion

### Data Persistence

```bash
# Create index with data
curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/persist-test/_doc \
  -H "Content-Type: application/json" \
  -d '{"message": "should survive restart"}'

# Restart service
systemctl --user restart elasticsearch-pod

# Wait for ready (30s max)
sleep 30

# Verify data persists
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/persist-test/_search

# Cleanup
curl -u elastic:$ELASTIC_PASSWORD -X DELETE http://127.0.0.1:9200/persist-test
```

Expected: Document survives restart

### Query Complexity

```bash
# Create test data
for level in ERROR WARN INFO DEBUG; do
  for i in {1..5}; do
    curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/query-test/_doc \
      -H "Content-Type: application/json" \
      -d '{
        "level": "'$level'",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "message": "Test message '$i'"
      }' -s -o /dev/null
  done
done

# Refresh
curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/query-test/_refresh -s -o /dev/null

# Simple match
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/query-test/_search \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"level": "ERROR"}}}'

# Term filter
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/query-test/_search \
  -H "Content-Type: application/json" \
  -d '{"query": {"term": {"level": "WARN"}}}'

# Range query
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/query-test/_search \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "range": {
        "timestamp": {
          "gte": "now-1h"
        }
      }
    }
  }'

# Aggregation
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/query-test/_search \
  -H "Content-Type: application/json" \
  -d '{
    "size": 0,
    "aggs": {
      "levels": {
        "terms": {"field": "level"}
      }
    }
  }'

# Cleanup
curl -u elastic:$ELASTIC_PASSWORD -X DELETE http://127.0.0.1:9200/query-test -s -o /dev/null
```

Expected: All queries return expected results

## Regression Testing

Before releasing updates, run complete test suite:

```bash
# Full lifecycle test
./manage-svc.sh elasticsearch prepare
export ELASTIC_PASSWORD="TestPass123!"
./manage-svc.sh elasticsearch deploy
./svc-exec.sh elasticsearch verify
./manage-svc.sh elasticsearch remove

# With data preservation
./manage-svc.sh elasticsearch deploy
curl -u elastic:$ELASTIC_PASSWORD -X POST http://127.0.0.1:9200/persist-index/_doc \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}' -s -o /dev/null
./manage-svc.sh elasticsearch remove
ls ~/elasticsearch-data/data/  # Should contain data
./manage-svc.sh elasticsearch deploy
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/persist-index/_search  # Should find document
DELETE_DATA=true ./manage-svc.sh elasticsearch remove
ls ~/elasticsearch-data/  # Should NOT exist
```

## Integration Testing

Test with other services:

```bash
# Deploy with Traefik
./manage-svc.sh traefik deploy
./manage-svc.sh elasticsearch deploy

# Verify Traefik routing
curl -I -k https://elasticsearch.a0a0.org:8080
curl -I -k https://es.a0a0.org:8080

# Test with application
# (Example: Log aggregation from fluentd/logstash)
```

## Expected Test Results Summary

| Test | Expected Result | Pass/Fail |
|------|-----------------|-----------|
| Prepare | Directories created, SELinux contexts applied, vm.max_map_count set | |
| Deploy | Pod running, containers up, ports listening | |
| Verify | All checks pass, cluster health green/yellow | |
| Access | API responds with 200, Elasticvue loads | |
| Create Index | Document indexed successfully | |
| Search | Query returns indexed documents | |
| Memory | JVM heap 25-75%, container < limit | |
| Data Persistence | Index survives service restart | |
| Authentication | Valid credentials: 200, invalid: 401 | |
| Traefik SSL | HTTPS access via domain name | |
| Remove | Service stopped, quadlets removed | |
| Cleanup | All data and images removed | |

## Notes

- First startup may take 30-60 seconds for Elasticsearch initialization
- Single-node cluster will have "yellow" health status (no replicas) - this is normal
- `vm.max_map_count` must be >= 262144 (automatically set by prepare task)
- JVM memory is configured via `elasticsearch_memory` (default 1GB)
- Browser caching can affect Elasticvue - use hard refresh (Ctrl+Shift+R)
- SELinux issues show in logs as "Permission denied" - re-run prepare
- Memory errors indicate `elasticsearch_memory` should be increased
- Port conflicts show as "address already in use" - change ports in inventory

## Common Errors

### Error: "max virtual memory areas vm.max_map_count [65530] is too low"

**Symptom**: Container exits immediately after starting

**Fix**:

```bash
# Run prepare again (sets vm.max_map_count automatically)
./manage-svc.sh elasticsearch prepare
```

### Error: "Cluster health timeout"

**Symptom**: Verification fails waiting for cluster health

**Fix**:

```bash
# Check if Elasticsearch started
podman logs elasticsearch-svc | tail -50

# Common causes:
# - Insufficient memory: increase elasticsearch_memory
# - Port conflict: check ss -tlnp | grep 9200
# - Password not set: export ELASTIC_PASSWORD before deploy
```

### Error: "401 Unauthorized"

**Symptom**: API requests fail with authentication error

**Fix**:

```bash
# Verify password is set
echo $ELASTIC_PASSWORD

# Set password and redeploy
export ELASTIC_PASSWORD="your_password"
./manage-svc.sh elasticsearch remove
./manage-svc.sh elasticsearch deploy
```

### Error: "Elasticvue cannot connect to Elasticsearch"

**Symptom**: GUI loads but cannot connect to cluster

**Fix**:

```bash
# In Elasticvue GUI, use:
# URI: http://localhost:9200
# Username: elastic
# Password: <value of ELASTIC_PASSWORD>

# Note: Use localhost, not 127.0.0.1
# Elasticvue runs in browser, connects directly to host
```

### Error: "Index corrupted" or "Shard failures"

**Symptom**: Red cluster health, search failures

**Fix**:

```bash
# Check cluster health details
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_cluster/health?level=indices

# Check disk space
curl -u elastic:$ELASTIC_PASSWORD http://127.0.0.1:9200/_cat/allocation?v
df -h ~/elasticsearch-data/

# If index corrupted, may need to delete and recreate
curl -u elastic:$ELASTIC_PASSWORD -X DELETE http://127.0.0.1:9200/<index-name>
```
