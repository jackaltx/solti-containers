# _base Role - Shared Infrastructure

**Purpose**: Internal role providing common functionality for all SOLTI container services through task inclusion (simulated inheritance).

## Why This Exists

Ansible has no native role inheritance. This role implements a **shared infrastructure pattern** where service roles include `_base` tasks to eliminate code duplication. Instead of each service implementing directory creation, network setup, SELinux configuration, and cleanup separately, `_base` provides these generically.

**Key Benefit**: Write common functionality once, use across all 10+ services. Fix a bug in `_base`, fix it everywhere instantly.

## Pattern: Service Properties + Generic Tasks

Service roles define a `service_properties` dictionary (what they need), and `_base` tasks consume it generically (how to do it).

**Example** (from redis/defaults/main.yml):

```yaml
service_properties:
  root: "redis"
  name: "redis-pod.service"
  data_dir: "{{ ansible_facts.user_dir }}/redis-data"
  dirs:
    - { path: "", mode: "0755" }
    - { path: "config", mode: "0775" }
    - { path: "data", mode: "0775" }
  quadlets:
    - "redis-svc.container"
    - "redis.pod"
```

**Usage** (in service role tasks/prepare.yml):

```yaml
- name: Include _base prepare tasks
  ansible.builtin.include_tasks:
    file: ../_base/tasks/prepare.yml
```

The `_base/tasks/prepare.yml` reads `service_properties.dirs` and creates them generically - no service-specific code needed.

## Available Tasks

Service roles can include these `_base` tasks:

### prepare.yml

Creates directory structure and applies SELinux contexts.

**What it does**:

- Validates required variables (data_dir, config_dir, dirs)
- Creates all directories in `service_properties.dirs` with specified modes
- Sets ownership to `real_user` (rootless containers)
- Applies SELinux `container_file_t` context on RHEL-based systems
- Handles SELinux failures gracefully (falls back to chcon)

**When to include**: In service's `tasks/prepare.yml` (one-time setup)

### networks.yml

Creates shared container network (`ct-net`) used by all services.

**What it does**:

- Creates Podman network with DNS enabled
- Configures DNS servers (1.1.1.1, 8.8.8.8)
- Sets DNS search domain (example.com)
- Idempotent - safe to run multiple times

**When to include**: In service's `tasks/prepare.yml` (before container deployment)

### check_upgrade.yml

Checks if newer container image versions are available.

**What it does**:

- Reads `service_properties.quadlets` list
- For each quadlet, extracts container name
- Calls `check_upgrade_container.yml` for each container
- Compares current image digest vs. remote registry latest
- Reports "UPDATE AVAILABLE" or "Up to date"

**When to include**: In service's `tasks/check_upgrade.yml` (6-line wrapper pattern)

**Example wrapper**:

```yaml
---
# check_upgrade.yml - Check if container image updates are available

- name: Include _base check_upgrade implementation
  ansible.builtin.include_tasks:
    file: ../_base/tasks/check_upgrade.yml
```

### cleanup.yml

Removes containers, pods, and optionally data directories.

**What it does**:

- Stops and removes all containers in `service_properties.quadlets`
- Removes pod if defined
- Deletes data directory if `DELETE_DATA=true` env var set
- Removes container images if `DELETE_IMAGES=true` env var set
- Preserves data by default (safe for redeploy/upgrade)

**When to include**: In service's `tasks/cleanup.yml` (removal operations)

### containers.yml

(Legacy/unused) - Container management tasks superseded by quadlet pattern.

## Standard Variables

All `_base` tasks expect these variables to be defined:

### service_properties Dictionary

```yaml
service_properties:
  root: ""              # Service name (e.g., "elasticsearch")
  name: ""              # Systemd service name (e.g., "elasticsearch-pod")
  pod_key: ""           # Pod reference (e.g., "elasticsearch.pod")
  quadlets: []          # List of quadlet filenames
  data_dir: ""          # Main data directory path
  config_dir: "config"  # Config subdirectory (default: "config")
  delete_data: false    # Delete data on removal (override: DELETE_DATA env)
  delete_images: false  # Delete images on removal (override: DELETE_IMAGES env)
  dirs: []              # Required directories [{path: "", mode: "0755"}, ...]
```

**Required fields**: `root`, `name`, `data_dir`, `dirs`, `quadlets`

**Optional fields**: All others have defaults

### Global Service Variables

Defined in `_base/defaults/main.yml`, shared across all services:

```yaml
# Container networking
service_network: "ct-net"
service_dns_servers:
  - "1.1.1.1"
  - "8.8.8.8"
service_dns_search: "example.com"

# Systemd integration
service_quadlet_dir: "{{ lookup('env', 'HOME') }}/.config/containers/systemd"
```

## File Structure

```text
roles/_base/
├── defaults/
│   └── main.yml              # Global service variables
├── tasks/
│   ├── prepare.yml           # Directory creation, SELinux
│   ├── networks.yml          # ct-net creation
│   ├── check_upgrade.yml     # Upgrade detection (wrapper)
│   ├── check_upgrade_container.yml  # Per-container upgrade logic
│   ├── cleanup.yml           # Removal operations
│   └── containers.yml        # (Legacy)
└── Readme.md                 # This file
```

## Usage Pattern in Service Roles

**Complete example** (elasticsearch role structure):

```yaml
# roles/elasticsearch/defaults/main.yml
service_properties:
  root: "elasticsearch"
  name: "elasticsearch-pod.service"
  data_dir: "{{ ansible_facts.user_dir }}/elasticsearch-data"
  quadlets:
    - "elasticsearch-svc.container"
    - "elasticsearch.pod"
  dirs:
    - { path: "", mode: "0755" }
    - { path: "config", mode: "0775" }
    - { path: "data", mode: "0775" }

# roles/elasticsearch/tasks/prepare.yml
---
- name: Include _base prepare
  ansible.builtin.include_tasks:
    file: ../_base/tasks/prepare.yml

- name: Include _base networks
  ansible.builtin.include_tasks:
    file: ../_base/tasks/networks.yml

# Service-specific setup continues...

# roles/elasticsearch/tasks/check_upgrade.yml
---
- name: Include _base check_upgrade implementation
  ansible.builtin.include_tasks:
    file: ../_base/tasks/check_upgrade.yml

# roles/elasticsearch/tasks/cleanup.yml
---
- name: Include _base cleanup
  ansible.builtin.include_tasks:
    file: ../_base/tasks/cleanup.yml

# Service-specific cleanup continues...
```

## Benefits of This Pattern

1. **DRY (Don't Repeat Yourself)**: 98% reduction in boilerplate code per service
2. **Consistency**: All services use identical directory setup, SELinux, network creation
3. **Maintainability**: Fix a bug in `_base`, fixes all 10+ services instantly
4. **Extensibility**: Add new common functionality once, all services inherit it
5. **Clarity**: Service roles focus on service-specific logic, not infrastructure

## Trade-offs

**Pros**:

- Shared functionality centralized
- Easy to add new services (minimal code)
- Consistent patterns across all services

**Cons**:

- Not true inheritance (explicit include_tasks required)
- Less discoverable (need to read _base to understand full behavior)
- Changes to _base affect all services (test carefully)

## This is NOT User Documentation

This README is for **developers working on SOLTI container roles**. Users deploying services should:

- **NOT** interact with `_base` directly
- Read individual service READMEs (roles/redis/README.md, roles/mattermost/README.md, etc.)
- Use management scripts (manage-svc.sh, svc-exec.sh)

## See Also

- [docs/Claude-new-quadlet.md](../../docs/Claude-new-quadlet.md) - Complete pattern documentation
- [docs/Container-Role-Architecture.md](../../docs/Container-Role-Architecture.md) - Architectural overview
- [docs/Check-Upgrade-Pattern.md](../../docs/Check-Upgrade-Pattern.md) - Upgrade detection details

## When to Modify _base

**Add to _base when**:

- Functionality is needed by 3+ services
- Logic is truly generic (uses service_properties, no hardcoded service names)
- Reduces significant duplication

**Keep in service role when**:

- Service-specific logic (PostgreSQL for Mattermost, not all services)
- Unique configuration patterns
- One-off requirements

## Example: How prepare.yml Works

When elasticsearch role includes `_base/tasks/prepare.yml`:

1. Reads `elasticsearch` service_properties from defaults/main.yml
2. Validates required fields exist
3. Loops through `service_properties.dirs`: `["", "config", "data"]`
4. Creates: `~/elasticsearch-data/`, `~/elasticsearch-data/config/`, `~/elasticsearch-data/data/`
5. Sets ownership to current user (rootless)
6. Detects RHEL system → applies SELinux `container_file_t` context
7. Returns to elasticsearch role to continue service-specific setup

**Result**: 54 lines of generic code in `_base/tasks/prepare.yml` replaces 540+ lines across 10 service roles.
