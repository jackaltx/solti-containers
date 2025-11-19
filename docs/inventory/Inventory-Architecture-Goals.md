# Inventory Architecture Goals

## Vision

The inventory system is evolving to support **solti-orchestrator**: a headless automation system that manages multi-environment, multi-collection deployments with externalized configuration and secrets.

## Strategic Direction

### Near-Term (Current Sprint)
- Document current state comprehensively
- Eliminate obvious pain points (duplication, safety)
- Establish clear patterns for inventory organization
- Implement safety improvements for interactive use

### Mid-Term (Next 3-6 Months)
- Transition to `group_vars/host_vars` pattern
- Implement capability matrix for testing strategies
- Separate secrets into external private repository
- Standardize across solti collections

### Long-Term (Orchestrator Era)
- Headless operation with external inventory sources
- Workflow-driven deployments (not script-driven)
- Multi-collection coordination
- Compliance and audit trail integration

## Core Concepts

### 1. Separation of Concerns

**Configuration Layers**:

```
┌─────────────────────────────────────────────────────┐
│ Workflow Definitions (External)                     │
│ - What to deploy                                    │
│ - Where to deploy it                                │
│ - When to deploy it                                 │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ Inventory (Public Repository)                       │
│ - Service defaults                                  │
│ - Network configuration                             │
│ - Host capabilities                                 │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ Secrets (Private Repository)                        │
│ - Passwords                                         │
│ - API keys                                          │
│ - Certificates                                      │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ Roles (Collection Code)                             │
│ - Implementation                                    │
│ - No hardcoded config                               │
│ - Pure logic                                        │
└─────────────────────────────────────────────────────┘
```

**Benefits**:
- Public repos contain no secrets
- Configuration changes don't require code changes
- External systems can inject workflows and secrets
- Clear responsibility boundaries

### 2. Capability Matrix

**Problem**: Different hosts have different testing capabilities

**Example Scenarios**:

| Host | Direct Port Access | Traefik Routing | Container Exec | External DNS |
|------|-------------------|-----------------|----------------|--------------|
| `firefly` (localhost) | ✓ Yes | ✗ No | ✓ Yes | ✗ No |
| `podma` (lab host) | ✓ Yes | ✓ Yes | ✓ Yes | ✓ Yes |
| `prod-01` (production) | ✗ No | ✓ Yes | ✗ No | ✓ Yes |
| GitHub Actions | ✗ No | ✗ No | ✓ Yes | ✗ No |

**Current Problem**: Verification tasks hardcode assumptions about capabilities

**Example** (elasticsearch verify):
```yaml
# Assumes direct port access
- name: Test Elasticsearch API
  uri:
    url: "http://localhost:9200"
    method: GET
```

**This fails on hosts that**:
- Don't allow localhost binding
- Require Traefik proxy access
- Use different networking models

**Solution**: Capability-driven verification

```yaml
# Host declares capabilities
host_capabilities:
  - direct_port_access
  - container_exec
  - systemd_user

# Verification tasks adapt
- name: Test Elasticsearch API (direct)
  uri:
    url: "http://localhost:9200"
  when: "'direct_port_access' in host_capabilities"

- name: Test Elasticsearch API (proxy)
  uri:
    url: "{{ elasticsearch_proxy }}/health"
  when: "'traefik_routing' in host_capabilities"
```

**Future Enhancement**: Roles query capabilities and select appropriate tests

### 3. Inventory Modularity

**Current**: Monolithic inventory files (400 lines each)

**Future**: Modular, composable structure

```
inventory/
├── production.yml              # Multi-host orchestration inventory
├── localhost.yml               # Single-host: firefly
├── padma.yml                   # Single-host: podma
│
├── group_vars/
│   ├── all.yml                 # Global: domain, network, ansible connection
│   ├── mylab.yml               # Lab-specific: results arrays, debugging
│   │
│   ├── mattermost_svc.yml      # Service defaults (DRY)
│   ├── elasticsearch_svc.yml   # All elasticsearch configuration
│   ├── redis_svc.yml           # All redis configuration
│   ├── traefik_svc.yml         # All traefik configuration
│   ├── minio_svc.yml           # etc.
│   └── ...
│
└── host_vars/
    ├── firefly.yml             # Host-specific overrides
    │   ├── host_capabilities
    │   ├── data_dir_base
    │   └── service_name_suffix
    │
    └── podma.yml               # Remote host specifics
        ├── host_capabilities
        ├── data_dir_base
        └── service_name_suffix
```

**Benefits**:
1. **DRY Principle**: Service config defined once in `group_vars/<service>_svc.yml`
2. **Scalability**: Add new hosts with minimal configuration (just host_vars)
3. **Maintainability**: Change service defaults in one place
4. **Clarity**: File structure mirrors variable scope
5. **Tooling**: Standard Ansible pattern, works with all tooling

**Example** (elasticsearch configuration):

`group_vars/elasticsearch_svc.yml`:
```yaml
---
# Default configuration for all elasticsearch deployments
debug_level: warn
elasticsearch_version: "8.11.0"
elasticsearch_http_port: 9200
elasticsearch_password: "{{ lookup('env', 'ELASTICSEARCH_PASSWORD') }}"
elasticsearch_heap_size: "1g"
elasticsearch_delete_data: false
```

`host_vars/firefly.yml`:
```yaml
---
# Localhost-specific overrides
elasticsearch_svc_name: "elasticsearch"
elasticsearch_data_dir: "~/elasticsearch-data"
elasticsearch_proxy: ""  # No proxy on localhost
host_capabilities:
  - direct_port_access
  - container_exec
  - systemd_user
```

`host_vars/podma.yml`:
```yaml
---
# Remote host overrides
elasticsearch_svc_name: "elasticsearch-test"
elasticsearch_data_dir: "~/elasticsearch-data"
elasticsearch_proxy: "https://elasticsearch.a0a0.org"
host_capabilities:
  - direct_port_access
  - traefik_routing
  - container_exec
  - systemd_user
  - external_dns
```

**Result**: Adding `minio` service requires:
- 1 file: `group_vars/minio_svc.yml` (~30 lines)
- 2 host var additions (name + data_dir overrides)
- Total: ~35 lines vs 90 lines in current system

### 4. Secrets Separation

**Current State**: Secrets mixed with configuration

```yaml
# In inventory.yml (committed to git)
elasticsearch_password: "{{ lookup('env', 'ELASTICSEARCH_PASSWORD') }}"
```

**Problems**:
- Environment variable pattern doesn't work in all contexts
- No central secrets management
- Difficult to rotate secrets
- No audit trail for secret access

**Future State**: External secrets repository

```
solti-containers/                    # Public repository
├── inventory/
│   └── group_vars/
│       └── elasticsearch_svc.yml    # No secrets, references only
│           elasticsearch_password: "{{ vault_elasticsearch_password }}"

solti-secrets/                       # Private repository
├── inventory/
│   └── group_vars/
│       └── vault.yml                # Encrypted with ansible-vault
│           vault_elasticsearch_password: "actual_secret_here"
```

**Usage**:
```bash
# Ansible automatically merges group_vars from multiple sources
ansible-playbook -i inventory/localhost.yml \
                 -i ~/solti-secrets/inventory \
                 playbook.yml
```

**Benefits**:
- Public repos contain zero secrets
- Secrets managed independently of code
- Multiple secret backends supported (vault, env, keyring)
- Different secrets per environment (dev, staging, prod)

### 5. Orchestrator Integration

**Current**: Script-driven, manual invocation

```bash
# Human operator runs commands
./manage-svc.sh redis deploy
./manage-svc.sh elasticsearch deploy
./manage-svc.sh mattermost deploy
```

**Future**: Workflow-driven, orchestrator invocation

```yaml
# workflow.yml (external to collection)
---
- name: Deploy monitoring stack
  workflow:
    collections:
      - solti-containers
    inventory: ~/lab-inventory
    secrets: ~/lab-secrets
    targets:
      - host: firefly
        services:
          - redis
          - elasticsearch
          - grafana
      - host: podma
        services:
          - redis
          - elasticsearch
    notifications:
      - mattermost: "#deployments"
    rollback_on_failure: true
```

**Orchestrator responsibilities**:
- Parse workflow definitions
- Resolve dependencies between services
- Merge inventory sources (base + secrets)
- Invoke Ansible with correct parameters
- Handle failures and rollbacks
- Send notifications
- Record audit trail

**Collection responsibilities** (solti-containers):
- Implement service deployment roles
- Provide verification tasks
- Define service capabilities and requirements
- Maintain role documentation

**Benefits**:
- Collections become pure implementation (no workflow logic)
- Workflows are version-controlled and reviewable
- Same collection code deploys to any environment
- Centralized orchestration across multiple collections
- Better error handling and recovery

## Capability Matrix Detail

### Capability Definitions

| Capability | Description | Required For |
|------------|-------------|--------------|
| `direct_port_access` | Can access `localhost:PORT` directly | Local API testing |
| `traefik_routing` | Has Traefik deployed with SSL termination | HTTPS testing |
| `container_exec` | Can run `podman exec` commands | Container-internal verification |
| `systemd_user` | User services via `systemctl --user` | Service lifecycle testing |
| `external_dns` | Public DNS resolution for host | External endpoint testing |
| `sudo_access` | Can run privileged commands | System-level operations |
| `selinux_enforcing` | SELinux in enforcing mode | Security policy testing |

### Test Strategy Selection

**Verification tasks use capabilities to determine test strategy**:

```yaml
# roles/elasticsearch/tasks/verify.yml
---
- name: Verify Elasticsearch (Strategy Selection)
  include_tasks: "verify_{{ elasticsearch_test_strategy }}.yml"
  vars:
    elasticsearch_test_strategy: "{{ 'external' if 'traefik_routing' in host_capabilities else 'direct' }}"

# roles/elasticsearch/tasks/verify_direct.yml
- name: Test API (Direct Port)
  uri:
    url: "http://localhost:{{ elasticsearch_http_port }}"
    user: elastic
    password: "{{ elasticsearch_password }}"
    force_basic_auth: yes

# roles/elasticsearch/tasks/verify_external.yml
- name: Test API (Traefik Proxy)
  uri:
    url: "{{ elasticsearch_proxy }}/health"
    validate_certs: yes
```

**Benefits**:
- Same role works on localhost and production
- Tests adapt to environment automatically
- Clear documentation of requirements
- Enables "progressive testing" (more capabilities = more tests)

### Capability Inheritance

**Host capabilities can be inherited**:

```yaml
# group_vars/mylab.yml (applies to all lab hosts)
default_capabilities:
  - container_exec
  - systemd_user

# host_vars/firefly.yml
host_capabilities: "{{ default_capabilities + ['direct_port_access'] }}"

# host_vars/podma.yml
host_capabilities: "{{ default_capabilities + ['direct_port_access', 'traefik_routing', 'external_dns'] }}"
```

## Migration Philosophy

### Guiding Principles

1. **Non-Breaking Changes**: Existing workflows continue working during transition
2. **Incremental Progress**: Each phase delivers value independently
3. **User Testing Breakpoints**: Pause for validation after major changes
4. **Rollback Safety**: Can revert to previous state at any phase boundary
5. **Documentation First**: Document before implementing

### Phase Boundaries

Each migration phase ends with:
- ✓ Checkpoint commit
- ✓ Full regression testing
- ✓ User validation period
- ✓ Documentation updates
- ✓ Go/no-go decision for next phase

### Risk Management

**Low Risk Changes**:
- Documentation additions
- Safety feature additions
- Inventory file additions (not replacements)
- Script flag additions (backwards compatible)

**Medium Risk Changes**:
- Changing default inventory in `ansible.cfg`
- Creating `group_vars/` alongside existing inline vars
- Adding validation checks to scripts

**High Risk Changes**:
- Removing root `inventory.yml`
- Moving all vars to `group_vars/` (changes precedence)
- Removing inline vars from inventory files
- Changing variable names or structure

**Mitigation**:
- High-risk changes done in later phases after validation
- Always test with `--check` mode first
- Maintain parallel systems during transition
- Preserve old files until new system proven

## Success Criteria

### Phase 1 (Safety & Documentation)
- ✓ Complete documentation of current system
- ✓ Safety prompts prevent accidental remote deployments
- ✓ Clear migration roadmap with breakpoints
- ✓ Users understand current vs future state

### Phase 2 (Consolidate to inventory/)
- ✓ Default inventory is `inventory/localhost.yml`
- ✓ All workflows use `inventory/` files
- ✓ Root `inventory.yml` deprecated (but functional)
- ✓ No duplication between active inventory files

### Phase 3 (Extract group_vars)
- ✓ Service configuration in `group_vars/<service>_svc.yml`
- ✓ Host overrides in `host_vars/<host>.yml`
- ✓ Inventory files slim (<50 lines)
- ✓ Variable precedence behaves correctly

### Phase 4 (Capability Matrix)
- ✓ Hosts declare capabilities
- ✓ Verification tasks adapt to capabilities
- ✓ Same role works on localhost and production
- ✓ Progressive testing based on environment

### Phase 5 (Secrets Separation)
- ✓ No secrets in public repository
- ✓ External secrets repository pattern documented
- ✓ Multiple inventory source support tested
- ✓ Ready for orchestrator integration

## Timeline

**Phase 1**: Current sprint (1-2 weeks)
**Phase 2**: Next sprint (1-2 weeks)
**Phase 3**: Following sprint (2-3 weeks, higher complexity)
**Phase 4**: Parallel with phase 3 or after (1-2 weeks)
**Phase 5**: When orchestrator requirements finalized (TBD)

**Total estimated time**: 2-3 months for phases 1-4, orchestrator integration TBD

## Related Documentation

- [Inventory-System-Overview.md](Inventory-System-Overview.md) - Current state documentation
- [Migration-Phases.md](Migration-Phases.md) - Detailed phase implementation plans
- [Capability-Matrix.md](Capability-Matrix.md) - Testing strategy patterns
- [SOLTI Philosophy](../../solti/solti.md) - Overall project vision
