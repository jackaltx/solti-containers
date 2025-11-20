# Traefik Label Consolidation Pattern

**Status:** Proposed for Future Implementation
**Date:** 2025-01-20
**Related:** Container-Role-Architecture.md, Solti-Container-Pattern.md

## Executive Summary

This document describes a future enhancement pattern for consolidating Traefik label generation into the `_base` role, following the established SOLTI inheritance model. This would reduce code duplication and ensure consistent Traefik integration across all services.

**Current State:** Each service role independently generates Traefik labels using dict format (completed 2025-01-20)
**Proposed State:** `_base` role generates Traefik labels dynamically from service properties

---

## Current Implementation (As of 2025-01-20)

### Standardization Complete

All 9 services now follow a consistent pattern:

1. **Enable flag:** `<service>_enable_traefik: true` in `defaults/main.yml`
2. **Dict format:** Using `label:` dict instead of `quadlet_options` with `Label=` strings
3. **Conditional enable:** `traefik.enable: "{{ <service>_enable_traefik | lower }}"`
4. **No HTTP redirect:** All use `secHeaders@file` only (no `redirect-to-https@file`)
5. **Port 8080:** Traefik listens on 8080 for HTTPS (websecure entrypoint only)

### Example (Current Pattern)

```yaml
# roles/grafana/defaults/main.yml
grafana_enable_traefik: true

# roles/grafana/tasks/quadlet_rootless.yml
label:
  traefik.enable: "{{ grafana_enable_traefik | lower }}"
  traefik.http.routers.grafana.rule: "Host(`{{ grafana_fqdn }}`)"
  traefik.http.routers.grafana.entrypoints: "websecure"
  traefik.http.routers.grafana.service: "grafana"
  traefik.http.services.grafana.loadbalancer.server.port: "3000"
  traefik.http.routers.grafana.middlewares: "secHeaders@file"
```

### Advantages of Current Approach

✅ **Simple:** Each service owns its Traefik configuration
✅ **Explicit:** Labels are visible in each role's quadlet file
✅ **Flexible:** Services can customize labels easily
✅ **Debuggable:** No abstraction layer to troubleshoot

### Problems with Current Approach

❌ **Duplication:** Same label generation logic repeated 9 times
❌ **Inconsistency risk:** Changes must be applied to all services manually
❌ **Maintenance burden:** Bug fixes require editing multiple files
❌ **No validation:** Services can define invalid Traefik configurations

---

## Proposed Pattern: _base Role Consolidation

### Core Concept

Move Traefik label generation to `_base` role, where services declare their intent via `service_properties` and `_base` generates the labels dynamically.

This mirrors existing `_base` patterns:
- **Network setup:** All services use `ct-net` via `_base`
- **Directory creation:** Standardized paths via `_base`
- **SELinux contexts:** Applied consistently via `_base`

### Architecture

```
Service Role (defaults/main.yml)
    ↓ declares traefik properties
service_properties:
  traefik:
    enabled: true
    containers:
      - name: grafana-svc
        router: grafana
        hostname: "{{ grafana_fqdn }}"
        port: 3000
    ↓
_base Role (tasks/traefik_labels.yml)
    ↓ generates labels
traefik_labels:
  traefik.enable: "true"
  traefik.http.routers.grafana.rule: "Host(`grafana.domain`)"
  ...
    ↓
Service Role (tasks/quadlet_rootless.yml)
    ↓ uses generated labels
label: "{{ traefik_labels }}"
```

---

## Implementation Design

### Phase 1: Service Property Declaration

Each service declares Traefik requirements in `service_properties`:

```yaml
# roles/grafana/defaults/main.yml
service_properties:
  root: "grafana"
  name: "grafana-pod"
  data_dir: "{{ grafana_data_dir }}"

  # NEW: Traefik integration
  traefik:
    enabled: "{{ grafana_enable_traefik | default(true) }}"
    containers:
      - name: grafana-svc          # Container to expose
        router: grafana             # Router name
        hostname: "{{ grafana_fqdn }}"
        port: 3000
        middlewares:
          - secHeaders@file
```

### Phase 2: _base Label Generation

Create `roles/_base/tasks/traefik_labels.yml`:

```yaml
---
# Generate Traefik labels from service properties

- name: Initialize traefik_labels dict
  set_fact:
    traefik_labels: {}
  when: service_properties.traefik is defined

- name: Generate Traefik labels for each container
  set_fact:
    traefik_labels: "{{ traefik_labels | combine(container_labels) }}"
  vars:
    container_labels:
      traefik.enable: "{{ service_properties.traefik.enabled | lower }}"
      "traefik.http.routers.{{ item.router }}.rule": "Host(`{{ item.hostname }}`)"
      "traefik.http.routers.{{ item.router }}.entrypoints": "websecure"
      "traefik.http.routers.{{ item.router }}.service": "{{ item.router }}"
      "traefik.http.services.{{ item.router }}.loadbalancer.server.port": "{{ item.port }}"
      "traefik.http.routers.{{ item.router }}.middlewares": "{{ item.middlewares | join(',') }}"
  loop: "{{ service_properties.traefik.containers }}"
  when:
    - service_properties.traefik is defined
    - service_properties.traefik.enabled | bool
```

### Phase 3: Service Role Usage

Services include `_base` label generation and use the result:

```yaml
# roles/grafana/tasks/quadlet_rootless.yml

- name: Generate Traefik labels
  include_tasks: ../../_base/tasks/traefik_labels.yml

- name: Create Grafana container Quadlet
  containers.podman.podman_container:
    name: grafana-svc
    pod: grafana.pod
    image: "{{ grafana_image }}"
    state: quadlet
    # ... other config ...
    label: "{{ traefik_labels }}"  # Use generated labels
    quadlet_options:
      - "EnvironmentFile={{ real_user_dir }}/.config/containers/systemd/env/grafana.env"
      # ... rest of quadlet config ...
```

---

## Multi-Container Pattern

Services with multiple containers (like Minio with API + Console):

```yaml
# roles/minio/defaults/main.yml
service_properties:
  traefik:
    enabled: "{{ minio_enable_traefik | default(true) }}"
    containers:
      # API endpoint
      - name: minio-svc
        router: minio-api
        hostname: "{{ minio_api_domain }}"
        port: 9000
        middlewares:
          - secHeaders@file

      # Console endpoint
      - name: minio-svc
        router: minio-console
        hostname: "{{ minio_console_domain }}"
        port: 9001
        middlewares:
          - secHeaders@file
```

The `_base` role loops through all containers and generates labels for each.

---

## Multi-Router Pattern

Services with hostname aliases (like Elasticsearch: `elasticsearch.domain` + `es.domain`):

```yaml
# roles/elasticsearch/defaults/main.yml
service_properties:
  traefik:
    enabled: "{{ elasticsearch_enable_traefik | default(true) }}"
    containers:
      - name: elasticsearch-svc
        routers:
          # Primary hostname
          - name: elasticsearch0
            hostname: "{{ elasticsearch_fqdn }}"
            service: elasticsearch0
            middlewares:
              - secHeaders@file

          # Short hostname alias
          - name: elasticsearch1
            hostname: "{{ elasticsearch_fqdn_short }}"
            service: elasticsearch0  # Both route to same service
            middlewares:
              - secHeaders@file

        port: 9200
```

---

## Internal-Only Containers

Services that should NOT be exposed via Traefik:

```yaml
# roles/redis/defaults/main.yml
service_properties:
  traefik:
    enabled: "{{ redis_enable_traefik | default(true) }}"
    containers:
      # Redis server - no Traefik exposure
      - name: redis-svc
        traefik: false  # Explicitly mark as internal-only

      # Redis GUI - exposed via Traefik
      - name: redis-gui
        router: redis
        hostname: "{{ redis_svc_name }}.{{ domain }}"
        port: 8081
        middlewares:
          - secHeaders@file
        when: "{{ redis_enable_gui | bool }}"
```

---

## Benefits of _base Pattern

### Code Reduction

**Current:** ~450 lines of duplicated label code across 9 services
**Proposed:** ~100 lines in `_base` + ~100 lines of declarations = 80% reduction

### Consistency

✅ All services generate labels the same way
✅ Bugs fixed once in `_base`, applied everywhere
✅ New Traefik features added centrally
✅ Validation logic enforced for all services

### Maintainability

✅ Single source of truth for label generation
✅ Changes propagate automatically to all services
✅ Easier to add new services (just declare properties)
✅ Testing focused on `_base` instead of 9 roles

### Flexibility

✅ Services can still override via `traefik_labels_override`
✅ Complex patterns (multi-router, multi-container) supported
✅ Conditional container exposure handled cleanly

---

## Tradeoffs

### Advantages

| Aspect | Current (Dict per Service) | Proposed (_base Pattern) |
|--------|---------------------------|--------------------------|
| **Code duplication** | High (9 copies) | Low (1 generator) |
| **Consistency** | Manual enforcement | Automatic |
| **Debugging** | Labels visible in role | Requires understanding _base |
| **Special cases** | Easy to customize | Requires pattern support |
| **Onboarding** | Simple to understand | Requires learning _base |
| **Validation** | None | Centralized |

### Disadvantages

❌ **Abstraction complexity:** Adds indirection layer
❌ **Debugging difficulty:** Label issues require checking both service and _base
❌ **Migration effort:** All 9 services must be refactored
❌ **Special case handling:** Complex patterns (Minio, Elasticsearch) need careful design

---

## Migration Strategy

### Phase 1: Prototype (1 service)

1. Create `roles/_base/tasks/traefik_labels.yml`
2. Refactor Grafana (simplest single-container service)
3. Test thoroughly
4. Validate generated labels match current output

### Phase 2: Simple Services (4 services)

1. Migrate single-container services:
   - Mattermost
   - HashiVault
   - Gitea
   - InfluxDB3

### Phase 3: Complex Services (4 services)

1. Migrate multi-router/multi-container services:
   - Elasticsearch (2 routers, 1 service)
   - Minio (2 routers, 2 ports)
   - Redis (conditional GUI container)
   - Traefik (dashboard with TLS cert resolver)

### Phase 4: Deprecation

1. Remove old pattern documentation
2. Update CLAUDE.md with new pattern
3. Add validation to prevent mixing patterns

---

## Testing Strategy

### Unit Tests (Molecule)

```yaml
# Test label generation in _base
- name: Test single-container label generation
  assert:
    that:
      - traefik_labels['traefik.enable'] == 'true'
      - traefik_labels['traefik.http.routers.grafana.rule'] == 'Host(`grafana.example.com`)'

- name: Test multi-container label generation
  assert:
    that:
      - traefik_labels['traefik.http.routers.minio-api.rule'] is defined
      - traefik_labels['traefik.http.routers.minio-console.rule'] is defined
```

### Integration Tests

1. Deploy service with `_base` generated labels
2. Verify Traefik sees the labels: `podman inspect <container> | jq .Config.Labels`
3. Test HTTPS access: `curl -k https://<service>.domain:8080`
4. Verify generated quadlet files match expected format

---

## Decision: When to Implement

### Implement Now If:
- Adding 3+ new services soon
- Traefik configuration changing frequently
- Team has strong Ansible/Jinja2 skills

### Defer Implementation If:
- Service count stable (not adding many new services)
- Current pattern working well
- Team prefers explicit over abstract
- Other higher-priority refactoring needed

### Recommended Timeline

**Q1 2025:** Defer - current standardization sufficient
**Q2 2025:** Revisit if adding 3+ new services
**Q3 2025:** Implement if pattern proves beneficial

---

## Related Patterns

### Similar _base Consolidations

1. **Network setup** (`roles/_base/tasks/prepare.yml`)
   - All services use `ct-net` via `_base`
   - Services declare via `service_network` variable

2. **Directory creation** (`roles/_base/tasks/prepare.yml`)
   - Standard paths created via `_base`
   - Services declare via `service_properties.dirs`

3. **SELinux contexts** (`roles/_base/tasks/prepare.yml`)
   - Applied consistently via `_base`
   - Services benefit automatically

### Potential Future Consolidations

- **Health checks:** Standardized container health check generation
- **Resource limits:** CPU/memory limits via `service_properties`
- **Logging configuration:** Centralized logging label generation
- **Backup labels:** Standardized backup metadata

---

## References

- **Current implementation:** Sprint completed 2025-01-20
- **Architecture:** [Container-Role-Architecture.md](Container-Role-Architecture.md)
- **Pattern guide:** [Solti-Container-Pattern.md](Solti-Container-Pattern.md)
- **Git commit:** Search for "Traefik standardization sprint"

---

## Appendix: Code Comparison

### Before (_base Pattern)

**Service declares intent:**
```yaml
# 10 lines in defaults/main.yml
service_properties:
  traefik:
    enabled: true
    containers:
      - name: grafana-svc
        router: grafana
        hostname: "{{ grafana_fqdn }}"
        port: 3000
```

**Service uses generated labels:**
```yaml
# 3 lines in quadlet_rootless.yml
- include_tasks: ../../_base/tasks/traefik_labels.yml

label: "{{ traefik_labels }}"
```

**Total per service:** ~13 lines

### After (Current Dict Pattern)

**Service generates labels directly:**
```yaml
# 7 lines in quadlet_rootless.yml
label:
  traefik.enable: "{{ grafana_enable_traefik | lower }}"
  traefik.http.routers.grafana.rule: "Host(`{{ grafana_fqdn }}`)"
  traefik.http.routers.grafana.entrypoints: "websecure"
  traefik.http.routers.grafana.service: "grafana"
  traefik.http.services.grafana.loadbalancer.server.port: "3000"
  traefik.http.routers.grafana.middlewares: "secHeaders@file"
```

**Total per service:** ~7 lines

### Analysis

**_base pattern:** More lines per service (13 vs 7), but centralized logic
**Current pattern:** Fewer lines per service, but 9x duplication
**Tipping point:** ~5 services (current: 9 services = worth considering)

---

## Contact

For questions about this pattern:
- Review Container-Role-Architecture.md for inheritance model
- Check git history for "Traefik standardization sprint"
- Consult with Claude Code about implementation details
