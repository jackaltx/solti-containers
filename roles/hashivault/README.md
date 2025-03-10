# HashiCorp Vault Role Documentation

## Introduction

HashiCorp Vault is a powerful secrets management tool that provides secure storage for sensitive data such as API keys, passwords, certificates, and more. This Ansible role deploys Vault as a containerized service using Podman with a focus on ease of setup, management, and cleanup.

Key features of this implementation:

- Rootless Podman deployment
- Systemd integration using Quadlets
- Secure initialization and key management
- Multiple secret engines support (KV, PKI, SSH, Transit)
- Built-in web UI for easy management

This role follows the standard SOLTI container pattern, providing consistent deployment, configuration, and management commands across all services.

## Deployment Scenario

By default, the role deploys Vault on the local machine with the following configuration:

- **API Port**: 8200 (configurable via `vault_api_port`)
- **Cluster Port**: 8201 (configurable via `vault_cluster_port`)
- **UI Enabled**: Yes (access via <http://localhost:8200/ui>)
- **Storage**: File backend (configurable to Raft for clustering)
- **TLS**: Optional (disabled by default)

## Installation

### Prepare

The preparation step creates the necessary directory structure and configuration files. This step runs once per host:

```bash
./manage-svc.sh hashivault prepare
```

This command:

- Creates configuration and data directories
- Sets proper permissions
- Configures SELinux contexts (on RHEL-based systems)

Directory structure created:

```
~/vault-data/
├── config/    # Vault configuration files
├── data/      # Vault storage
├── logs/      # Audit logs
└── tls/       # TLS certificates (if enabled)
```

### Deploy

The deployment step creates and starts the Vault container:

```bash
./manage-svc.sh hashivault deploy
```

This command is idempotent and can be run multiple times safely. It:

- Creates the Podman pod and container(s)
- Generates systemd Quadlet files for service management
- Starts the Vault service as a rootless container

Quadlet files created:

```bash
$ ls -1 ~/.config/containers/systemd/vault*
/home/jackaltx/.config/containers/systemd/vault.pod
/home/jackaltx/.config/containers/systemd/vault-svc.container
```

To check the service status:

```bash
$ systemctl --user status vault-pod
# or
$ systemctl --user status vault-svc
```

Sample status output:

```
● vault-svc.service - HashiCorp Vault Container
 Loaded: loaded (/home/jackaltx/.config/containers/systemd/vault-svc.container; generated)
 Drop-In: /usr/lib/systemd/user/service.d
 └─10-timeout-abort.conf
 Active: active (running) since Mon 2025-03-03 15:29:24 CST; 1h 32min ago
 Invocation: 93fc66d5087c43e3abc57921aab5d52f
 Main PID: 3337 (conmon)
 Tasks: 14 (limit: 74224)
 Memory: 378.4M (peak: 379.6M)
 CPU: 2.965s
 CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/vault-svc.service
 ├─libpod-payload-b3fcc94cd6a1c263626ac6283d30ab854d9437379ec1a618b233c7c929891819
 │ ├─3346 /usr/bin/dumb-init /bin/sh /usr/local/bin/docker-entrypoint.sh server
 │ └─3359 vault server -config=/vault/config -dev-root-token-id= -dev-listen-address=0.0.0.0:8200
 └─runtime
 └─3337 /usr/bin/conmon --api-version 1 -c b3fcc94cd6a1c263626ac6283d30ab854d9437379ec1a618b233c7c929891819 -u b3fcc94cd6a1c263626ac6283d30ab854d9437379ec1a618b233c7c929891819 -r /usr/bin/c>
```

## Configuration

### Initialize Vault

After deployment, Vault must be initialized to generate encryption keys and root tokens:

```bash
./svc-exec.sh hashivault initialize
```

This command:

- Initializes Vault with a configurable number of key shares (default: 5)
- Sets the key threshold for unsealing (default: 3)
- Securely stores the keys and root token in `~/.secrets/vault-secrets/vault-keys.json`
- Optionally creates a backup of the keys
- Automatically unseals Vault if configured to do so

### Configure Vault

Set up Vault with authentication methods and secret engines:

```bash
./svc-exec.sh hashivault configure
```

This command configures:

- Authentication methods (userpass, approle)
- Admin user with secure password
- Policies for access control
- KV v2 secrets engine for general secrets

### Set Up Secret Engines

Enable and configure additional secret engines:

```bash
./svc-exec.sh hashivault vault-secrets
```

This task:

- Enables Transit engine for encryption as a service
- Enables PKI engine for certificate management
- Enables SSH engine for SSH key signing/management
- Populates initial secrets from environment variables or inventory variables

#### Initial Secrets Configuration

You can configure initial secrets in your inventory, host_vars, or group_vars:

```yaml
# Example vault_initial_secrets configuration
vault_initial_secrets:
  - path: "kv/ansible/vault"
    data:
      provision_vault_password: "{{ lookup('env', 'PROVISION_VAULT_PASSWORD') | default('changeme_in_production') }}"

  - path: "kv/services/elasticsearch"
    data:
      elastic_password: "{{ lookup('env', 'ELASTIC_PASSWORD') | default('changeme_in_production') }}"
      es_ro_token: "{{ lookup('env', 'ES_RO_TOKEN') | default('changeme_in_production') }}"

  # Additional secrets as needed
```

## Maintenance

### Unsealing Vault

Vault requires unsealing after every restart:

```bash
./svc-exec.sh hashivault unseal
```

This command:

- Checks if Vault is already unsealed
- Reads the unseal keys from the keys file
- Applies the keys up to the threshold
- Verifies the unsealed status

### Backup

To back up your Vault data:

```bash
./svc-exec.sh hashivault backup
```

This creates a timestamped backup of:

- Vault data directory
- Configuration files
- Unseal keys (encrypted)

### Remove Vault

To remove the Vault deployment (keeping data by default):

```bash
./manage-svc.sh hashivault remove
```

To completely remove Vault including all data:

```bash
VAULT_DELETE_DATA=true ./manage-svc.sh hashivault remove
```

## Security Considerations

1. **Key Storage**: Unseal keys and root tokens are extremely sensitive. In production:
   - Store key shares with different security officers
   - Use hardware security modules (HSMs) if possible
   - Never store all unseal keys on the same system as Vault

2. **Production Settings**:
   - Enable TLS (`vault_enable_tls: true`)
   - Use audit logging (`vault_enable_audit: true`)
   - Configure proper firewall rules
   - Use Raft storage instead of file storage for high availability

3. **Root Token**: The root token should be used only for initial setup, then revoked:

   ```bash
   podman exec -it vault-svc vault token revoke $ROOT_TOKEN
   ```

## Troubleshooting

### Cannot Unseal Vault

If you see "Error unsealing: Error making API request", check:

- Is Vault running? (`systemctl --user status vault-pod`)
- Is the keys file present and readable?
- Does the keys file contain valid unseal keys?

### API Connection Issues

If you can't connect to the Vault API:

- Check if Vault is running and unsealed
- Verify the API port is accessible (`curl -v http://localhost:8200/v1/sys/health`)
- Ensure the network connection is not blocked by a firewall

### Permission Issues

For SELinux-related issues:

- Check SELinux contexts: `ls -Z ~/vault-data`
- Reapply contexts: `sudo restorecon -Rv ~/vault-data`

## Configuration Variables

Key variables for customizing the Vault deployment:

```yaml
# Installation state
hashivault_state: present               # Use 'absent' to remove
vault_force_reload: false          # Force reload configuration
vault_delete_data: false           # Delete data on removal

# Container settings
vault_image: docker.io/hashicorp/vault:1.15
vault_data_dir: "{{ ansible_user_dir }}/vault-data"
vault_api_port: 8200
vault_cluster_port: 8201

# Security settings
vault_enable_ui: true
vault_enable_audit: true

# TLS Configuration
vault_enable_tls: false
vault_tls_cert_file: ""            # Path to certificate
vault_tls_key_file: ""             # Path to private key
vault_tls_ca_file: ""              # Optional CA certificate

# Storage settings
vault_storage_type: "file"         # Options: file, raft, consul
```

For complete configuration options, see `defaults/main.yml`.
