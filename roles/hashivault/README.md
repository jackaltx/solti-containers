# HashiVault Role - Development Secrets Management

## Purpose

HashiCorp Vault provides comprehensive secrets management for development workflows. This deployment offers secure storage and retrieval of API keys, passwords, certificates, and other sensitive data needed during testing and development cycles.

## Quick Start

```bash
# Prepare system directories and configuration
./manage-svc.sh hashivault prepare

# Deploy Vault container
./manage-svc.sh hashivault deploy

# Initialize Vault (one-time setup)
./svc-exec.sh hashivault initialize

# Configure authentication and policies
./svc-exec.sh hashivault configure

# Set up secret engines and initial data
./svc-exec.sh hashivault vault-secrets

# Verify deployment
./svc-exec.sh hashivault verify
```

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Features

- **Multiple Secret Engines**: KV, PKI, SSH, Transit encryption
- **Authentication Methods**: Token, Username/Password, AppRole
- **Development UI**: Built-in web interface for easy management
- **SSL Integration**: Automatic HTTPS via Traefik
- **Initialization Automation**: Secure key generation and storage
- **Policy Management**: Role-based access control

## Architecture

```
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
                              https://vault.yourdomain.com
```

## Access Points

| Interface | URL | Purpose |
|-----------|-----|---------|
| Vault API | `http://localhost:8200` | Direct Vault API access |
| Web UI | `http://localhost:8200/ui` | Local web interface |
| SSL Endpoint | `https://vault.{{ domain }}` | Traefik-proxied HTTPS access |

## Complete Setup Workflow

### 1. Initial Deployment

```bash
# Deploy Vault
./manage-svc.sh hashivault deploy
```

### 2. Initialize Vault (First Time Only)

```bash
# Initialize with secure key sharing
./svc-exec.sh hashivault initialize
```

This creates:

- 5 unseal key shares (3 required to unseal)
- Root token for initial configuration
- Keys stored securely in `~/.secrets/vault-secrets/vault-keys.json`

### 3. Configure Authentication & Policies

```bash
# Set up auth methods and admin user
./svc-exec.sh hashivault configure
```

Creates:

- Admin user with secure password
- UserPass authentication method
- AppRole authentication method  
- Admin and read-only policies

### 4. Initialize Secret Engines

```bash
# Enable secret engines and populate initial data
./svc-exec.sh hashivault vault-secrets
```

Sets up:

- KV v2 engine for general secrets
- PKI engine for certificate management
- SSH engine for key signing
- Transit engine for encryption services

## Configuration

### Environment Variables

```bash
# Vault initialization
export VAULT_ADDR="http://localhost:8200"

# Optional: Set initial passwords
export VAULT_ADMIN_PASSWORD="your_secure_admin_password"
```

### Secret Organization

Default secret structure:

```
kv/
├── ansible/vault              # Ansible vault passwords
├── services/
│   ├── elasticsearch         # ES credentials and tokens
│   ├── mattermost            # MM database passwords
│   └── redis                 # Redis authentication
└── providers/
    ├── linode                # API tokens
    ├── proxmox               # Infrastructure credentials
    └── gitea                 # Git service tokens
```

### Initial Secrets Configuration

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

## Using with Traefik SSL

Vault automatically integrates with Traefik for SSL termination:

```yaml
# Traefik labels automatically applied
- "Label=traefik.http.routers.vault-primary.rule=Host(`vault.{{ domain }}`)"
- "Label=traefik.http.routers.vault-secondary.rule=Host(`hashivault.{{ domain }}`)"
```

**Result**: Access Vault securely at `https://vault.yourdomain.com`

## Common Operations

### Unsealing Vault

Vault seals automatically on restart and requires unsealing:

```bash
# Unseal after container restart
./svc-exec.sh hashivault unseal
```

### Managing Secrets

```bash
# Store a secret
podman exec vault-svc vault kv put kv/myapp/config \
  database_url="postgres://user:pass@db:5432/mydb" \
  api_key="secret_key_123"

# Retrieve a secret
podman exec vault-svc vault kv get kv/myapp/config

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

## Integration Examples

### Application Integration

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

### Environment Loading

```bash
# Load secrets into environment
eval $(vault kv get -format=json kv/myapp/config | \
  jq -r '.data.data | to_entries[] | "export \(.key)=\(.value)"')
```

## Maintenance Operations

### Backup

```bash
# Built-in backup task
./svc-exec.sh hashivault backup
```

Creates timestamped backup of:

- Vault data directory
- Configuration files  
- Encrypted unseal keys

### Policy Updates

Policies are managed via the role's configuration:

```yaml
vault_policies:
  - name: "developer"
    rules: |
      path "kv/data/development/*" {
        capabilities = ["create", "read", "update", "delete", "list"]
      }
```

### Monitoring

```bash
# Check Vault status
podman exec vault-svc vault status

# Monitor logs
podman logs -f vault-svc

# Service status
systemctl --user status vault-pod
```

## Security Considerations

### Production Recommendations

1. **Key Management**: In production, distribute unseal keys among different administrators
2. **TLS**: Enable TLS for API communications (`vault_enable_tls: true`)
3. **Audit Logging**: Enable audit logging for compliance (`vault_enable_audit: true`)
4. **Root Token**: Revoke root token after initial setup
5. **Network**: Restrict network access to Vault API

### Development Security

- Unseal keys stored locally for convenience
- TLS disabled by default for easier testing
- Admin user created for quick access
- Audit logging enabled but stored locally

## Troubleshooting

### Vault Sealed

```bash
# Check if sealed
podman exec vault-svc vault status

# Unseal with stored keys
./svc-exec.sh hashivault unseal
```

### Authentication Issues

```bash
# List auth methods
podman exec vault-svc vault auth list

# Test userpass authentication
podman exec vault-svc vault auth -method=userpass \
  username=admin password=your_password
```

### Storage Issues

```bash
# Check storage backend
podman exec vault-svc vault read sys/storage/raft/configuration

# Check file permissions
ls -la ~/vault-data/
```

## Development Workflows

### Testing Secrets Management

```bash
# Deploy Vault
./manage-svc.sh hashivault deploy
./svc-exec.sh hashivault initialize
./svc-exec.sh hashivault configure

# Store test secrets
podman exec vault-svc vault kv put kv/test/config api_key="test123"

# Use in applications
export API_KEY=$(podman exec vault-svc vault kv get -field=api_key kv/test/config)

# Clean up
./manage-svc.sh hashivault remove
```

## Related Services

- **Elasticsearch**: Vault can store ES passwords and API tokens
- **Mattermost**: Database credentials secured in Vault
- **Traefik**: SSL certificates and API tokens managed by Vault
- **Redis**: Authentication passwords stored securely

## License

MIT

## Maintained By

Jackaltx - Part of the SOLTI containers collection for development testing workflows.
