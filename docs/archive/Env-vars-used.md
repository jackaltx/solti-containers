# Required Environment Variables

## Core System Variables

These variables are used across multiple roles:

```bash
# User Environment
XDG_RUNTIME_DIR          # Required for rootless container operations
ansible_facts.user_dir         # User's home directory
ANSIBLE_USER_ID          # User ID for container operations
```

## Role-Specific Variables

### Elasticsearch

```bash
ELASTIC_PASSWORD         # Password for Elasticsearch superuser
                        # Default: 'changemeplease'
                        # Required: Yes
                        # Used in: elasticsearch/defaults/main.yml
```

### Mattermost

```bash
MM_DB_PASSWORD          # PostgreSQL database password
                        # Default: 'changemeplease'
                        # Required: Yes
                        # Used in: mattermost/defaults/main.yml
```

### Traefik

```bash
LINODE_TOKEN            # API token for Linode DNS integration
                        # Default: None
                        # Required: Yes
                        # Used in: traefik/tasks/prerequisites.yml
```

## Optional Variables

### Redis

```bash
REDIS_PASSWORD          # Password for Redis authentication
                        # Default: 'changeme'
                        # Required: No, but highly recommended
                        # Used in: redis/defaults/main.yml
```

## Example Environment File

Here's a template `.env` file that can be used to set these variables:

```bash
# Core System
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Elasticsearch
export ELASTIC_PASSWORD="your_secure_elastic_password"

# Mattermost
export MM_DB_PASSWORD="your_secure_mattermost_db_password"

# Traefik
export LINODE_TOKEN="your_linode_api_token"

# Redis
export REDIS_PASSWORD="your_secure_redis_password"
```

## Usage Notes

1. Environment Variable Precendence:
   - Ansible playbook variables override environment variables
   - Environment variables override default values in role defaults

2. Security Considerations:
   - Don't store passwords in version control
   - Use Ansible Vault for sensitive values
   - Consider using a secrets management solution (e.g., HashiCorp Vault)

3. Validation:
   - All roles include validation tasks for required variables
   - Roles will fail early if required variables are not set

4. Integration:
   - Variables can be set in CI/CD pipelines
   - Can be managed through configuration management
   - Consider using `.env` files for local development

## Best Practices

1. Always use strong, unique passwords
2. Rotate credentials regularly
3. Use separate credentials for development and production
4. Document any changes to default values
5. Validate environment setup before running playbooks
