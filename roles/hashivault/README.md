# HashiVault Role

Deploys HashiCorp Vault as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **HashiCorp Vault** (`hashicorp/vault:1.15`) - Comprehensive secrets management system
- **Integrated Web UI** - Built-in web interface for vault management

## Features

- **Multiple Secret Engines**: KV v2, PKI, SSH, Transit encryption
- **Authentication Methods**: Token, Username/Password, AppRole
- **Development UI**: Built-in web interface for easy management
- **SSL Integration**: Automatic HTTPS via Traefik
- **Initialization Automation**: Secure key generation and storage
- **Policy Management**: Role-based access control
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management
- **Upgrade Detection**: Built-in check for image updates

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh hashivault prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Optional: Set admin password
export VAULT_ADMIN_PASSWORD="your_secure_admin_password"

./manage-svc.sh hashivault deploy

# Initialize Vault (first time only)
./svc-exec.sh hashivault initialize

# Configure authentication and policies
./svc-exec.sh hashivault configure

# Set up secret engines and initial data
./svc-exec.sh hashivault vault-secrets
```

Deploys Vault, initializes with unseal keys, and configures authentication.

### 3. Verify

```bash
./svc-exec.sh hashivault verify
```

Runs health checks and functional tests.

### 4. Access

- **Vault API**: `http://localhost:8200` (direct API access)
- **Web UI**: `http://localhost:8200/ui` (local web interface)
- **With Traefik SSL**: `https://vault.example.com:8080`
- **Alternate Route**: `https://hashivault.example.com:8080`

## Configuration

### Environment Variables

```bash
export VAULT_ADDR="http://localhost:8200"           # Vault API endpoint
export VAULT_ADMIN_PASSWORD="your_secure_password"  # Admin user password (optional)
```

### Inventory Variables

```yaml
# Data and ports
vault_data_dir: "{{ lookup('env', 'HOME') }}/vault-data"
vault_api_port: 8200
vault_cluster_port: 8201

# Container image
vault_image: "docker.io/hashicorp/vault:1.15"

# Service configuration
vault_enable_ui: true
vault_enable_audit: true
vault_storage_type: "file"  # Options: file, raft, consul

# TLS (disabled by default, use Traefik instead)
vault_enable_tls: false

# Traefik integration
hashivault_enable_traefik: true
hashivault_svc_name: "vault"          # Primary route: vault.example.com
hashivault_svc_name_alt: "hashivault" # Alternate route: hashivault.example.com
hashivault_external_port: 8080
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/vault-data/
├── config/          # Vault configuration files
├── data/            # Encrypted vault data (persistent)
├── logs/            # Audit and service logs
└── tls/             # TLS certificates (if vault_enable_tls: true)
```

**Important**: Unseal keys stored separately in `~/.secrets/vault-secrets/vault-keys.json`

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status vault-pod

# Start service
systemctl --user start vault-pod

# Stop service
systemctl --user stop vault-pod

# Restart service
systemctl --user restart vault-pod

# Enable on boot
systemctl --user enable vault-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u vault-pod -f

# View container logs
podman logs vault-svc

# View last 50 lines
podman logs --tail 50 vault-svc

# View audit logs (if enabled)
tail -f ~/vault-data/logs/vault-audit.log
```

### Remove

```bash
# Preserve data (vault data and unseal keys)
./manage-svc.sh hashivault remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh hashivault remove
```

**Warning**: Deleting data removes vault storage and unseal keys. Vault will need re-initialization.

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status vault-pod

# Check vault status
podman exec vault-svc vault status

# Run verification tasks
./svc-exec.sh hashivault verify
```

Expected output from `vault status`:

```text
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
Total Shares    5
Threshold       3
Version         1.15.x
```

## Vault Operations

### Unsealing Vault

Vault seals automatically on restart and requires unsealing:

```bash
# Unseal after container restart
./svc-exec.sh hashivault unseal
```

**How it works**: Uses stored keys from `~/.secrets/vault-secrets/vault-keys.json` (3 of 5 shares required)

### Managing Secrets

```bash
# Store a secret
podman exec vault-svc vault kv put kv/myapp/config \
  database_url="postgres://user:pass@db:5432/mydb" \
  api_key="secret_key_123"

# Retrieve a secret
podman exec vault-svc vault kv get kv/myapp/config

# Retrieve specific field
podman exec vault-svc vault kv get -field=api_key kv/myapp/config

# List secrets
podman exec vault-svc vault kv list kv/
```

### Certificate Management

```bash
# Generate a certificate
podman exec vault-svc vault write pki/issue/server \
  common_name="myapp.example.com" \
  ttl="24h"

# List certificates
podman exec vault-svc vault list pki/certs
```

### User Management

```bash
# Create additional user
podman exec vault-svc vault write auth/userpass/users/developer \
  password="dev_password" \
  policies="readonly"

# List users
podman exec vault-svc vault list auth/userpass/users
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh hashivault check_upgrade
```

**Output when updates available:**

```text
TASK [hashivault : Display container status]
ok: [localhost] => {
    "msg": "vault-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [hashivault : Summary of upgrade status]
ok: [localhost] => {
    "msg": "UPDATES AVAILABLE for: vault-svc"
}
```

**Output when up-to-date:**

```text
TASK [hashivault : Display container status]
ok: [localhost] => {
    "msg": "vault-svc:Up to date (abc123)"
}

TASK [hashivault : Summary of upgrade status]
ok: [localhost] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Backup vault data (recommended)
./svc-exec.sh hashivault backup

# 2. Remove current deployment
./manage-svc.sh hashivault remove

# 3. Redeploy with latest image
./manage-svc.sh hashivault deploy

# 4. Unseal vault
./svc-exec.sh hashivault unseal

# 5. Verify new version
./svc-exec.sh hashivault verify
```

**Note**: Vault data in `~/vault-data/` and unseal keys in `~/.secrets/vault-secrets/` persist across upgrades.

## Traefik Integration

When Traefik is deployed with `hashivault_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly
```

This creates:
- `vault.example.com` → `firefly.example.com`
- `hashivault.example.com` → `firefly.example.com`

2. Access via HTTPS:
   - `https://vault.example.com:8080` (primary)
   - `https://hashivault.example.com:8080` (alternate)

### Traefik Labels

Automatically configured:

```yaml
- "Label=traefik.http.routers.vault-primary.rule=Host(`vault.{{ domain }}`)"
- "Label=traefik.http.routers.vault-secondary.rule=Host(`hashivault.{{ domain }}`)"
```

## Advanced Usage

### Vault Initialization Workflow

Complete setup sequence:

```bash
# 1. Deploy Vault container
./manage-svc.sh hashivault deploy

# 2. Initialize with unseal keys (first time only)
./svc-exec.sh hashivault initialize
# Creates:
# - 5 unseal key shares (3 required to unseal)
# - Root token for initial configuration
# - Keys stored in ~/.secrets/vault-secrets/vault-keys.json

# 3. Configure authentication methods and policies
./svc-exec.sh hashivault configure
# Creates:
# - Admin user with secure password
# - UserPass authentication method
# - AppRole authentication method
# - Admin and read-only policies

# 4. Initialize secret engines
./svc-exec.sh hashivault vault-secrets
# Sets up:
# - KV v2 engine for general secrets
# - PKI engine for certificate management
# - SSH engine for key signing
# - Transit engine for encryption services

# 5. Verify deployment
./svc-exec.sh hashivault verify
```

### Secret Organization

Default secret structure:

```text
kv/
├── ansible/vault              # Ansible vault passwords
├── services/
│   ├── elasticsearch          # ES credentials and tokens
│   ├── mattermost             # MM database passwords
│   └── redis                  # Redis authentication
└── providers/
    ├── linode                 # API tokens
    ├── proxmox                # Infrastructure credentials
    └── gitea                  # Git service tokens
```

### Initial Secrets Configuration

Configure via inventory:

```yaml
vault_initial_secrets:
  - path: "kv/services/elasticsearch"
    data:
      elastic_password: "{{ lookup('env', 'ELASTIC_PASSWORD') }}"
      es_ro_token: "{{ lookup('env', 'ES_RO_TOKEN') }}"
      es_rw_token: "{{ lookup('env', 'ES_RW_TOKEN') }}"

  - path: "kv/providers/linode"
    data:
      linode_token: "{{ lookup('env', 'LINODE_TOKEN') }}"
```

### Integration Examples

**Python Application:**

```python
import hvac

# Connect to Vault
client = hvac.Client(url='http://localhost:8200')

# Authenticate
client.auth.userpass.login(
    username='admin',
    password='your_admin_password'
)

# Read secrets
secret = client.secrets.kv.v2.read_secret_version(
    path='services/elasticsearch'
)
elastic_password = secret['data']['data']['elastic_password']
```

**Environment Loading:**

```bash
# Load secrets into environment
eval $(vault kv get -format=json kv/myapp/config | \
  jq -r '.data.data | to_entries[] | "export \(.key)=\(.value)"')
```

### Policy Management

Policies are managed via role configuration:

```yaml
vault_policies:
  - name: "developer"
    rules: |
      path "kv/data/development/*" {
        capabilities = ["create", "read", "update", "delete", "list"]
      }
      path "kv/data/production/*" {
        capabilities = ["read", "list"]
      }
```

### Backup Operations

```bash
# Built-in backup task
./svc-exec.sh hashivault backup
```

Creates timestamped backup of:
- Vault data directory
- Configuration files
- Encrypted unseal keys

## Troubleshooting

### Issue: Vault Sealed

**Problem**: Vault shows "Sealed: true" and won't accept requests

**Detection:**

```bash
# Check seal status
podman exec vault-svc vault status
```

Output shows:

```text
Sealed          true
```

**Resolution**: Unseal with stored keys

```bash
./svc-exec.sh hashivault unseal
```

### Issue: Authentication Errors

**Problem**: Cannot authenticate with username/password

**Detection:**

```bash
# List auth methods
podman exec vault-svc vault auth list

# Test authentication
podman exec vault-svc vault login -method=userpass \
  username=admin password=your_password
```

**Resolution**: Verify auth method is enabled and user exists

```bash
# Re-run configuration
./svc-exec.sh hashivault configure

# Verify user exists
podman exec vault-svc vault list auth/userpass/users
```

### Issue: Storage Permission Errors

**Problem**: Vault fails to start with permission errors

**Detection:**

```bash
# Check container logs
podman logs vault-svc

# Check file permissions
ls -la ~/vault-data/
```

**Resolution**: Fix ownership and SELinux contexts

```bash
# Remove and redeploy (preserves data)
./manage-svc.sh hashivault remove
./manage-svc.sh hashivault prepare
./manage-svc.sh hashivault deploy
```

### Issue: Lost Unseal Keys

**Problem**: Cannot unseal vault after key loss

**Detection:**

Keys stored in `~/.secrets/vault-secrets/vault-keys.json` are missing or corrupted.

**Resolution**:

**If backup exists:**

```bash
# Restore from backup
cp ~/vault-backups/vault-keys-YYYYMMDD.json ~/.secrets/vault-secrets/vault-keys.json
./svc-exec.sh hashivault unseal
```

**If no backup:**

```text
Vault data is permanently sealed. You must:
1. Remove vault: ./manage-svc.sh hashivault remove
2. Delete data: DELETE_DATA=true ./manage-svc.sh hashivault remove
3. Re-initialize: ./manage-svc.sh hashivault deploy
4. Re-initialize vault: ./svc-exec.sh hashivault initialize
```

**Prevention**: Regularly backup unseal keys to secure location

```bash
# Automated backup
./svc-exec.sh hashivault backup
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
hashivault_svc:
  hosts:
    podma:
      hashivault_svc_name: "vault-podma"
  vars:
    vault_api_port: 8200
    vault_cluster_port: 8201

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml hashivault prepare
./manage-svc.sh -h podma -i inventory/podma.yml hashivault deploy

# Initialize on remote host
./svc-exec.sh -h podma -i inventory/podma.yml hashivault initialize
./svc-exec.sh -h podma -i inventory/podma.yml hashivault configure
```

**Note**: Unseal keys are stored on the remote host at `~/.secrets/vault-secrets/vault-keys.json`

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

**Component Architecture:**

```text
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│  Your Apps      │───▶│   HashiVault     │◀───│   Vault Web UI      │
│                 │    │   API (8200)     │    │   (Built-in)        │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                              │                           │
                              └───────────────────────────┘
                                           │
                              ┌──────────────────────┐
                              │       Traefik        │
                              │   (SSL Termination)  │
                              └──────────────────────┘
                                           │
                              https://vault.example.com:8080
```

**Vault Storage Architecture:**

- **Development**: File-based storage (vault_storage_type: file)
- **Production Option**: Raft consensus (vault_storage_type: raft)
- **External Option**: Consul backend (vault_storage_type: consul)

See [docs/Claude-new-quadlet.md](../../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Security Considerations

### Development Security

Current deployment optimized for development:

- Unseal keys stored locally for convenience
- TLS disabled by default (Traefik provides SSL termination)
- Admin user created for quick access
- Audit logging enabled but stored locally
- Containers run rootless under your user account
- Ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems

### Production Recommendations

For production deployments:

1. **Key Management**: Distribute unseal keys among different administrators (Shamir's secret sharing)
2. **TLS**: Enable TLS for API communications (`vault_enable_tls: true`)
3. **Audit Logging**: Enable audit logging and send to SIEM (`vault_enable_audit: true`)
4. **Root Token**: Revoke root token after initial setup
5. **Network**: Restrict network access to Vault API (firewall rules)
6. **Storage**: Use Raft or Consul for HA deployments
7. **Backup**: Automated backup of unseal keys to secure offline storage
8. **Access Control**: Implement least-privilege policies
9. **Monitoring**: Enable Vault metrics and alerting
10. **Auto-Unseal**: Use cloud KMS for auto-unsealing (AWS KMS, Azure Key Vault, etc.)

### Key Storage Security

**Development:**

```bash
~/.secrets/vault-secrets/vault-keys.json
# Permissions: 0600 (user read/write only)
```

**Production:**

- Split keys among trusted administrators
- Store offline in secure locations (safe, encrypted USB)
- Use hardware security modules (HSM) for auto-unseal
- Never commit keys to version control
- Encrypt key backups with additional passphrase

## Links

- [HashiCorp Vault Official Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Docker Hub Image](https://hub.docker.com/r/hashicorp/vault)
- [Vault API Reference](https://developer.hashicorp.com/vault/api-docs)
- [Vault Secrets Engines](https://developer.hashicorp.com/vault/docs/secrets)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs vault-svc`
2. Systemd logs: `journalctl --user -u vault-pod`
3. Vault status: `podman exec vault-svc vault status`
4. Verification output: `./svc-exec.sh hashivault verify`

For Vault application issues, consult the [official documentation](https://developer.hashicorp.com/vault/docs).

## Related Services

- **Elasticsearch**: Vault can store ES passwords and API tokens
- **Mattermost**: Database credentials secured in Vault
- **Traefik**: SSL certificates and API tokens managed by Vault
- **Redis**: Authentication passwords stored securely
