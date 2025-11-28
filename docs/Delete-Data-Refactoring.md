# Delete Data Refactoring: Architecture & Patterns

## Problem Statement

The original `delete_data` pattern required manual variable mapping in every service role, violating the DRY principle and the _base role inheritance pattern. Each service role had to manually map `<service>_delete_data` → `service_delete_data` when calling `_base/tasks/cleanup.yml`.

## Solution Overview

Moved `delete_data` into the `service_properties` structure, making it part of the service's architectural definition rather than a separately-mapped variable. Added environment variable override capability for runtime control.

---

## The _base Inheritance Pattern

### Core Principle: Simulated Inheritance Through Variable Precedence

Ansible doesn't support true role inheritance, but we simulate it using **variable precedence**:

```
_base/defaults/main.yml (lowest precedence)
    ↓ defines template
<service>/defaults/main.yml (higher precedence)
    ↓ overrides with service-specific values
_base/tasks/*.yml (generic consumers)
    ↓ uses service_properties generically
```

### How It Works

**1. _base defines the template** (`roles/_base/defaults/main.yml`):

```yaml
service_properties:
  root: ""              # Template with empty/default values
  name: ""
  data_dir: ""
  delete_data: false    # Added in this refactoring
  dirs: []
  # ... other fields
```

**2. Service roles override** (`roles/<service>/defaults/main.yml`):

```yaml
service_properties:
  root: "elasticsearch"  # Service-specific values
  name: "elasticsearch-pod"
  data_dir: "{{ elasticsearch_data_dir }}"
  delete_data: "{{ lookup('env', 'DELETE_DATA') | default(false) | bool }}"
  dirs:
    - { path: "", mode: "0750" }
    # ... service-specific directories
```

**3. _base tasks consume generically** (`roles/_base/tasks/cleanup.yml`):

```yaml
- name: Remove all traces
  when: service_state == 'absent' and (service_properties.delete_data | bool)
  block:
    - name: Remove configuration
      become: true
      file:
        path: "{{ service_properties.data_dir }}"
        state: absent
```

### Why This Pattern Works

- **Variable Precedence**: Ansible merges defaults, with role-specific defaults taking precedence over _base defaults
- **Generic Consumption**: _base tasks only reference `service_properties.*` - they never need service-specific variable names
- **Single Source of Truth**: Each service defines its complete `service_properties` structure in one place
- **No Boilerplate**: Service roles don't need manual mapping code

---

## Key Architectural Insights

### 1. service_properties is the Service's "Interface"

Think of `service_properties` as the contract between a service role and _base:

- Service role: "Here's my structure (properties)"
- _base role: "I'll use your structure generically"

### 2. Avoid Inventory Overrides of service_properties

**Problem Found**: inventory.yml had redundant `service_properties` overrides for gitea and influxdb3:

```yaml
# BAD - Don't do this in inventory
influxdb3_svc:
  vars:
    service_properties:
      root: "influxdb3"
      data_dir: "{{ influxdb3_data_dir }}"
      # Missing delete_data field! Breaks the pattern
```

**Why This Breaks**:

- Inventory overrides are **complete replacements**, not merges
- If inventory defines `service_properties`, it must include ALL fields
- Creates maintenance burden - changes to _base template require inventory updates
- Violates single source of truth principle

**Solution**:

- Remove `service_properties` from inventory.yml
- Override individual service variables instead (e.g., `influxdb3_data_dir`)
- Let role defaults define complete `service_properties`

### 3. Environment Variables for Runtime Override

Pattern used throughout:

```yaml
delete_data: "{{ lookup('env', 'DELETE_DATA') | default(false) | bool }}"
```

**Benefits**:

- No inventory edits needed for one-time overrides
- Explicit at invocation: `DELETE_DATA=true ./manage-svc.sh redis remove`
- Consistent with existing password pattern: `lookup('env', 'REDIS_PASSWORD')`

**Special Cases**:

- influxdb3: `default(true)` for dev convenience
- Most services: `default(false)` for safety

---

## Implementation Changes

### Files Modified

**_base template (1 file)**:

- `roles/_base/defaults/main.yml`: Added `delete_data: false` to template

**_base consumer (1 file)**:

- `roles/_base/tasks/cleanup.yml`: Changed `service_delete_data` → `service_properties.delete_data`

**Service role defaults (10 files)**:

- Added `delete_data` field to each `service_properties`
- Removed standalone `<service>_delete_data` variables
- Services: elasticsearch, redis, hashivault, mattermost, traefik, minio, grafana, influxdb3, gitea, wazuh

**Service role tasks (10 files)**:

- Removed manual mapping: `service_delete_data: "{{ <service>_delete_data }}"`
- Cleanup now uses `service_properties.delete_data` directly

**Inventory (1 file)**:

- Removed 8 `<service>_delete_data` variable declarations
- Removed 2 redundant `service_properties` overrides (gitea, influxdb3)

### Code Reduction

- **~26 lines removed**: Manual mapping boilerplate + redundant declarations
- **~12 lines added**: Template field + service overrides
- **Net reduction**: ~14 lines
- **Architectural win**: Eliminated pattern duplication across 10 services

---

## Variable Flow Diagram

### Before (Manual Mapping)

```
inventory.yml
    elasticsearch_delete_data: false
        ↓
roles/elasticsearch/defaults/main.yml
    elasticsearch_delete_data: false  [redundant]
        ↓
roles/elasticsearch/tasks/main.yml
    vars:
      service_delete_data: "{{ elasticsearch_delete_data }}"  [manual mapping]
        ↓
roles/_base/tasks/cleanup.yml
    when: service_delete_data | bool
```

### After (service_properties Pattern)

```
_base/defaults/main.yml (template)
    service_properties.delete_data: false
        ↓
roles/elasticsearch/defaults/main.yml (override)
    service_properties:
      delete_data: "{{ lookup('env', 'DELETE_DATA') | default(false) | bool }}"
        ↓
roles/_base/tasks/cleanup.yml (generic consumer)
    when: service_properties.delete_data | bool
```

---

## Usage Examples

### Basic Usage

**Preserve data (default)**:

```bash
./manage-svc.sh elasticsearch remove
```

**Delete data**:

```bash
DELETE_DATA=true ./manage-svc.sh elasticsearch remove
```

### Development Workflow (influxdb3)

```bash
# Deploy, test, tear down (deletes data by default)
./manage-svc.sh influxdb3 prepare
./manage-svc.sh influxdb3 deploy
./manage-svc.sh influxdb3 remove  # Deletes data

# Preserve data during development
DELETE_DATA=false ./manage-svc.sh influxdb3 remove
```

---

## Future Opportunities: Variable Analysis

### Pattern Recognition

Many variables follow similar patterns across services:

- `<service>_data_dir`: Data directory location
- `<service>_password`: Service credentials
- `<service>_port`: Service port binding
- `<service>_image`: Container image
- `<service>_enable_tls`: TLS configuration

### Candidates for _base Migration

**High Priority** (appear in 8+ services):

1. **data_dir pattern**: Already in `service_properties`
2. **Port binding pattern**: Could standardize format
3. **TLS configuration**: Common structure across services
4. **Password/credential lookup**: Standardize env var pattern

**Medium Priority** (appear in 4-7 services):

1. **GUI/dashboard containers**: Standard naming pattern
2. **Volume mount patterns**: Common structure
3. **Resource limits**: Memory, CPU constraints
4. **Logging configuration**: Log levels, destinations

**Low Priority** (appear in 1-3 services):

1. Service-specific configs (e.g., Redis maxmemory policy)
2. Protocol-specific settings (e.g., Elasticsearch discovery type)

### Analysis Approach

For each variable group:

1. **Identify pattern**: What's common across services?
2. **Extract commonality**: What can move to _base template?
3. **Preserve flexibility**: What must remain service-specific?
4. **Test migration**: Does it simplify or complicate?

### Guiding Principles

**Move to _base if**:

- ✅ Same structure across 5+ services
- ✅ Generic naming possible (not service-specific)
- ✅ Part of service "interface" (used by _base tasks)
- ✅ Reduces boilerplate significantly

**Keep in service role if**:

- ❌ Service-specific logic or naming
- ❌ Used by service tasks only (not _base)
- ❌ High variability between services
- ❌ Domain-specific configuration

---

## Testing & Validation

### Verification Commands

**Check for remaining references**:

```bash
grep -r "service_delete_data" roles/ --include="*.yml"
# Should return no results
```

**Verify service_properties structure**:

```bash
grep -A 15 "^service_properties:" roles/*/defaults/main.yml | grep delete_data
# Should show delete_data in all services
```

**Test environment variable override**:

```bash
# Test with service that has data
./manage-svc.sh redis deploy
./manage-svc.sh redis remove  # Data preserved
ls ~/redis-data  # Should exist

DELETE_DATA=true ./manage-svc.sh redis remove
ls ~/redis-data  # Should not exist
```

---

## Lessons Learned

### 1. Ansible Variable Precedence is Powerful

Understanding precedence rules enables inheritance-like patterns without true OOP.

### 2. Inventory Overrides Can Break Patterns

Be cautious overriding complex structures in inventory - prefer overriding leaf variables.

### 3. Environment Variables Provide Flexibility

Runtime overrides via env vars avoid inventory edits while maintaining safe defaults.

### 4. Template First, Override Second

Define complete templates in _base, let services override with their specific values.

### 5. Generic Consumption is the Goal

If _base tasks reference service-specific variable names, the pattern is broken.

---

## Related Documentation

- [Container-Role-Architecture.md](Container-Role-Architecture.md) - Overall architecture
- [Solti-Container-Pattern.md](Solti-Container-Pattern.md) - Standard role structure

---

**Document Version**: 1.0
**Date**: 2025-01-09
**Author**: Claude Code (with jackaltx)
