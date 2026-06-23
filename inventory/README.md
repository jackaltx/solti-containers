# Inventory Structure

This directory contains baseline configurations for testing container services across different environments.

## Purpose

These inventories provide **baseline service configurations** for the solti-podman collection. They are designed for:

- **Development testing** - Validate service deployments on local machines (localhost.yml)
- **Remote testing** - Test deployments on remote hosts (podma.yml)
- **CI/CD validation** - Automated testing in pipelines
- **Example configurations** - Reference implementations for users deploying services

All configurations use **safe defaults** with environment variable lookups, making them suitable for both testing and as templates for production deployments.

## Structure

```
inventory/
├── group_vars/                 # Shared configuration for service groups
│   ├── all.yml                 # Global vars (domain, networking, test vars)
│   ├── redis_svc.yml           # Redis-specific shared config
│   ├── elasticsearch_svc.yml   # Elasticsearch-specific shared config
│   ├── mattermost_svc.yml      # Mattermost-specific shared config
│   └── ...                     # One file per service group
│
├── localhost.yml               # Local testing inventory (firefly host)
├── podma.yml                   # Remote testing inventory (podma host)
└── README.md                   # This file
```

## Variable Precedence

Ansible applies variables in this order (later overrides earlier):

1. **group_vars/all.yml** - Global defaults (domain, network settings)
2. **group_vars/<service>_svc.yml** - Service-specific defaults
3. **inventory/*.yml** - Host-specific overrides
4. **host_vars/** (not used currently) - Per-host customization

This allows:
- **Shared defaults** in group_vars for DRY configuration
- **Host-specific overrides** in inventory files for environment differences
- **Environment variable injection** for secrets and site-specific values

## Inventory Files

### localhost.yml

**Purpose**: Local development and testing on the control machine

**Host**: `firefly` (localhost via local connection)

**Use cases**:
- Local service development
- Quick iteration on role changes
- Pre-commit validation

**Example usage**:
```bash
./manage-svc.sh -i inventory/localhost.yml redis deploy
```

### podma.yml

**Purpose**: Remote host testing in a clean environment

**Host**: `podma` (remote SSH connection)

**Use cases**:
- Multi-host deployment validation
- Clean environment testing
- CI/CD integration
- Production-like testing scenarios

**Example usage**:
```bash
./manage-svc.sh -h podma -i inventory/podma.yml redis deploy
```

## Configuration Philosophy

### Baseline vs Production

These inventories are **baseline configurations**, not production-ready:

- **Secrets**: Use environment variables with safe defaults (`default=''`)
- **Passwords**: Loaded from env vars, not hardcoded
- **Data paths**: Use `$HOME` for portability across test environments
- **Ports**: Standard defaults, easily overridable

**For production deployments**, create site-specific inventories:
- Copy baseline inventory as starting point
- Override variables in inventory or host_vars
- Use ansible-vault for secrets management
- Customize data paths, ports, and networking

### Environment Variables

Services reference environment variables for sensitive data:

```yaml
# In group_vars/redis_svc.yml
redis_password: "{{ lookup('env', 'REDIS_PASSWORD', default='') }}"
```

**Testing**: Set env vars before running playbooks:
```bash
export REDIS_PASSWORD="test123"
./manage-svc.sh redis deploy
```

**Production**: Use .env files, vault, or orchestrator-specific secret injection

### Host-Specific Overrides

Only truly host-specific values remain in inventory files:

- Hostnames (firefly vs podma)
- Service names (redis-ui vs redis-ui-test)
- Port overrides (if different per host)

Example from `localhost.yml`:
```yaml
redis_svc:
  hosts:
    firefly:
      redis_svc_name: "redis-ui"  # Host-specific service name
```

## Adding New Services

To add a new service to the testing inventories:

1. **Create group_vars file**: `inventory/group_vars/<service>_svc.yml`
   - Add shared configuration (data paths, defaults, feature flags)
   - Reference env vars for secrets

2. **Add to localhost.yml** and **podma.yml**:
   ```yaml
   <service>_svc:
     hosts:
       firefly:  # or podma
         <service>_svc_name: "<service-name>"
   ```

3. **Test variable precedence**:
   ```bash
   ansible-inventory -i inventory/localhost.yml --host firefly | grep <service>
   ```

## Testing

Validate inventory syntax:
```bash
# YAML syntax check
yamllint inventory/

# Ansible inventory parsing
ansible-inventory -i inventory/localhost.yml --list
ansible-inventory -i inventory/podma.yml --list

# Verify specific service vars
ansible-inventory -i inventory/localhost.yml --host firefly | jq '.redis_password'
```

Verify variable precedence:
```bash
# Should show group_vars values merged with inventory overrides
ansible-inventory -i inventory/localhost.yml --host firefly | jq '.redis_svc_name'
```

## Galaxy Collection Compatibility

This structure follows Ansible Galaxy best practices:

- **Portable**: Uses env vars and relative paths
- **DRY**: Shared configs in group_vars eliminate duplication
- **Testable**: Separate inventories for different test scenarios
- **Documented**: Clear separation of baseline vs production configs

Users consuming this collection can:
1. Use provided inventories as-is for testing
2. Copy and customize for their environments
3. Reference group_vars as examples for their own deployments
