# HashiVault Role Testing Guide

## Quick Test Commands

### 1. Prepare (One-time Setup)

```bash
./manage-svc.sh hashivault prepare
```

**Expected Results:**
- Creates `~/hashivault-data/` directory structure
- Creates subdirectories: config, data, logs
- Creates container network `ct-net`
- Applies SELinux contexts (RHEL-based systems)

### 2. Deploy Service

```bash
./manage-svc.sh hashivault deploy
```

**Expected Results:**
- Creates Podman pod named `hashivault`
- Creates container `hashivault-svc`
- Generates systemd unit `hashivault-pod.service`
- Starts service automatically
- Vault starts in **SEALED** state (this is normal)
- Runs verification checks

### 3. Initialize Vault (First Time Only)

```bash
# Initialize and save unseal keys
podman exec hashivault-svc vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  > ~/hashivault-init-keys.txt

# IMPORTANT: Save this file securely!
chmod 600 ~/hashivault-init-keys.txt
cat ~/hashivault-init-keys.txt
```

**Expected Results:**
- 5 unseal keys generated
- Root token generated
- Keys and token saved to file
- Vault remains sealed (requires manual unsealing)

**Output Format:**
```text
Unseal Key 1: <key1>
Unseal Key 2: <key2>
Unseal Key 3: <key3>
Unseal Key 4: <key4>
Unseal Key 5: <key5>

Initial Root Token: <root-token>
```

### 4. Unseal Vault

Unsealing requires 3 out of 5 keys:

```bash
# Unseal with 3 keys (use keys from init output)
podman exec hashivault-svc vault operator unseal <key1>
podman exec hashivault-svc vault operator unseal <key2>
podman exec hashivault-svc vault operator unseal <key3>

# Check seal status
podman exec hashivault-svc vault status
```

**Expected Results:**
- First unseal: Progress 1/3
- Second unseal: Progress 2/3
- Third unseal: Vault unsealed, Progress 3/3
- Status shows: `Sealed: false`

### 5. Authenticate with Root Token

```bash
# Set root token as environment variable
export VAULT_TOKEN="<root-token-from-init>"

# Or login interactively
podman exec hashivault-svc vault login <root-token>

# Verify authentication
podman exec hashivault-svc vault token lookup
```

**Expected Results:**
- Authentication successful
- Token details displayed (TTL, policies, etc.)

### 6. Write Test Secret

```bash
# Enable KV secrets engine (if not already enabled)
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault secrets enable -version=2 -path=secret kv

# Write test secret
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv put secret/test password="mySecretPassword" username="testuser"

# Read secret back
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv get secret/test
```

**Expected Results:**
- Secret written successfully
- Secret retrieved with correct values
- Metadata includes version number

### 7. Verify Deployment

```bash
# Automated verification
./svc-exec.sh hashivault verify

# Manual checks
systemctl --user status hashivault-pod
podman ps --filter pod=hashivault
curl -s http://127.0.0.1:8200/v1/sys/health | jq
```

**Expected Results:**
- Pod status: Running
- Container status: Up
- Health endpoint returns: `{"initialized": true, "sealed": false}`
- Port 8200 listening

### 8. Seal Vault (for testing)

```bash
# Seal the vault
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc vault operator seal

# Verify sealed
podman exec hashivault-svc vault status
```

**Expected Results:**
- Vault sealed successfully
- Status shows: `Sealed: true`
- Requires unsealing to access secrets again

### 9. Check Logs

```bash
# Container logs
podman logs hashivault-svc

# Systemd logs
journalctl --user -u hashivault-pod -n 50

# Follow logs in real-time
podman logs -f hashivault-svc

# Audit logs (if enabled)
cat ~/hashivault-data/logs/vault_audit.log
```

**Expected Results:**
- No ERROR messages
- Shows seal/unseal operations
- Shows secret read/write operations

### 10. Remove Service

```bash
# Preserve data
./manage-svc.sh hashivault remove

# Verify removal
systemctl --user status hashivault-pod  # Should fail
podman ps -a | grep hashivault          # Should be empty

# Check data preserved
ls -la ~/hashivault-data/               # Should still exist
ls ~/hashivault-data/data/              # Vault data files preserved
```

**Expected Results:**
- Container stopped and removed
- Pod removed
- Systemd unit removed
- Data directory intact (unsealing keys needed after redeploy)

### 11. Complete Cleanup

```bash
# WARN: This deletes unseal keys - vault will be inaccessible!
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh hashivault remove

# Verify complete removal
ls ~/hashivault-data/                   # Should not exist
podman images | grep hashicorp/vault    # Should be empty
```

## Common Test Scenarios

### Scenario 1: Unseal After Restart

Vault always starts sealed after container restart:

```bash
# Restart service
systemctl --user restart hashivault-pod

# Check status (will be sealed)
podman exec hashivault-svc vault status

# Unseal with 3 keys
podman exec hashivault-svc vault operator unseal <key1>
podman exec hashivault-svc vault operator unseal <key2>
podman exec hashivault-svc vault operator unseal <key3>

# Verify unsealed
podman exec hashivault-svc vault status
```

### Scenario 2: Auto-unseal Script

Create helper script for quick unsealing:

```bash
cat > ~/unseal-vault.sh << 'EOF'
#!/bin/bash
# Read keys from init file
KEYS=$(grep "Unseal Key" ~/hashivault-init-keys.txt | awk '{print $NF}')
KEY_ARRAY=($KEYS)

# Unseal with first 3 keys
for i in 0 1 2; do
  podman exec hashivault-svc vault operator unseal ${KEY_ARRAY[$i]}
done

# Show status
podman exec hashivault-svc vault status
EOF

chmod +x ~/unseal-vault.sh

# Use it
~/unseal-vault.sh
```

### Scenario 3: Port Conflicts

If port 8200 is already in use:

```bash
# Check what's using the port
ss -tlnp | grep 8200

# Override in inventory
# Edit inventory/localhost.yml:
hashivault_port: 8201

# Redeploy
./manage-svc.sh hashivault remove
./manage-svc.sh hashivault deploy
```

### Scenario 4: Remote Host Deployment

```bash
# Add to inventory/podma.yml
hashivault_svc:
  hosts:
    podma:
      hashivault_svc_name: "hashivault-podma"
  vars:
    hashivault_port: 8200

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml hashivault prepare
./manage-svc.sh -h podma -i inventory/podma.yml hashivault deploy

# Initialize remotely (SSH to podma or use -h flag)
ssh podma "podman exec hashivault-svc vault operator init"
```

### Scenario 5: Traefik Integration

```bash
# Enable Traefik (edit inventory)
hashivault_enable_traefik: true

# Update DNS
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly

# Access via HTTPS
curl -sk https://vault.a0a0.org:8080/v1/sys/health | jq
```

### Scenario 6: Backup Vault Data

```bash
# Vault must be unsealed for backup
~/unseal-vault.sh

# Take snapshot (requires root token)
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault operator raft snapshot save /vault/data/vault-backup.snap

# Copy snapshot to host
podman cp hashivault-svc:/vault/data/vault-backup.snap \
  ~/vault-backup-$(date +%Y%m%d).snap

# Verify backup
ls -lh ~/vault-backup-*.snap
```

## Verification Checklist

After deployment, verify:

- [ ] Pod running: `systemctl --user is-active hashivault-pod`
- [ ] Container up: `podman ps --filter name=hashivault-svc`
- [ ] Port 8200 listening: `ss -tlnp | grep 8200`
- [ ] Vault initialized: `podman exec hashivault-svc vault status | grep Initialized`
- [ ] Can unseal: Three keys unseal vault successfully
- [ ] Can authenticate: Root token works
- [ ] Can write secrets: `vault kv put` succeeds
- [ ] Can read secrets: `vault kv get` returns correct data
- [ ] Can seal: `vault operator seal` works
- [ ] Data persists: Secrets survive seal/unseal cycle
- [ ] Logs accessible: `podman logs hashivault-svc`
- [ ] Traefik labels correct (if enabled)

## Troubleshooting Tests

### Test 1: Seal Status

```bash
# Check seal status
podman exec hashivault-svc vault status

# Expected fields:
# - Initialized: true/false
# - Sealed: true/false
# - Unseal Progress: X/3
```

**Expected**: Initialized=true after init, Sealed varies by state

### Test 2: Token Validation

```bash
# Check if token is valid
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault token lookup

# Check token TTL
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault token lookup -format=json | jq '.data.ttl'
```

**Expected**: Token valid, TTL > 0 (or null for root token)

### Test 3: Storage Backend

```bash
# Check storage type (should be raft)
podman exec hashivault-svc vault status -format=json | jq '.storage_type'

# List raft peers
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault operator raft list-peers
```

**Expected**: storage_type="raft", one peer listed (single node)

### Test 4: Secrets Engine Status

```bash
# List enabled secrets engines
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault secrets list

# Check KV engine
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault secrets list -format=json | jq '.["secret/"]'
```

**Expected**: KV v2 engine enabled at secret/ path

### Test 5: Health Endpoint

```bash
# Check health API
curl -s http://127.0.0.1:8200/v1/sys/health | jq

# Expected JSON fields:
# - initialized: true
# - sealed: false (if unsealed)
# - standby: false
```

**Expected**: HTTP 200 (unsealed) or 503 (sealed), JSON response

## Performance Testing

### Initial Startup Time

```bash
# Deploy and time until ready
time (./manage-svc.sh hashivault deploy && \
  until curl -sf http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; do sleep 1; done)
```

**Expected**: < 10 seconds

### Secret Write Performance

```bash
# Write 100 secrets
time for i in {1..100}; do
  podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
    vault kv put secret/test$i value="data$i" >/dev/null
done
```

**Expected**: < 30 seconds (< 0.3s per secret)

### Secret Read Performance

```bash
# Read 100 secrets
time for i in {1..100}; do
  podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
    vault kv get secret/test$i >/dev/null
done
```

**Expected**: < 20 seconds (< 0.2s per secret)

### Container Memory Usage

```bash
podman stats --no-stream --format "{{.Name}}\t{{.MemUsage}}" hashivault-svc
```

**Expected**: < 100MB idle, < 200MB under load

## Functional Testing

### Test 1: KV Secret Operations

```bash
export VAULT_TOKEN="<root-token>"

# Write secret
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv put secret/app db_password="SecurePass123" api_key="abc-xyz-789"

# Read secret
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv get secret/app

# Update secret (creates new version)
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv put secret/app db_password="NewPass456" api_key="abc-xyz-789"

# Read specific version
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv get -version=1 secret/app

# Delete secret
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv delete secret/app
```

**Expected**: All operations succeed, versioning works

### Test 2: Policy Management

```bash
# Create policy file
podman exec hashivault-svc sh -c 'cat > /tmp/app-policy.hcl << EOF
path "secret/data/app/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF'

# Write policy
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault policy write app-policy /tmp/app-policy.hcl

# Create token with policy
APP_TOKEN=$(podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault token create -policy=app-policy -format=json | jq -r '.auth.client_token')

# Test policy permissions
podman exec -e VAULT_TOKEN=$APP_TOKEN hashivault-svc \
  vault kv put secret/app/config setting="value"
```

**Expected**: Policy created, token has restricted permissions

### Test 3: Audit Logging

```bash
# Enable file audit device
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault audit enable file file_path=/vault/logs/audit.log

# Perform operation
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv put secret/test audit="test"

# Check audit log
podman exec hashivault-svc cat /vault/logs/audit.log | tail -5 | jq
```

**Expected**: Audit device enabled, operations logged as JSON

### Test 4: Seal/Unseal Cycle

```bash
# Write secret while unsealed
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv put secret/persist data="should survive seal/unseal"

# Seal vault
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault operator seal

# Verify sealed (should fail)
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv get secret/persist 2>&1

# Unseal
~/unseal-vault.sh

# Read secret (should succeed)
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv get secret/persist
```

**Expected**: Secret survives seal/unseal, inaccessible when sealed

## Regression Testing

Before releasing updates, run complete test suite:

```bash
# Full lifecycle test
./manage-svc.sh hashivault prepare
./manage-svc.sh hashivault deploy

# Initialize and save keys
podman exec hashivault-svc vault operator init > ~/vault-keys.txt
chmod 600 ~/vault-keys.txt

# Extract unseal keys and root token
KEYS=$(grep "Unseal Key" ~/vault-keys.txt | awk '{print $NF}')
KEY_ARRAY=($KEYS)
ROOT_TOKEN=$(grep "Root Token" ~/vault-keys.txt | awk '{print $NF}')

# Unseal
for i in 0 1 2; do
  podman exec hashivault-svc vault operator unseal ${KEY_ARRAY[$i]}
done

# Enable KV and write test secrets
export VAULT_TOKEN=$ROOT_TOKEN
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault secrets enable -version=2 -path=secret kv
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv put secret/test data="regression test $(date)"

# Verify
./svc-exec.sh hashivault verify

# Test seal/unseal cycle
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc vault operator seal
~/unseal-vault.sh
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc vault kv get secret/test

# Remove and verify data preservation
./manage-svc.sh hashivault remove
ls ~/hashivault-data/data/  # Vault data should exist

# Redeploy and unseal
./manage-svc.sh hashivault deploy
~/unseal-vault.sh
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc vault kv get secret/test

# Complete cleanup
rm ~/vault-keys.txt
DELETE_DATA=true ./manage-svc.sh hashivault remove
```

## Integration Testing

### With Traefik (SSL Termination)

```bash
# Deploy both services
./manage-svc.sh traefik deploy
./manage-svc.sh hashivault deploy

# Verify Traefik routing
curl -sk https://vault.a0a0.org:8080/v1/sys/health | jq

# Check Traefik dashboard
curl -s http://localhost:8080/api/http/routers | \
  jq '.[] | select(.name | contains("hashivault"))'
```

**Expected**: HTTPS access works, Traefik routes to Vault

### With Mattermost (Credential Storage)

```bash
# Deploy Mattermost
./manage-svc.sh mattermost deploy

# Store Mattermost credentials in Vault
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv put secret/mattermost \
    postgres_password="MattermostDBPass"

# Retrieve for verification
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault kv get -format=json secret/mattermost | \
  jq -r '.data.data.postgres_password'
```

**Expected**: Credentials stored and retrieved successfully

## Expected Test Results Summary

| Test | Expected Result | Pass/Fail |
|------|-----------------|-----------|
| Prepare | Directories created, SELinux applied | |
| Deploy | Pod + container running, Vault sealed | |
| Initialize | 5 unseal keys + root token generated | |
| Unseal | 3 keys unseal vault | |
| Authenticate | Root token works | |
| Write Secret | KV secret stored | |
| Read Secret | Secret retrieved correctly | |
| Seal | Vault seals, secrets inaccessible | |
| Unseal Again | Vault unseals, secrets accessible | |
| Data Persistence | Secrets survive seal/unseal cycle | |
| Remove | Service stopped, data preserved | |
| Cleanup | All data and images removed | |

## Notes

- **Always save unseal keys securely**: Without them, vault data is permanently inaccessible
- **Root token has unlimited access**: Create limited tokens for applications
- **Vault starts sealed**: This is normal security behavior, must unseal after each restart
- **Unseal keys are NOT passwords**: They decrypt the master encryption key
- **Auto-unseal available**: Can use cloud KMS or Transit engine (not configured in basic setup)
- **Audit logs are verbose**: Can grow large, rotate regularly
- **HA mode**: Requires 3+ nodes with Raft consensus (single node for testing)
- **Backup unsealed**: Snapshots require unsealed state
- **Secrets versioned**: KV v2 keeps version history, can rollback

## Common Errors

### "Vault is sealed"

Vault must be unsealed after every restart:

```bash
~/unseal-vault.sh
```

### "permission denied"

Token expired or insufficient permissions:

```bash
# Renew token
podman exec -e VAULT_TOKEN=$VAULT_TOKEN hashivault-svc \
  vault token renew

# Or use root token
export VAULT_TOKEN="<root-token>"
```

### "storage migration in progress"

Vault is upgrading storage format:

```bash
# Wait for migration to complete
podman logs -f hashivault-svc | grep migration

# Check status
podman exec hashivault-svc vault status
```

### "error initializing listener"

Port conflict or permission issue:

```bash
# Check port availability
ss -tlnp | grep 8200

# Check container logs
podman logs hashivault-svc | grep -i error

# Verify SELinux (RHEL)
ls -Z ~/hashivault-data/
```
