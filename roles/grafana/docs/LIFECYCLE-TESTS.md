# Grafana Lifecycle Tests

This document contains executable lifecycle tests for the Grafana service. These tests validate the complete deployment workflow and can be executed by AI agents or human operators.

## Prerequisites

- Host configured (NOPASSWD sudo recommended, or be prepared for password prompts)
- Environment variable set: `GRAFANA_ADMIN_PASSWORD` (optional, defaults to "changeme")
- Network connectivity to `docker.io`
- Inventory file prepared (`inventory/localhost.yml` or `inventory/podma.yml`)

## Test 1: Fresh Install (Complete Removal and Reinstall)

**Purpose:** Validates new installation on a clean system with current image version.

**Duration:** ~2-3 minutes

**Test Sequence:**

### Step 1: Complete Removal

```bash
# Remove service, data, AND container images (destructive!)
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh -h podma -i inventory/podma.yml grafana remove
```

**Expected outcome:**

- ✓ Service stopped: `grafana-pod.service` inactive
- ✓ Quadlets removed: `grafana-svc.container`, `grafana.pod` deleted
- ✓ Data directories deleted: `~/grafana-data/` removed
- ✓ Container image removed: `docker.io/grafana/grafana:latest` deleted

**Verification:**

```bash
# All of these should fail/return empty
ssh podma.a0a0.org "systemctl --user status grafana-pod"           # Should fail (inactive)
ssh podma.a0a0.org "ls ~/grafana-data"                             # Should fail (no such file)
ssh podma.a0a0.org "podman images | grep grafana"                  # Should be empty
```

---

### Step 2: Prepare

```bash
./manage-svc.sh -h podma -i inventory/podma.yml grafana prepare
```

**Expected outcome:**

- ✓ Directories created (9 total: root, config, data, logs, plugins, provisioning/*)
- ✓ Ownership: user:user (1000:1000 typically)
- ✓ Permissions: 0750
- ✓ SELinux context applied (on RHEL/Rocky/Fedora)

**Verification:**

```bash
ssh podma.a0a0.org "ls -ld ~/grafana-data/"                        # Should exist with correct ownership
ssh podma.a0a0.org "ls -la ~/grafana-data/"                        # Should show all subdirectories
```

**Expected changes:** 2 (directory creation, SELinux context)

---

### Step 3: Deploy

```bash
./manage-svc.sh -h podma -i inventory/podma.yml grafana deploy
```

**Expected outcome:**

- ✓ Container image pulled: `docker.io/grafana/grafana:latest` (latest version)
- ✓ Configuration templated: `grafana.ini` created
- ✓ Network created/verified: `ct-net`
- ✓ Environment file created: `~/.config/containers/systemd/env/grafana.env`
- ✓ Pod quadlet created: `grafana.pod`
- ✓ Container quadlet created: `grafana-svc.container`
- ✓ Systemd daemon reloaded
- ✓ Service started: `grafana-pod.service` active

**Verification:**

```bash
ssh podma.a0a0.org "systemctl --user status grafana-pod"           # Should be active (running)
ssh podma.a0a0.org "podman ps --filter pod=grafana"                # Should show 2 containers
ssh podma.a0a0.org "podman images | grep grafana"                  # Should show grafana image
```

**Expected changes:** 6 (config template, env file, 2 quadlets, service start, handler restart)

---

### Step 4: Initialize

**NOT REQUIRED for Grafana** - auto-initializes on first startup

Skip this step.

---

### Step 5: Verify

```bash
./svc-exec.sh -h podma -i inventory/podma.yml grafana verify
```

**Expected outcome:**

- ✓ Systemd service check passes
- ✓ Container health check passes
- ✓ HTTP API responds (port 3000)
- ✓ Admin login works

**Verification:**

```bash
# Manual verification if automated verify fails
ssh podma.a0a0.org "curl -s http://localhost:3000/api/health" | jq
# Expected: {"commit":"...","database":"ok","version":"..."}

ssh podma.a0a0.org "curl -s -u admin:changeme http://localhost:3000/api/org" | jq
# Expected: {"id":1,"name":"Main Org.",...}
```

**Expected changes:** 0 (read-only verification)

---

### Step 6: Cleanup After Testing

```bash
# If this was just a test, remove everything
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh -h podma -i inventory/podma.yml grafana remove
```

**Expected outcome:** Clean system, ready for next test

---

## Test 2: Upgrade Test

**Purpose:** Validates upgrade path when new image version is available.

**Duration:** ~1-2 minutes

**Prerequisites:** Grafana already deployed (run Test 1 steps 1-3 first, but skip step 6)

### Test Sequence

#### Step 1: Check for upgrades

```bash
./svc-exec.sh -h podma -i inventory/podma.yml grafana check_upgrade
```

**Expected outcome:**

- ✓ Current version detected
- ✓ Latest version checked
- ✓ Upgrade status displayed (available or up-to-date)

**If no upgrade available:** Test complete, system is up-to-date.

**If upgrade available:** Proceed to next step.

---

#### Step 2: Remove old image and redeploy

```bash
# Remove only the image (keep data and configuration)
DELETE_IMAGES=true ./manage-svc.sh -h podma -i inventory/podma.yml grafana remove

# Redeploy (will pull new image)
./manage-svc.sh -h podma -i inventory/podma.yml grafana prepare
./manage-svc.sh -h podma -i inventory/podma.yml grafana deploy
```

**Expected outcome:**

- ✓ New image version pulled
- ✓ Service upgraded
- ✓ Data preserved (existing dashboards, datasources, users intact)

---

#### Step 3: Verify upgrade

```bash
./svc-exec.sh -h podma -i inventory/podma.yml grafana verify
```

**Expected outcome:**

- ✓ All verification passes
- ✓ Version updated (check via API: `/api/health`)
- ✓ Data intact (existing config preserved)

---

## Service-Specific Notes

### Timing Considerations

- Container startup: ~5-10 seconds
- Database initialization: Automatic on first run
- No manual initialization required

### Port Binding

- Internal: 3000
- External (localhost): 3000 (configurable via `grafana_port` in inventory)
- Traefik: Enabled by default (`grafana_enable_traefik: true`)

### Data Persistence

All data persists in `~/grafana-data/`:

- `data/grafana.db` - SQLite database (dashboards, users, datasources)
- `config/grafana.ini` - Configuration file
- `logs/` - Application logs
- `plugins/` - Installed plugins
- `provisioning/` - Provisioning configs (dashboards, datasources)

### Common Issues

**Issue:** Image pull fails

```
Error: error pulling image "docker.io/grafana/grafana:latest": ...
```

**Solution:** Check network connectivity, try manual pull:

```bash
ssh podma.a0a0.org "podman pull docker.io/grafana/grafana:latest"
```

---

**Issue:** Service won't start

```
Job for grafana-pod.service failed
```

**Solution:** Check logs:

```bash
ssh podma.a0a0.org "journalctl --user -u grafana-pod -n 50"
ssh podma.a0a0.org "podman logs grafana-svc"
```

---

**Issue:** Verification fails (HTTP connection refused)

```
curl: (7) Failed to connect to localhost port 3000
```

**Solution:** Wait a few seconds for container to fully start, then retry:

```bash
ssh podma.a0a0.org "podman ps --filter pod=grafana"  # Verify container is up
sleep 10  # Wait for Grafana to initialize
# Retry verification
```

---

## Integration Tests

### Test 3: Traefik Integration (if Traefik deployed)

**Prerequisites:** Traefik service deployed and running

```bash
# Test HTTPS access via Traefik
curl -k https://grafana.a0a0.org:8443/api/health
```

**Expected outcome:**

- ✓ HTTPS connection successful
- ✓ Response: `{"database":"ok",...}`
- ✓ Certificate valid (if Let's Encrypt configured)

---

## Automated Test Execution

All tests can be executed in sequence:

```bash
# Full test cycle (Fresh Install)
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh -h podma -i inventory/podma.yml grafana remove && \
./manage-svc.sh -h podma -i inventory/podma.yml grafana prepare && \
./manage-svc.sh -h podma -i inventory/podma.yml grafana deploy && \
./svc-exec.sh -h podma -i inventory/podma.yml grafana verify

# Check exit code
echo "Test result: $?"  # 0 = success, non-zero = failure
```

---

## CI/CD Integration

These tests are designed for automated execution in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Grafana Lifecycle Test
  run: |
    DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh -y -h testhost -i inventory/ci.yml grafana remove
    ./manage-svc.sh -y -h testhost -i inventory/ci.yml grafana prepare
    ./manage-svc.sh -y -h testhost -i inventory/ci.yml grafana deploy
    ./svc-exec.sh -y -h testhost -i inventory/ci.yml grafana verify
```

**Note:** Use `-y` flag to skip interactive prompts in automation.

---

## Test Matrix

| Host | Inventory | Test Type | Expected Duration |
|------|-----------|-----------|-------------------|
| firefly | localhost.yml | Fresh Install | 2-3 min |
| podma | podma.yml | Fresh Install | 2-3 min |
| podma | podma.yml | Upgrade | 1-2 min |
| firefly | localhost.yml | Upgrade | 1-2 min |

---

## Changelog

- 2025-11-20: Initial lifecycle test documentation created
- Added DELETE_IMAGES support for fresh install testing
