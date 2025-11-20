# Capability Matrix

## Overview

The capability matrix defines host capabilities and how they drive test strategy selection. Different hosts (localhost, remote, production, CI) have different testing capabilities, and verification tasks must adapt accordingly.

## Problem Statement

### Current Limitation

Verification tasks hardcode assumptions about the test environment:

```yaml
# roles/elasticsearch/tasks/verify.yml - CURRENT
- name: Test Elasticsearch API
  uri:
    url: "http://localhost:9200"
    user: elastic
    password: "{{ elasticsearch_password }}"
    method: GET
```

**This fails when**:
- Host doesn't allow direct port access (production firewall rules)
- Service only accessible via Traefik proxy (HTTPS-only environments)
- Host requires different networking (bridge mode, macvlan, etc.)
- Running in containerized CI environment

### Solution: Capability-Driven Testing

Hosts declare capabilities, roles query capabilities, tests adapt:

```yaml
# inventory/host_vars/firefly.yml
host_capabilities:
  - direct_port_access
  - container_exec
  - systemd_user

# roles/elasticsearch/tasks/verify.yml - FUTURE
- name: Determine test strategy
  set_fact:
    test_strategy: "{{ 'direct' if 'direct_port_access' in host_capabilities else 'container' }}"

- name: Run verification
  include_tasks: "verify_{{ test_strategy }}.yml"
```

## Capability Taxonomy

### Core Capabilities

| Capability | Description | Enables | Example Test |
|------------|-------------|---------|--------------|
| `direct_port_access` | Can access `localhost:PORT` | Direct API testing | `curl http://localhost:9200` |
| `container_exec` | Can run `podman exec` | Container-internal tests | `podman exec es-svc curl localhost:9200` |
| `systemd_user` | User systemd services | Lifecycle testing | `systemctl --user status es-pod` |
| `traefik_routing` | Traefik deployed with SSL | HTTPS endpoint testing | `curl https://es.domain.com` |
| `external_dns` | Public DNS resolution | External endpoint testing | `curl https://es.example.com` |
| `local_file_access` | Direct filesystem access | Data directory validation | `ls ~/elasticsearch-data/` |

### Extended Capabilities

| Capability | Description | Enables | Use Case |
|------------|-------------|---------|----------|
| `sudo_access` | Can run privileged commands | System-level ops | `sudo systemctl daemon-reload` |
| `selinux_enforcing` | SELinux enforcing mode | Security policy testing | `ls -Z ~/data/`, `seinfo` |
| `firewall_management` | Can modify firewall | Port opening tests | `firewall-cmd --add-port` |
| `network_bridge` | Bridge network mode | Multi-host networking | Bridge connectivity tests |
| `rootless_containers` | Rootless Podman | User-namespace testing | UID mapping validation |

## Host Capability Profiles

### Localhost Development (firefly)

```yaml
# inventory/host_vars/firefly.yml
host_capabilities:
  - direct_port_access      # curl localhost:9200 works
  - container_exec          # podman exec available
  - systemd_user            # systemctl --user available
  - local_file_access       # Direct access to ~/data/
  - rootless_containers     # Podman rootless mode
  - selinux_enforcing       # Fedora with SELinux (optional)
```

**Test Strategy**: Direct port access, container exec fallback

**Characteristics**:
- Local development machine
- All ports accessible on localhost
- Full filesystem access
- No external routing (no Traefik)
- Fast iteration cycles

### Remote Lab Host (podma)

```yaml
# inventory/host_vars/podma.yml
host_capabilities:
  - direct_port_access      # curl localhost:9200 works
  - traefik_routing         # HTTPS via Traefik
  - external_dns            # *.a0a0.org resolves
  - container_exec          # podman exec available
  - systemd_user            # systemctl --user available
  - local_file_access       # SSH access to ~/data/
  - rootless_containers     # Podman rootless mode
  - selinux_enforcing       # Rocky/RHEL with SELinux
```

**Test Strategy**: External HTTPS preferred, direct access fallback

**Characteristics**:
- Lab infrastructure host
- Traefik provides SSL termination
- External domain resolution
- Full test environment
- Mirrors production more closely

### Production Host (example)

```yaml
# inventory/host_vars/prod-01.yml
host_capabilities:
  - traefik_routing         # HTTPS only
  - external_dns            # Public DNS
  - systemd_user            # systemctl --user available
  - firewall_management     # Firewalld configured
  - selinux_enforcing       # SELinux mandatory
```

**Test Strategy**: External HTTPS only, no direct access

**Characteristics**:
- Production infrastructure
- No localhost port access (firewall)
- HTTPS-only access via Traefik
- Limited testing capabilities
- Security hardened

### GitHub Actions CI (example)

```yaml
# inventory/host_vars/github-runner.yml
host_capabilities:
  - container_exec          # podman exec available
  - rootless_containers     # Container-in-container
```

**Test Strategy**: Container exec only, no network access

**Characteristics**:
- Ephemeral CI environment
- No persistent storage
- No external network access
- Container-internal testing only
- Fast, isolated

## Test Strategy Selection

### Decision Tree

```
┌─────────────────────────────────────────────────────────┐
│ Start Verification                                       │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │ traefik_routing?   │
         └────┬───────────┬───┘
              │ Yes       │ No
              ▼           ▼
      ┌───────────┐   ┌──────────────────┐
      │ External  │   │ direct_port_     │
      │ HTTPS     │   │   access?        │
      │ Strategy  │   └──┬───────────┬───┘
      └───────────┘      │ Yes       │ No
                         ▼           ▼
                  ┌──────────┐   ┌──────────┐
                  │ Direct   │   │ Container│
                  │ Strategy │   │ Exec     │
                  └──────────┘   │ Strategy │
                                 └──────────┘
```

### Strategy Implementations

#### Strategy: External HTTPS

**When**: Host has `traefik_routing` and `external_dns`

**Verification Method**: HTTPS requests via Traefik

**Example** (elasticsearch):
```yaml
# roles/elasticsearch/tasks/verify_external.yml
---
- name: Test Elasticsearch API via Traefik
  uri:
    url: "{{ elasticsearch_proxy }}/health"
    method: GET
    validate_certs: yes
    status_code: 200
  register: es_health

- name: Verify cluster health
  uri:
    url: "{{ elasticsearch_proxy }}/_cluster/health"
    method: GET
    user: elastic
    password: "{{ elasticsearch_password }}"
    force_basic_auth: yes
    validate_certs: yes
  register: cluster_health

- name: Assert cluster is healthy
  assert:
    that:
      - cluster_health.json.status in ['green', 'yellow']
    fail_msg: "Cluster health is {{ cluster_health.json.status }}"
```

**Variables Required**:
- `elasticsearch_proxy`: `https://elasticsearch.a0a0.org`

**Benefits**:
- Tests production access path
- Validates SSL certificates
- Tests DNS resolution
- Mirrors end-user experience

**Limitations**:
- Requires Traefik deployed first
- Requires DNS configured
- Slower than direct access
- Requires valid SSL certificates

#### Strategy: Direct Port Access

**When**: Host has `direct_port_access` (and NOT `traefik_routing` preferred)

**Verification Method**: Direct HTTP to localhost:PORT

**Example** (elasticsearch):
```yaml
# roles/elasticsearch/tasks/verify_direct.yml
---
- name: Test Elasticsearch API (direct)
  uri:
    url: "http://localhost:{{ elasticsearch_http_port }}"
    method: GET
    status_code: 200
  register: es_health

- name: Verify cluster health (direct)
  uri:
    url: "http://localhost:{{ elasticsearch_http_port }}/_cluster/health"
    method: GET
    user: elastic
    password: "{{ elasticsearch_password }}"
    force_basic_auth: yes
  register: cluster_health

- name: Test indexing (direct)
  uri:
    url: "http://localhost:{{ elasticsearch_http_port }}/{{ test_index }}/_doc"
    method: POST
    user: elastic
    password: "{{ elasticsearch_password }}"
    force_basic_auth: yes
    body: "{{ test_doc }}"
    body_format: json
  register: index_result
```

**Variables Required**:
- `elasticsearch_http_port`: `9200`
- `test_index`: `test-ansible`
- `test_doc`: `{"message": "verification test"}`

**Benefits**:
- Fast execution
- No external dependencies
- Full API access
- Detailed error messages

**Limitations**:
- Doesn't test production path
- Requires port binding to localhost
- Might not work in hardened environments

#### Strategy: Container Exec

**When**: No `direct_port_access`, but has `container_exec`

**Verification Method**: Execute commands inside container

**Example** (elasticsearch):
```yaml
# roles/elasticsearch/tasks/verify_container.yml
---
- name: Test Elasticsearch API (container exec)
  command: >
    podman exec {{ elasticsearch_svc_name }}-svc
    curl -s -u elastic:{{ elasticsearch_password }}
    http://localhost:9200/_cluster/health
  register: cluster_health_output
  changed_when: false

- name: Parse cluster health
  set_fact:
    cluster_health: "{{ cluster_health_output.stdout | from_json }}"

- name: Assert cluster is healthy
  assert:
    that:
      - cluster_health.status in ['green', 'yellow']
    fail_msg: "Cluster health is {{ cluster_health.status }}"

- name: Test indexing (container exec)
  command: >
    podman exec {{ elasticsearch_svc_name }}-svc
    curl -s -X POST
    -u elastic:{{ elasticsearch_password }}
    -H "Content-Type: application/json"
    -d '{{ test_doc | to_json }}'
    http://localhost:9200/{{ test_index }}/_doc
  register: index_result
  changed_when: false
```

**Variables Required**:
- `elasticsearch_svc_name`: Container name
- `test_index`, `test_doc`: Test data

**Benefits**:
- Works in restricted environments
- No network access required
- Tests container-internal state
- Fallback when other methods unavailable

**Limitations**:
- Doesn't test external access
- Requires `podman exec` permission
- More complex error handling
- Output parsing required

#### Strategy: Systemd Lifecycle

**When**: Host has `systemd_user`

**Verification Method**: Systemd service status checks

**Example** (all services):
```yaml
# roles/_base/tasks/verify_systemd.yml
---
- name: Check service is running
  systemd:
    name: "{{ service_name }}-pod"
    state: started
    scope: user
  check_mode: yes
  register: service_status

- name: Verify service is active
  command: systemctl --user is-active {{ service_name }}-pod
  register: is_active
  changed_when: false
  failed_when: is_active.stdout != "active"

- name: Verify service is enabled
  command: systemctl --user is-enabled {{ service_name }}-pod
  register: is_enabled
  changed_when: false
  failed_when: is_enabled.stdout != "enabled"
```

**Benefits**:
- Quick health check
- Standard systemd patterns
- No service-specific knowledge

**Limitations**:
- Doesn't test functionality
- Only validates service is running
- Not sufficient alone

## Variable Naming Patterns

### Service-Specific Variables

**Pattern**: `<service>_<property>`

**Examples**:
- `elasticsearch_http_port`: Internal port
- `elasticsearch_proxy`: External HTTPS URL
- `elasticsearch_svc_name`: Container name
- `elasticsearch_data_dir`: Data directory path

### Test Strategy Variables

**Pattern**: `<service>_test_<property>`

**Examples**:
- `elasticsearch_test_strategy`: Selected strategy (`direct`, `external`, `container`)
- `elasticsearch_test_index`: Test index name
- `elasticsearch_test_enabled`: Enable/disable tests
- `redis_test_key`: Test key for Redis

### Capability Detection Variables

**Pattern**: `host_capabilities` (list)

**Example**:
```yaml
host_capabilities:
  - direct_port_access
  - traefik_routing
  - container_exec
```

**Usage in roles**:
```yaml
- name: Check for direct access
  set_fact:
    has_direct_access: "{{ 'direct_port_access' in host_capabilities | default([]) }}"
```

## Implementation Patterns

### Role-Level Strategy Selection

**Pattern**: Determine strategy at role level, include appropriate task file

```yaml
# roles/elasticsearch/tasks/verify.yml
---
- name: Include systemd verification (always)
  include_tasks: verify_systemd.yml

- name: Determine API test strategy
  set_fact:
    elasticsearch_test_strategy: >-
      {{ 'external' if ('traefik_routing' in host_capabilities | default([]) and elasticsearch_proxy is defined)
         else 'direct' if 'direct_port_access' in host_capabilities | default([])
         else 'container' if 'container_exec' in host_capabilities | default([])
         else 'skip' }}

- name: Run API verification
  include_tasks: "verify_api_{{ elasticsearch_test_strategy }}.yml"
  when: elasticsearch_test_strategy != 'skip'

- name: Include data verification (if local access)
  include_tasks: verify_data.yml
  when: "'local_file_access' in host_capabilities | default([])"
```

**Benefits**:
- Single entry point (`verify.yml`)
- Clear strategy selection logic
- Easy to add new strategies
- Graceful degradation (skip if no capabilities)

### Task-Level Conditional Execution

**Pattern**: Use `when` conditions on individual tasks

```yaml
# roles/elasticsearch/tasks/verify.yml (alternative)
---
- name: Test API via Traefik
  uri:
    url: "{{ elasticsearch_proxy }}/health"
  when:
    - "'traefik_routing' in host_capabilities | default([])"
    - elasticsearch_proxy is defined

- name: Test API directly
  uri:
    url: "http://localhost:{{ elasticsearch_http_port }}"
  when:
    - "'direct_port_access' in host_capabilities | default([])"
    - "'traefik_routing' not in host_capabilities | default([])"

- name: Test API via container exec
  command: podman exec {{ elasticsearch_svc_name }}-svc curl localhost:9200
  when:
    - "'container_exec' in host_capabilities | default([])"
    - "'direct_port_access' not in host_capabilities | default([])"
    - "'traefik_routing' not in host_capabilities | default([])"
```

**Benefits**:
- All tests in one file
- Clear capability requirements
- Easy to scan capabilities

**Drawbacks**:
- Can become cluttered with many strategies
- Harder to maintain complex logic
- More repetition

### Progressive Testing

**Pattern**: Run basic tests first, then advanced tests if capabilities allow

```yaml
# roles/elasticsearch/tasks/verify.yml
---
# Level 1: Systemd (minimum requirement)
- name: Verify service is running
  include_tasks: verify_systemd.yml

# Level 2: Basic connectivity (if any API access)
- name: Verify API responds
  include_tasks: verify_connectivity.yml
  when: >
    'direct_port_access' in host_capabilities | default([]) or
    'traefik_routing' in host_capabilities | default([]) or
    'container_exec' in host_capabilities | default([])

# Level 3: Functional tests (if direct or external access)
- name: Verify indexing works
  include_tasks: verify_indexing.yml
  when: >
    'direct_port_access' in host_capabilities | default([]) or
    'traefik_routing' in host_capabilities | default([])

# Level 4: Performance tests (if direct access)
- name: Verify performance
  include_tasks: verify_performance.yml
  when:
    - "'direct_port_access' in host_capabilities | default([])"
    - elasticsearch_verify_performance | default(false)
```

**Benefits**:
- Tests increase in depth based on capabilities
- Clear test hierarchy
- Easy to understand requirements
- Graceful degradation

## Service-Specific Patterns

### Simple Services (Redis, Minio)

**Characteristics**:
- Single port
- Simple API
- Basic health check

**Test Strategy**:
```yaml
# roles/redis/tasks/verify.yml
---
- name: Systemd check
  include_tasks: verify_systemd.yml

- name: Determine test strategy
  set_fact:
    test_strategy: >-
      {{ 'direct' if 'direct_port_access' in host_capabilities | default([])
         else 'container' }}

- name: Test Redis (direct)
  command: redis-cli -a {{ redis_password }} PING
  when: test_strategy == 'direct'
  register: redis_ping
  changed_when: false
  failed_when: redis_ping.stdout != "PONG"

- name: Test Redis (container exec)
  command: podman exec {{ redis_svc_name }}-svc redis-cli -a {{ redis_password }} PING
  when: test_strategy == 'container'
  register: redis_ping
  changed_when: false
  failed_when: redis_ping.stdout != "PONG"
```

### Complex Services (Elasticsearch, Mattermost)

**Characteristics**:
- Multiple endpoints
- Complex API
- Requires authentication
- State management

**Test Strategy**:
```yaml
# roles/elasticsearch/tasks/verify.yml
---
- name: Systemd check
  include_tasks: verify_systemd.yml

- name: Determine test strategy
  set_fact:
    test_strategy: >-
      {{ 'external' if 'traefik_routing' in host_capabilities | default([])
         else 'direct' if 'direct_port_access' in host_capabilities | default([])
         else 'container' }}

- name: API verification
  include_tasks: "verify_api_{{ test_strategy }}.yml"

- name: Data directory verification
  include_tasks: verify_data.yml
  when: "'local_file_access' in host_capabilities | default([])"

- name: Performance verification
  include_tasks: verify_performance.yml
  when:
    - test_strategy == 'direct'
    - elasticsearch_verify_performance | default(false)
```

### Infrastructure Services (Traefik, HashiVault)

**Characteristics**:
- Required by other services
- Complex routing rules
- Certificate management

**Test Strategy**:
```yaml
# roles/traefik/tasks/verify.yml
---
- name: Systemd check
  include_tasks: verify_systemd.yml

- name: Check dashboard access
  uri:
    url: "http://localhost:{{ traefik_dashboard_port }}"
    method: GET
  when: "'direct_port_access' in host_capabilities | default([])"

- name: Verify certificate resolver
  include_tasks: verify_acme.yml
  when:
    - traefik_acme_enabled | default(false)
    - "'external_dns' in host_capabilities | default([])"

- name: Test routing rules
  include_tasks: verify_routing.yml
  when: traefik_verify_routing | default(true)
```

## Future Enhancements

### Dynamic Capability Detection

Instead of manual declaration, detect capabilities automatically:

```yaml
# roles/_base/tasks/detect_capabilities.yml
---
- name: Detect direct port access
  wait_for:
    host: localhost
    port: 22
    timeout: 1
  ignore_errors: yes
  register: direct_access_test

- name: Detect container exec
  command: podman version
  ignore_errors: yes
  register: container_test

- name: Build capability list
  set_fact:
    detected_capabilities: >-
      {{ [] +
         (['direct_port_access'] if direct_access_test is success else []) +
         (['container_exec'] if container_test is success else []) }}
```

### Capability Requirements in Role Metadata

Roles declare required capabilities:

```yaml
# roles/elasticsearch/meta/main.yml
---
dependencies: []
requirements:
  minimum_capabilities:
    - systemd_user
  preferred_capabilities:
    - direct_port_access
    - local_file_access
  optional_capabilities:
    - traefik_routing
    - selinux_enforcing
```

### Test Matrix Generation

Automatically generate test matrices based on capabilities:

```yaml
# Generate test matrix for CI
- name: Build test matrix
  set_fact:
    test_matrix:
      - host: firefly
        capabilities: [direct_port_access, container_exec]
        tests: [systemd, api_direct, indexing]
      - host: podma
        capabilities: [traefik_routing, external_dns]
        tests: [systemd, api_external, ssl_cert]
```

## Related Documentation

- [Inventory-System-Overview.md](Inventory-System-Overview.md) - Inventory structure
- [Inventory-Architecture-Goals.md](Inventory-Architecture-Goals.md) - Vision
- [Migration-Phases.md](Migration-Phases.md) - Implementation roadmap
- [Solti-Container-Pattern.md](../Solti-Container-Pattern.md) - Role structure
