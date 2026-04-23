# Inventory System Overview

## Purpose

This document describes the current inventory system in solti-containers: how inventory files are structured, how management scripts consume them, and how variables are resolved.

## Inventory Files

### Root Inventory (Legacy Default)

**File**: `./inventory.yml` (403 lines)
**Created**: Early development
**Status**: Transitioning to deprecated

**Purpose**: Multi-host orchestration for development workflows

**Hosts Defined**:

- `firefly` - localhost (ansible_connection: local)
- `podma` - remote test host (podma.a0a0.org)

**Key Characteristics**:

- Service instances differentiated by `<service>_svc_name` suffixes
  - `firefly`: Base names (e.g., `elasticsearch`)
  - `podma`: Test suffix (e.g., `elasticsearch-test`)
- External routing configuration (`<service>_external_port` for Traefik)
- Both hosts in all service groups (`<service>_svc`)
- Focus: Multi-host deployment from single command

**Use Case**:

```bash
./manage-svc.sh redis deploy           # Deploys to both firefly and podma
./manage-svc.sh -h firefly redis deploy  # Targets only firefly
```

### Directory Inventories (Current Standard)

**Files**:

- `inventory/localhost.yml` (382 lines) - firefly only
- `inventory/padma.yml` (384 lines) - podma only

**Created**: November 17, 2025 (commit cacca3d)
**Status**: Active, recommended

**Purpose**: Single-host targeting with host-specific configuration

**Key Characteristics**:

- One host per file
- Service names use base names (no suffixes)
- Explicit data directory paths (`<service>_data_dir`)
- Proxy URLs for verification (`<service>_proxy`)
- Domain URLs (`<service>_domain`, `<service>_root_url`)
- Focus: Host-local operations and isolated deployments

**Use Cases**:

```bash
# Localhost operations
./manage-svc.sh -i inventory/localhost.yml redis deploy

# Remote host operations
./manage-svc.sh -i inventory/padma.yml redis deploy

# Environment-driven selection
export SOLTI_INVENTORY=inventory/localhost.yml
./manage-svc.sh redis deploy
```

## Inventory Structure

### Hierarchical Organization

All inventory files follow this pattern:

```yaml
all:
  vars:
    # Global configuration (all hosts, all services)
    domain: a0a0.org
    ansible_user: lavender
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    service_network: "ct-net"
    service_dns_servers: [1.1.1.1, 8.8.8.8]
    mylab_nolog: "{{ cluster_secure_log | bool | default(true) }}"

  children:
    mylab:
      hosts:
        firefly:          # Host definition
          ansible_host: "localhost"
          ansible_connection: local

      vars:
        # Lab-specific variables
        mylab_results: []

      children:
        # Service groups
        mattermost_svc:
          hosts:
            firefly:
              mattermost_svc_name: "mattermost"
          vars:
            # Service-specific configuration
            debug_level: warn
            mattermost_password: "{{ lookup('env', 'MATTERMOST_PASSWORD') }}"

        elasticsearch_svc:
          hosts:
            firefly:
              elasticsearch_svc_name: "elasticsearch"
          vars:
            debug_level: warn
            elasticsearch_password: "{{ lookup('env', 'ELASTICSEARCH_PASSWORD') }}"

        # ... additional service groups
```

### Variable Scopes

| Scope | Location | Purpose | Example |
|-------|----------|---------|---------|
| **Global** | `all:vars` | Cross-service, cross-host | `domain`, `service_network` |
| **Lab** | `mylab:vars` | Lab-wide settings | `mylab_results`, `mylab_nolog` |
| **Service Group** | `<service>_svc:vars` | Service defaults | `debug_level`, `<service>_password` |
| **Host-Service** | `<service>_svc:hosts:<host>` | Host-specific overrides | `<service>_svc_name`, `<service>_data_dir` |

## Script Integration

### Management Script Inventory Handling

Both `manage-svc.sh` and `svc-exec.sh` support flexible inventory selection:

**Default Behavior**:

```bash
# Uses ansible.cfg default (currently ./inventory.yml)
./manage-svc.sh redis deploy
```

**Explicit Inventory Selection**:

```bash
# Via -i flag (highest priority)
./manage-svc.sh -i inventory/localhost.yml redis deploy

# Via environment variable (fallback)
export SOLTI_INVENTORY=inventory/localhost.yml
./manage-svc.sh redis deploy
```

**Host Targeting**:

```bash
# Target specific host within inventory
./manage-svc.sh -h firefly redis deploy
./manage-svc.sh -i inventory.yml -h podma redis deploy
```

**Implementation** (manage-svc.sh:18):

```bash
INVENTORY="${SOLTI_INVENTORY:-${ANSIBLE_DIR}/inventory.yml}"

# Parse -i flag
while getopts "i:h:..." opt; do
    case $opt in
        i) INVENTORY="$OPTARG" ;;
        h) HOST="$OPTARG" ;;
    esac
done
```

### Generated Playbook Pattern

Scripts generate temporary playbooks dynamically:

```yaml
---
- name: Manage redis Service
  hosts: redis_svc              # or specific HOST if -h provided
  become: true
  vars:
    redis_state: present        # or prepare/absent
  roles:
    - role: redis
```

**Key Points**:

- Playbooks target service groups (`<service>_svc`) by default
- Host targeting via `-h` overrides group targeting
- Ansible resolves all variables from inventory automatically
- Scripts don't parse inventory content directly

## Variable Resolution

### Ansible Precedence Rules

Variables are resolved in this order (highest to lowest):

1. **Extra vars** (`-e` on command line)
2. **Host vars** (inline under host in inventory)
3. **Group vars** (inline under group in inventory)
4. **All vars** (inline under `all` in inventory)
5. **Role defaults** (in role's `defaults/main.yml`)

### Example Resolution

For `elasticsearch` service on `firefly` host:

```yaml
# Global (all:vars) - Lowest precedence
domain: a0a0.org
service_network: "ct-net"

# Service group (elasticsearch_svc:vars) - Medium precedence
debug_level: warn
elasticsearch_password: "{{ lookup('env', 'ELASTICSEARCH_PASSWORD') }}"
elasticsearch_http_port: 9200

# Host-specific (elasticsearch_svc:hosts:firefly) - Highest precedence
elasticsearch_svc_name: "elasticsearch"
elasticsearch_data_dir: "~/elasticsearch-data"
```

**Resulting Context**:

```yaml
domain: "a0a0.org"                    # from all:vars
service_network: "ct-net"             # from all:vars
debug_level: "warn"                   # from elasticsearch_svc:vars
elasticsearch_password: "secret123"   # from env var lookup
elasticsearch_http_port: 9200         # from elasticsearch_svc:vars
elasticsearch_svc_name: "elasticsearch" # from host override
elasticsearch_data_dir: "~/elasticsearch-data" # from host override
```

### Jinja2 Template Processing

Variables with Jinja2 expressions are processed recursively:

```yaml
# First pass: environment lookup
elasticsearch_password: "{{ lookup('env', 'ELASTICSEARCH_PASSWORD') }}"
# Result: "secret123"

# Second pass: boolean conversion
mylab_nolog: "{{ cluster_secure_log | bool | default(true) }}"
# Result: true (if cluster_secure_log undefined)

# Third pass: variable reference
service_dns_search: "{{ domain }}"
# Result: "a0a0.org"
```

## Configuration Variables

### Shared Core Variables

**Synchronized with solti-platforms** - These must remain consistent:

| Variable | Purpose | Example |
|----------|---------|---------|
| `domain` | Lab domain | `a0a0.org` |
| `ansible_user` | Remote SSH user | `lavender` |
| `ansible_ssh_private_key_file` | SSH key path | `~/.ssh/id_ed25519` |
| `mylab_nolog` | Secure logging control | `true` |
| `mylab_non_ssh` | Non-SSH host flag | `false` |

### Container-Specific Variables

**Unique to solti-containers**:

| Variable | Purpose | Example |
|----------|---------|---------|
| `service_network` | Shared container network | `ct-net` |
| `service_dns_servers` | Container DNS | `[1.1.1.1, 8.8.8.8]` |
| `service_dns_search` | DNS search domain | `{{ domain }}` |
| `test_index` | Elasticsearch test index | `test-ansible` |
| `test_doc` | Test document JSON | `{"message": "..."}` |

### Service-Specific Variables

**Pattern per service**:

| Variable Pattern | Purpose | Example |
|-----------------|---------|---------|
| `<service>_svc_name` | Container name | `elasticsearch` or `elasticsearch-test` |
| `<service>_data_dir` | Data directory path | `~/elasticsearch-data` |
| `<service>_password` | Admin password | `{{ lookup('env', 'ELASTICSEARCH_PASSWORD') }}` |
| `<service>_http_port` | Internal port | `9200` |
| `<service>_external_port` | Traefik port | `9200` (root inventory only) |
| `<service>_delete_data` | Cleanup flag | `false` |
| `<service>_proxy` | HTTPS proxy URL | `https://elasticsearch.a0a0.org` (dir inventories) |

## Current Issues

### 1. Duplication

**Problem**: Three inventory files with ~95% overlap (1169 total lines)

**Impact**:

- Service configuration changes require updates in 3 places
- Risk of inconsistency and drift
- Maintenance burden scales with number of services

**Example**: Adding `minio` service requires:

- 30 lines in `inventory.yml`
- 30 lines in `inventory/localhost.yml`
- 30 lines in `inventory/padma.yml`
- Total: 90 lines of mostly duplicate content

### 2. Mixed Concerns

**Problem**: Different inventories focus on different aspects

**Root inventory.yml**:

- External routing (`<service>_external_port`)
- Service name differentiation (`-test` suffix)
- Multi-host coordination

**Directory inventories**:

- Data directory paths (`<service>_data_dir`)
- Proxy URLs (`<service>_proxy`)
- Domain URLs (`<service>_domain`)

**Impact**: Unclear which inventory is authoritative for each variable type

### 3. Unclear Default

**Problem**: `ansible.cfg` defaults to `./inventory.yml` but documentation recommends `inventory/localhost.yml`

**Impact**:

- Users might accidentally deploy to both hosts
- Inconsistent behavior between documented and actual defaults

### 4. No Safety Rails

**Problem**: Easy to deploy to wrong host without confirmation

**Impact**:

- Risk of accidentally deploying to remote hosts
- No "are you sure" prompts for destructive operations
- Automation and interactive use have same behavior

## Best Practices

### Choosing the Right Inventory

**Use `inventory/localhost.yml` when**:

- Developing/testing services locally
- Working on a single host
- Want isolated, predictable deployments

**Use `inventory/padma.yml` when**:

- Testing on remote infrastructure
- Validating service behavior on different host
- Running CI/CD tests

**Use root `inventory.yml` when** (deprecated):

- Need to deploy to multiple hosts simultaneously
- Orchestrating multi-host workflows
- (Recommend using separate inventory files with orchestration tooling instead)

### Variable Organization

**Global variables** (rare changes):

- Network configuration (`service_network`, DNS settings)
- Authentication (`ansible_user`, SSH keys)
- Domain/lab settings

**Service variables** (frequent changes):

- Passwords and secrets
- Port assignments
- Feature flags
- Test data

**Host variables** (host-specific):

- Service names (for disambiguation)
- Data directory paths
- Connection settings

### Secure Logging

All inventories support secure logging control:

```yaml
mylab_nolog: "{{ cluster_secure_log | bool | default(true) }}"
```

**Usage in roles**:

```yaml
- name: Task with sensitive data
  debug:
    msg: "Password is {{ redis_password }}"
  no_log: "{{ mylab_nolog | default(true) }}"
```

**Override for debugging**:

```bash
export MOLECULE_SECURE_LOGGING=false
./manage-svc.sh redis deploy
```

## Related Documentation

- [Inventory-Architecture-Goals.md](Inventory-Architecture-Goals.md) - Future vision and orchestrator strategy
- [Migration-Phases.md](Migration-Phases.md) - Roadmap for inventory system evolution
- [Capability-Matrix.md](Capability-Matrix.md) - localhost vs external testing patterns
- [Container-Role-Architecture.md](../Container-Role-Architecture.md) - How roles consume inventory variables

## Quick Reference

### Common Commands

```bash
# Default localhost deployment
./manage-svc.sh redis deploy

# Explicit localhost
./manage-svc.sh -i inventory/localhost.yml redis deploy

# Remote deployment
./manage-svc.sh -i inventory/padma.yml redis deploy

# Target specific host in multi-host inventory
./manage-svc.sh -i inventory.yml -h firefly redis deploy

# Environment-driven selection
export SOLTI_INVENTORY=inventory/localhost.yml
./manage-svc.sh redis deploy

# Verify with specific inventory
./svc-exec.sh -i inventory/localhost.yml redis verify
```

### Inventory Location Priority

1. `-i` flag (explicit override)
2. `SOLTI_INVENTORY` environment variable
3. `ansible.cfg` default (currently `./inventory.yml`)

### Service Group Naming

All service groups follow the pattern `<service>_svc`:

- `redis_svc`
- `elasticsearch_svc`
- `mattermost_svc`
- `traefik_svc`
- etc.

### Variable Lookup Order

For any variable, Ansible checks in this order:

1. Command line `-e` vars
2. Host-level vars (under host in inventory)
3. Group-level vars (under group in inventory)
4. Global vars (under `all:vars`)
5. Role defaults
