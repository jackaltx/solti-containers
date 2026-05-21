# DNS Service - Quick Start Guide

Automated DNS management for solti-podman services using Linode DNS.

## Prerequisites

1. **Linode Account** with DNS service enabled
2. **API Token** from Linode (Account → API Tokens)
3. **Ansible Collection**: `ansible-galaxy collection install linode.cloud`
4. **Python dependencies**: `./solti-venv/bin/pip install -r requirements.txt`
5. **Environment Variables**: Set `LINODE_TOKEN` (see below)

## Setup

### 1. Install Linode Collection

```bash
ansible-galaxy collection install linode.cloud
```

### 2. Set API Token

**Option A: Source secrets file (recommended)**
```bash
source ~/.secrets/LabProvision
```

**Option B: Export directly**
```bash
export LINODE_TOKEN="your-linode-api-token-here"
```

**Option C: Add to ~/.bashrc**
```bash
echo 'export LINODE_TOKEN="your-token"' >> ~/.bashrc
source ~/.bashrc
```

### 3. Verify Domain in Linode

Ensure your domain (`a0a0.org`) is configured in Linode DNS:
```bash
curl -H "Authorization: Bearer $LINODE_TOKEN" \
  https://api.linode.com/v4/domains | jq '.data[].domain'
```

## Usage

### Prepare (Check Requirements)

```bash
# Check if collection installed and token set
./manage-svc.sh -i inventory/podma.yml dns_service prepare
```

### Deploy (Create DNS Records)

```bash
# Create CNAME records for all services on podma
source ~/.secrets/LabProvision
./manage-svc.sh -i inventory/podma.yml dns_service deploy
```

**What this does**:
- Discovers all `*_svc_name` variables for `podma` host
- Creates CNAME records: `service-name.a0a0.org → podma.a0a0.org`
- Sets TTL to 60 seconds
- Idempotent (safe to run multiple times)

### Sync (Update DNS)

After adding new services, sync DNS without full deploy:

```bash
./svc-exec.sh -i inventory/podma.yml dns_service sync
```

### Verify (Check Propagation)

```bash
./svc-exec.sh -i inventory/podma.yml dns_service verify
```

**Output example**:
```
DNS Verification Results:
  Total services: 3
  Propagated: 3
  Pending: 0
  Failed: 0

redis-ui-test.a0a0.org → podma.a0a0.org
elasticsearch-test.a0a0.org → podma.a0a0.org
mattermost-test.a0a0.org → podma.a0a0.org
```

### Remove (Delete DNS Records)

```bash
./manage-svc.sh -i inventory/podma.yml dns_service remove
```

**Warning**: This deletes ALL CNAME records for services on the target host.

## Complete Workflow Example

```bash
# 1. Source secrets
source ~/.secrets/LabProvision

# 2. Deploy services on podma
./manage-svc.sh -i inventory/podma.yml -h podma redis deploy
./manage-svc.sh -i inventory/podma.yml -h podma elasticsearch deploy
./manage-svc.sh -i inventory/podma.yml -h podma traefik deploy

# 3. Create DNS records
./manage-svc.sh -i inventory/podma.yml dns_service deploy

# 4. Verify DNS
./svc-exec.sh -i inventory/podma.yml dns_service verify

# 5. Test service URLs (after DNS propagates)
curl https://redis-ui-test.a0a0.org:8080
curl https://elasticsearch-test.a0a0.org:8080
curl https://traefik-test.a0a0.org:8080
```

## DNS Record Structure

For inventory `podma.yml` with domain `a0a0.org`:

**Services discovered**:
```yaml
# inventory/podma.yml
redis_svc:
  hosts:
    podma:
      redis_svc_name: "redis-ui-test"

elasticsearch_svc:
  hosts:
    podma:
      elasticsearch_svc_name: "elasticsearch-test"
```

**DNS records created**:
```
redis-ui-test.a0a0.org       CNAME  podma.a0a0.org  (TTL: 60)
elasticsearch-test.a0a0.org  CNAME  podma.a0a0.org  (TTL: 60)
```

**With Traefik reverse proxy**:
```
https://redis-ui-test.a0a0.org:8080
  ↓ DNS lookup
podma.a0a0.org (your server IP)
  ↓ Traefik SSL termination
redis container (localhost:6379)
```

## Troubleshooting

### "LINODE_TOKEN environment variable not set"

```bash
# Check if token is set
echo $LINODE_TOKEN

# If empty, source secrets file
source ~/.secrets/LabProvision

# Or export manually
export LINODE_TOKEN="your-token"
```

### "linode.cloud collection not found"

```bash
# Install collection
ansible-galaxy collection install linode.cloud

# Verify installation
ansible-galaxy collection list | grep linode
```

### "No *_svc_name variables found"

Check that services are defined in inventory with service names:

```yaml
# inventory/podma.yml
redis_svc:
  hosts:
    podma:
      redis_svc_name: "redis-ui-test"  # ← Required
```

### DNS not propagating

```bash
# Check DNS manually
dig redis-ui-test.a0a0.org CNAME @1.1.1.1

# Wait 60 seconds (TTL) and retry
./svc-exec.sh -i inventory/podma.yml dns_service verify
```

### Test Linode API directly

```bash
# List domains
curl -H "Authorization: Bearer $LINODE_TOKEN" \
  https://api.linode.com/v4/domains | jq

# List DNS records for domain
DOMAIN_ID=$(curl -s -H "Authorization: Bearer $LINODE_TOKEN" \
  https://api.linode.com/v4/domains | \
  jq -r '.data[] | select(.domain=="a0a0.org") | .id')

curl -H "Authorization: Bearer $LINODE_TOKEN" \
  https://api.linode.com/v4/domains/$DOMAIN_ID/records | jq
```

## Advanced Usage

### Custom TTL

```bash
./manage-svc.sh -i inventory/podma.yml dns_service deploy -e dns_ttl=300
```

### Debug Mode

```bash
./svc-exec.sh -i inventory/podma.yml dns_service sync -e dns_debug=true
```

### Dry Run (Check Mode)

```bash
ansible-playbook --check tmp/dns_service-deploy-*.yml
```

## Integration with CI/CD

```yaml
# .github/workflows/deploy.yml
- name: Deploy DNS records
  run: |
    source ~/.secrets/LabProvision
    ./manage-svc.sh -i inventory/podma.yml dns_service deploy
  env:
    LINODE_TOKEN: ${{ secrets.LINODE_TOKEN }}
```

## Security Notes

- **Never commit** `LINODE_TOKEN` to git
- Store in `~/.secrets/LabProvision` (git-ignored)
- Use environment-specific tokens (dev/staging/prod)
- Rotate tokens periodically
- Use HashiVault for production token storage

## See Also

- [roles/dns_service/README.md](../roles/dns_service/README.md) - Full role documentation
- [Linode API Docs](https://www.linode.com/docs/api/domains/)
- [linode.cloud Collection](https://galaxy.ansible.com/ui/repo/published/linode/cloud/)
