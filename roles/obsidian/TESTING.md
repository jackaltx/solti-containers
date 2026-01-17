# Obsidian Role Testing Guide

## Quick Test Commands

### 1. Prepare (One-time Setup)

```bash
./manage-svc.sh obsidian prepare
```

**Expected Results:**
- Creates `~/obsidian-data/` directory structure
- Creates container network `ct-net`
- Applies SELinux contexts (RHEL-based systems)

### 2. Deploy Service

```bash
./manage-svc.sh obsidian deploy
```

**Expected Results:**
- Creates Podman pod named `obsidian`
- Creates container `obsidian-svc`
- Generates systemd unit `obsidian-pod.service`
- Starts service automatically
- Runs verification checks

### 3. Verify Deployment

```bash
# Automated verification
./svc-exec.sh obsidian verify

# Manual checks
systemctl --user status obsidian-pod
podman ps --filter pod=obsidian
curl -I http://127.0.0.1:3000
```

**Expected Results:**
- Pod status: Running
- Container status: Up
- HTTP response: 200 or 301/302
- HTTPS port 3001 listening
- Service accessible via browser

### 4. Access Application

Open browser to:
- HTTP: <http://127.0.0.1:3000>
- HTTPS: <https://127.0.0.1:3001>

**Expected Results:**
- Obsidian interface loads
- Can create new vault in `/vaults` directory
- Can open existing vault

### 5. Create Test Vault

```bash
# Create sample vault
mkdir -p ~/obsidian-data/vaults/test-vault
echo "# Test Note" > ~/obsidian-data/vaults/test-vault/test.md
echo "This is a test note for Obsidian." >> ~/obsidian-data/vaults/test-vault/test.md

# Open vault in Obsidian (use browser interface)
```

### 6. Check Logs

```bash
# Container logs
podman logs obsidian-svc

# Systemd logs
journalctl --user -u obsidian-pod -n 50

# Follow logs in real-time
podman logs -f obsidian-svc
```

### 7. Remove Service

```bash
# Preserve data
./manage-svc.sh obsidian remove

# Verify removal
systemctl --user status obsidian-pod  # Should fail
podman ps -a | grep obsidian           # Should be empty

# Check data preserved
ls -la ~/obsidian-data/                # Should still exist
```

### 8. Complete Cleanup

```bash
# Remove data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh obsidian remove

# Verify complete removal
ls ~/obsidian-data/                    # Should not exist
podman images | grep obsidian          # Should be empty
```

## Common Test Scenarios

### Scenario 1: Port Conflicts

If ports 3000 or 3001 are already in use:

```bash
# Check what's using the ports
ss -tlnp | grep -E '3000|3001'

# Override in inventory
# Edit inventory/localhost.yml:
obsidian_port: 3002
obsidian_https_port: 3003
```

### Scenario 2: Custom Timezone

```bash
# Edit inventory/localhost.yml:
obsidian_tz: "America/New_York"

# Redeploy
./manage-svc.sh obsidian remove
./manage-svc.sh obsidian deploy
```

### Scenario 3: Remote Host Deployment

```bash
# Add to inventory/podma.yml
obsidian_svc:
  hosts:
    podma:
      obsidian_svc_name: "obsidian-podma"
  vars:
    obsidian_port: 3000
    obsidian_https_port: 3001

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml obsidian prepare
./manage-svc.sh -h podma -i inventory/podma.yml obsidian deploy
```

### Scenario 4: Traefik Integration

```bash
# Enable Traefik (edit inventory)
obsidian_enable_traefik: true

# Update DNS
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly

# Access via HTTPS
curl -I https://obsidian.a0a0.org:8080
```

## Verification Checklist

After deployment, verify:

- [ ] Pod running: `systemctl --user is-active obsidian-pod`
- [ ] Container up: `podman ps --filter name=obsidian-svc`
- [ ] HTTP port listening: `ss -tlnp | grep 3000`
- [ ] HTTPS port listening: `ss -tlnp | grep 3001`
- [ ] Web interface loads in browser
- [ ] Can create/edit vaults
- [ ] Data persists in `~/obsidian-data/vaults/`
- [ ] Logs accessible: `podman logs obsidian-svc`
- [ ] Traefik labels correct (if enabled)

## Troubleshooting Tests

### Test 1: Container Health

```bash
podman inspect obsidian-svc | jq '.[0].State'
```

Expected: `"Status": "running"`, `"Running": true`

### Test 2: Network Connectivity

```bash
podman exec obsidian-svc ping -c 2 1.1.1.1
```

Expected: Successful ping

### Test 3: Volume Mounts

```bash
podman inspect obsidian-svc | jq '.[0].Mounts[] | select(.Destination == "/vaults")'
```

Expected: Source path matches `~/obsidian-data/vaults`

### Test 4: Environment Variables

```bash
podman inspect obsidian-svc | jq '.[0].Config.Env' | grep -E 'PUID|PGID|TZ'
```

Expected: Correct user ID, group ID, and timezone

### Test 5: Resource Limits

```bash
podman inspect obsidian-svc | jq '.[0].HostConfig.ShmSize'
```

Expected: `1073741824` (1GB)

## Performance Testing

### Browser Loading Time

```bash
time curl -I http://127.0.0.1:3000
```

Expected: < 2 seconds

### Container Memory Usage

```bash
podman stats --no-stream obsidian-svc --format "{{.Name}}\t{{.MemUsage}}"
```

Expected: < 500MB idle, < 1.5GB under load

### File I/O Test

```bash
# Create 100 test notes
for i in {1..100}; do
  echo "# Note $i" > ~/obsidian-data/vaults/test-vault/note-$i.md
  echo "Content for note $i" >> ~/obsidian-data/vaults/test-vault/note-$i.md
done

# Check if Obsidian indexes them (via browser)
```

## Regression Testing

Before releasing updates, run complete test suite:

```bash
# Full lifecycle test
./manage-svc.sh obsidian prepare
./manage-svc.sh obsidian deploy
./svc-exec.sh obsidian verify
./manage-svc.sh obsidian remove

# With data preservation
./manage-svc.sh obsidian deploy
echo "Test" > ~/obsidian-data/vaults/persist-test.md
./manage-svc.sh obsidian remove
ls ~/obsidian-data/vaults/persist-test.md  # Should exist
DELETE_DATA=true ./manage-svc.sh obsidian remove
ls ~/obsidian-data/vaults/persist-test.md  # Should NOT exist
```

## Integration Testing

Test with other services:

```bash
# Deploy with Traefik
./manage-svc.sh traefik deploy
./manage-svc.sh obsidian deploy

# Verify Traefik routing
curl -I https://obsidian.a0a0.org:8080

# Deploy with HashiVault (future credential integration)
./manage-svc.sh hashivault deploy
# (credential integration not yet implemented)
```

## Expected Test Results Summary

| Test | Expected Result | Pass/Fail |
|------|-----------------|-----------|
| Prepare | Directories created, SELinux contexts applied | |
| Deploy | Pod running, container up, ports listening | |
| Verify | All checks pass, service accessible | |
| Access | Browser loads Obsidian interface | |
| Create Vault | Vault created, notes editable | |
| Data Persistence | Data survives service restart | |
| Traefik SSL | HTTPS access via domain name | |
| Remove | Service stopped, quadlets removed | |
| Cleanup | All data and images removed | |

## Notes

- First startup may take 30-60 seconds as LinuxServer.io image initializes
- Browser caching can affect testing - use hard refresh (Ctrl+Shift+R)
- SELinux issues show in logs as "Permission denied" - re-run prepare
- Port conflicts show as "address already in use" - change ports in inventory
