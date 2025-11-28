# Check Upgrade Pattern

## Overview

The `check_upgrade.yml` task file provides a standardized, **generic** way to check if container image updates are available for a service, without requiring shell access inside containers. The pattern automatically discovers all containers in the pod and checks each one.

## Purpose

As container images evolve (e.g., Mattermost v11 removing shell access), traditional verification methods that rely on executing commands inside containers become unreliable. The check_upgrade pattern:

1. **Auto-discovers all containers** in the pod (works for 1 or N containers)
2. Works without shell access in containers
3. Uses only podman commands available on the host
4. Provides clear per-container and summary upgrade status
5. Sets facts for programmatic use

## Usage

```bash
# Check upgrade on any host
./svc-exec.sh -h <host> -i inventory/<host>.yml <service> check_upgrade

# Examples
./svc-exec.sh -h podma -i inventory/podma.yml mattermost check_upgrade
./svc-exec.sh mattermost check_upgrade  # defaults to localhost
```

## Implementation Pattern

The pattern is implemented in the **`_base` role** and inherited by all service roles.

### Architecture

**Common implementation in `_base` role:**

- `roles/_base/tasks/check_upgrade.yml` - Main orchestrator
- `roles/_base/tasks/check_upgrade_container.yml` - Per-container checker

**Service role wrapper:**

- `roles/<service>/tasks/check_upgrade.yml` - Simple include of `_base` implementation

### File 1: `_base/tasks/check_upgrade.yml` - Main orchestrator

Discovers all containers in the pod and coordinates checking each one:

```yaml
---
# check_upgrade.yml - Check if container image updates are available
# Generic pattern that discovers all containers in pod

- name: Get all containers in pod
  command: >
    podman ps --filter "pod={{ service_properties.root }}" --format '{% raw %}{{.Names}}|{{.Image}}{% endraw %}'
  register: pod_containers
  changed_when: false

- name: Display discovered containers
  debug:
    msg: "Found {{ pod_containers.stdout_lines | length }} container(s) in pod: {{ service_properties.root }}"

- name: Check each container for updates
  include_tasks: check_upgrade_container.yml
  loop: "{{ pod_containers.stdout_lines }}"
  loop_control:
    loop_var: container_info
  when: "'infra' not in container_info"  # Skip pause/infra container

- name: Summary of upgrade status
  debug:
    msg: "{{ upgrade_summary }}"
  vars:
    upgrade_summary: >-
      {%- set updates = [] -%}
      {%- for result in container_checks | default([]) -%}
        {%- if result.upgrade_available -%}
          {%- set _ = updates.append(result.container_name) -%}
        {%- endif -%}
      {%- endfor -%}
      {%- if updates | length > 0 -%}
      UPDATES AVAILABLE for: {{ updates | join(', ') }}
      {%- else -%}
      All containers up to date
      {%- endif -%}
```

### File 2: `_base/tasks/check_upgrade_container.yml` - Per-container checker

Performs the actual check for a single container:

```yaml
---
# check_upgrade_container.yml - Check single container for updates
# Expects: container_info (format: "name|image")

- name: Parse container info
  set_fact:
    container_name: "{{ container_info.split('|')[0] }}"
    container_image: "{{ container_info.split('|')[1] }}"

- name: Get current container image ID
  command: >
    podman inspect {{ container_name }} --format '{% raw %}{{.Image}}{% endraw %}'
  register: current_image_id
  changed_when: false

- name: Get current image creation time
  command: >
    podman image inspect {{ current_image_id.stdout }} --format '{% raw %}{{.Created}}{% endraw %}'
  register: current_created
  changed_when: false

- name: Pull latest image from registry
  command: >
    podman pull {{ container_image }}
  register: pull_result
  changed_when: "'Copying blob' in pull_result.stderr or 'Copying config' in pull_result.stderr"
  failed_when: false

- name: Get latest image ID
  command: >
    podman image inspect {{ container_image }} --format '{% raw %}{{.Id}}{% endraw %}'
  register: latest_image_id
  changed_when: false

- name: Display container status
  debug:
    msg: "{{ status_msg }}"
  vars:
    upgrade_available: "{{ current_image_id.stdout != latest_image_id.stdout }}"
    status_msg: >-
      {{ container_name }}:
      {%- if upgrade_available -%}
      UPDATE AVAILABLE - Current: {{ current_image_id.stdout[:12] }} | Latest: {{ latest_image_id.stdout[:12] }}
      {%- else -%}
      Up to date ({{ current_image_id.stdout[:12] }})
      {%- endif -%}

- name: Collect result
  set_fact:
    container_checks: "{{ container_checks | default([]) + [check_result] }}"
  vars:
    check_result:
      container_name: "{{ container_name }}"
      container_image: "{{ container_image }}"
      upgrade_available: "{{ current_image_id.stdout != latest_image_id.stdout }}"
      current_image_id: "{{ current_image_id.stdout }}"
      latest_image_id: "{{ latest_image_id.stdout }}"
```

### File 3: Service role wrapper - `<service>/tasks/check_upgrade.yml`

Each service role has a simple wrapper that includes the `_base` implementation:

```yaml
---
# check_upgrade.yml - Check if container image updates are available
# This role uses the common implementation from _base

- name: Include _base check_upgrade implementation
  ansible.builtin.include_tasks:
    file: ../_base/tasks/check_upgrade.yml
```

This preserves the service's variables (like `service_properties`) while using the common code.

### Key Design Elements

1. **Centralized in `_base`**: Common implementation written once, inherited by all services
2. **Auto-discovery**: Uses `service_properties.root` to find pod, then lists all containers
3. **Skip infra**: Filters out pause/infra containers automatically
4. **Per-container output**: Shows status for each container individually
5. **Aggregate facts**: Collects all results in `container_checks` list
6. **Summary**: Final task provides overall upgrade status
7. **Variable preservation**: Uses `include_tasks` to maintain service context

## Example Output

### Mattermost with Updates Available (localhost)

```
TASK [mattermost : Display discovered containers]
ok: [firefly] => {
    "msg": "Found 3 container(s) in pod: mattermost"
}

TASK [mattermost : Display container status]
ok: [firefly] => {
    "msg": "mattermost-svc:UPDATE AVAILABLE - Current: bda0ac478a7f | Latest: 33f64e748731"
}

TASK [mattermost : Display container status]
ok: [firefly] => {
    "msg": "mattermost-db:UPDATE AVAILABLE - Current: 8c74beeec387 | Latest: 4ba28b1f75f3"
}

TASK [mattermost : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: mattermost-svc, mattermost-db"
}
```

### Mattermost Up-to-Date (podma)

```
TASK [mattermost : Display discovered containers]
ok: [podma] => {
    "msg": "Found 3 container(s) in pod: mattermost"
}

TASK [mattermost : Display container status]
ok: [podma] => {
    "msg": "mattermost-db:Up to date (216e5ca6a814)"
}

TASK [mattermost : Display container status]
ok: [podma] => {
    "msg": "mattermost-svc:Up to date (33f64e748731)"
}

TASK [mattermost : Summary of upgrade status]
ok: [podma] => {
    "msg": "All containers up to date"
}
```

### Redis with Partial Update (localhost)

```
TASK [redis : Display discovered containers]
ok: [firefly] => {
    "msg": "Found 3 container(s) in pod: redis"
}

TASK [redis : Display container status]
ok: [firefly] => {
    "msg": "redis-gui:Up to date (778af9bd6397)"
}

TASK [redis : Display container status]
ok: [firefly] => {
    "msg": "redis-svc:UPDATE AVAILABLE - Current: b2833885c489 | Latest: 38ce10209598"
}

TASK [redis : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: redis-svc"
}
```

## Integration with Playbooks

The `container_checks` fact provides detailed information for automation:

```yaml
- name: Check for updates
  include_role:
    name: mattermost
    tasks_from: check_upgrade

- name: Display containers needing updates
  debug:
    msg: "{{ item.container_name }} needs update: {{ item.current_image_id[:12] }} → {{ item.latest_image_id[:12] }}"
  loop: "{{ container_checks | default([]) }}"
  when: item.upgrade_available

- name: Perform upgrade if any container has updates
  include_role:
    name: mattermost
    tasks_from: upgrade
  when: container_checks | default([]) | selectattr('upgrade_available', 'equalto', true) | list | length > 0
```

### Available Facts in `container_checks`

Each entry in the `container_checks` list contains:

- `container_name` - Name of the container
- `container_image` - Full image reference (e.g., docker.io/library/redis:7.2-alpine)
- `upgrade_available` - Boolean
- `current_image_id` - Full SHA256 image ID currently running
- `latest_image_id` - Full SHA256 image ID from registry
- `current_created` - ISO timestamp when current image was created
- `latest_created` - ISO timestamp when latest image was created

## Key Design Decisions

1. **Centralized in `_base` role**: Common implementation written once, bugs fixed once, benefits all services
2. **Auto-discovery**: No hardcoded container names - discovers all containers in pod dynamically
3. **No shell access required**: Uses only podman inspect/pull commands on the host
4. **Multi-container aware**: Handles services with 1 or N containers automatically
5. **Skip infra containers**: Filters out pause/infra containers that don't need checking
6. **Actual pull vs metadata**: Performs real pull to ensure accurate comparison (lightweight for already-cached images)
7. **Changed detection**: Only marks as changed if new image data was downloaded
8. **Aggregate facts**: Collects all results in `container_checks` list for programmatic use
9. **Short IDs in output**: Displays first 12 chars of image IDs for readability
10. **Variable preservation**: Uses `include_tasks` (not `include_role`) to preserve service context

## Applying to Other Services

To add check_upgrade to another service:

1. Copy the simple wrapper file:

   ```bash
   cp roles/mattermost/tasks/check_upgrade.yml roles/<service>/tasks/
   ```

2. **No modifications needed** - the wrapper is identical for all services

3. Test with: `./svc-exec.sh <service> check_upgrade`

### Example - Adding to Grafana

```bash
cp roles/mattermost/tasks/check_upgrade.yml roles/grafana/tasks/
./svc-exec.sh grafana check_upgrade
```

That's it! The `_base` implementation automatically discovers all containers in the grafana pod and checks each one.

### Why This Works

- Common implementation lives in `roles/_base/tasks/`
- Service wrapper uses `include_tasks` with relative path `../_base/tasks/check_upgrade.yml`
- This preserves the service's `service_properties` variable
- Pattern works identically for all services

## See Also

- [roles/_base/tasks/check_upgrade.yml](../roles/_base/tasks/check_upgrade.yml) - Main orchestrator (centralized implementation)
- [roles/_base/tasks/check_upgrade_container.yml](../roles/_base/tasks/check_upgrade_container.yml) - Per-container checker (centralized implementation)
- [roles/mattermost/tasks/check_upgrade.yml](../roles/mattermost/tasks/check_upgrade.yml) - Service wrapper example
- [roles/redis/tasks/check_upgrade.yml](../roles/redis/tasks/check_upgrade.yml) - Another service wrapper example
- [Solti Container Pattern](Solti-Container-Pattern.md) - Overall role structure
- [Service Management Scripts](../manage-svc.sh) - Lifecycle management
