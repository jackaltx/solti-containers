# Unify svc_exec.sh and manage-svc.sh

## Rules

This wil install on an "inventory" group host(s). The inventory to be installed is based on a smart mapping.
`<svc_name>_svc` for the group to be installed.

There are three main orthogonal states "prepare", "deploy" and "remove".

The Services are manged inside of this directory.  Secrets are passed in via environment variables
manually sources in from ~/.secrets.

These service run rootless podman xdg runtime, so XDG will chown files for that service.  These rules can be looked up.
To deal this and selinux the "prepare" and "deploy" states were separated.

There are two hosts, localhost and podma in the current database. Podma is a VM ephemeral test service.

Verify tests are use traefix to verify the system is work, not just the local service.

## Manage services

There are two scripts for creating and executing a dynamically generated ansible playbook. Here is current usage informaiton

```
Usage: manage-svc.sh [-i INVENTORY] [-h HOST] [-y] <service> <action> [options]

Options:
  -i INVENTORY     - Path to inventory file (default: $SOLTI_INVENTORY or inventory.yml)
  -h HOST          - Target specific host from inventory (default: uses all hosts in service group)
  -y, --yes        - Skip safety prompts (for automation)
  -e VAR=VALUE     - Set extra variables (can be used multiple times)

Services:
  - elasticsearch
  - hashivault
  - redis
  - mattermost
  - traefik
  - minio
  - wazuh
  - grafana
  - gitea
  - influxdb3
  - mongodb
  - obsidian
  - conduit
  - dns_service

Actions:
  - prepare
  - deploy
  - remove

Examples:
  manage-svc.sh elasticsearch prepare
  manage-svc.sh -h firefly hashivault deploy
  manage-svc.sh -i inventory/podma.yml redis deploy
  manage-svc.sh redis remove
  manage-svc.sh -y redis deploy                              # Skip prompts
  manage-svc.sh mattermost deploy -e mattermost_version=8.1.0
  manage-svc.sh -h firefly elasticsearch prepare -e elasticsearch_memory=2g
```

```
Usage: svc-exec.sh [-i INVENTORY] [-h HOST] [-K] [-y] <service> [entry] [options]

Options:
  -i INVENTORY     - Path to inventory file (default: $SOLTI_INVENTORY or inventory.yml)
  -h HOST          - Target specific host from inventory (default: uses all hosts in service group)
  -K               - Prompt for sudo password (needed for some operations)
  -y, --yes        - Skip safety prompts (for automation)

Parameters:
  service          - The service to manage
  entry            - The entry point task (default: verify)
  options          - Extra variables (-e VAR=VALUE)

Services:
  - elasticsearch
  - hashivault
  - redis
  - mattermost
  - traefik
  - minio
  - wazuh
  - grafana
  - gitea
  - influxdb3
  - mongodb
  - obsidian
  - conduit
  - dns_service

Examples:
  svc-exec.sh elasticsearch verify     # No sudo prompt
  svc-exec.sh -K redis configure       # With sudo prompt
  svc-exec.sh -y elasticsearch verify  # Skip safety prompts
  svc-exec.sh -h firefly mattermost    # Run on specific host
  svc-exec.sh -i inventory/podma.yml redis verify  # Use specific inventory
  svc-exec.sh mattermost               # Default entry, no sudo
  svc-exec.sh redis verify -e redis_password=newpass
  svc-exec.sh -h firefly -K elasticsearch configure -e elasticsearch_memory=4g
```

## workflow breakdown by example

Claude, this is level one..

### manage service state

The script build the dynamic playbook.  it is called a a role and executed main.yml.

```
source ~/.secrets/LabProvision && ./manage-svc.sh redis prepare
```

Executes

```
---
# Dynamically generated playbook
# Works for: prepare, deploy, remove
- name: Manage redis Service
  hosts: redis_svc
  vars:
    redis_state: prepare
  roles:
    - role: redis
```

```
source ~/.secrets/LabProvision && ./manage-svc.sh redis deploy
```

executes

```
---
# Dynamically generated playbook
# Works for: prepare, deploy, remove
- name: Manage redis Service
  hosts: redis_svc
  vars:
    redis_state: present
  roles:
    - role: redis

```

```
source ~/.secrets/LabProvision && DELETE_DATA=true ./manage-svc.sh redis remove
```

executes

```
---
# Dynamically generated playbook
# Works for: prepare, deploy, remove
- name: Manage redis Service
  hosts: redis_svc
  become: true
  vars:
    redis_state: absent
  roles:
    - role: redis

```

### SVC_EXEC example

This build a dynamic playbook that executes a task within a role. This allows the group and host vars to be
loaded from the role!

```
source ~/.secrets/LabProvision && ./svc-exec.sh redis verify
```

executes, this larger script...with a pre and post task list that sends output to matrix chat room
but at the core it executes a role.  

```
---
# Dynamic execution playbook
- name: Execute verify for redis Service
  hosts: redis_svc
  gather_facts: false
  vars:
    matrix_homeserver_url: "{{ lookup('env', 'MATRIX_HOMESERVER_URL') }}"
    matrix_access_token: "{{ lookup('env', 'MATRIX_ACCESS_TOKEN') }}"
    matrix_room_id: "{{ lookup('env', 'MATRIX_ROOM_ID') }}"
    task_service: "redis"
    task_entry: "verify"
    task_host: "all"
    task_start_time: "{{ ansible_facts['date_time']['iso8601'] }}"

  pre_tasks:
    - name: "Log task start to Matrix"
      jackaltx.solti_matrix_mgr.matrix_event:
        homeserver_url: "{{ matrix_homeserver_url }}"
        access_token: "{{ matrix_access_token }}"
        room_id: "{{ matrix_room_id }}"
        content:
          msgtype: "m.text"
          body: "Starting task: {{ task_service }}/{{ task_entry }} on {{ task_host }}"
          solti:
            schema: "task.start.v1"
            source: "svc-exec"
            data:
              service: "{{ task_service }}"
              entry: "{{ task_entry }}"
              host: "{{ task_host }}"
              timestamp: "{{ task_start_time }}"
      when: matrix_access_token | length > 0
      ignore_errors: true

  tasks:
    - name: "Include role task: redis/verify"
      ansible.builtin.include_role:
        name: "{{ task_service }}"
        tasks_from: "{{ task_entry }}"
      register: task_result

  post_tasks:
    - name: "Log task completion to Matrix"
      vars:
        task_status: "{{ 'success' if task_result is succeeded else 'failure' }}"
      jackaltx.solti_matrix_mgr.matrix_event:
        homeserver_url: "{{ matrix_homeserver_url }}"
        access_token: "{{ matrix_access_token }}"
        room_id: "{{ matrix_room_id }}"
        content:
          msgtype: "m.text"
          body: "Task complete: {{ task_service }}/{{ task_entry }} on {{ task_host }} ({{ task_status }})"
          solti:
            schema: "task.complete.v1"
            source: "svc-exec"
            data:
              service: "{{ task_service }}"
              entry: "{{ task_entry }}"
              host: "{{ task_host }}"
              status: "{{ task_status }}"
      when: matrix_access_token | length > 0
      ignore_errors: true

```

## Things the scripts do

### Shared behavior (both scripts)

1. **Resolve working directory** — anchors to the script's own directory, not `$PWD`
2. **Resolve inventory** — `$SOLTI_INVENTORY` env var → `-i` flag → `inventory/localhost.yml` default
3. **Validate service name** — rejects unknown services from a hardcoded `SUPPORTED_SERVICES` array
4. **Validate inventory file exists** — exits early if the file is missing
5. **Create `tmp/` with mode 700** — strict permissions on the temp directory
6. **Generate a timestamped playbook** — written under `tmp/<service>-<action|entry>-<timestamp>.yml` with `umask 077`
7. **Print playbook content** before executing (for visibility)
8. **Detect target context** — classifies the run as `localhost` or `remote` based on inventory filename and `-h HOST` value (hardcoded knowledge of `podma`/`firefly`)
9. **Safety prompt** — soft prompt for localhost, hard `[y/N]` prompt for remote; skipped with `-y`; skipped automatically when inventory + host match consistently
10. **Probe for NOPASSWD sudo** — runs `sudo -n true` via an ad-hoc Ansible command to decide whether to ask for a password
11. **Pass through `-e VAR=VALUE` extra vars** — remaining args after service/action forwarded to `ansible-playbook`
12. **Track execution time** (`manage-svc.sh` only) — captures start/end epoch seconds
13. **Preserve playbook on failure** — `cleanup` trap deletes on success; leaves file in `tmp/` on error for debugging
14. **Optional Matrix logging** — calls `bin/matrix-log.py` if present (both scripts); generates full pre/post Matrix task events in the playbook itself (`svc-exec.sh`)

### manage-svc.sh specific

1. **Map action → state** — `prepare→prepare`, `deploy→present`, `remove→absent`; state injected as `<service>_state` var
2. **Auto-determine sudo need** — always needs `--become` for `prepare`/`deploy`; for `remove`, checks `$DELETE_DATA` env var or inventory for `delete_data: true`
3. **Special-case `dns_service`** — forces `hosts: localhost` instead of `<service>_svc`
4. **Executes the full role** via `roles: - role: <service>` (runs `main.yml`)

### svc-exec.sh specific

1. **Default entry point** — defaults to `verify` if no entry argument given
2. **Skip safety prompt for `verify`** — read-only task, no confirmation needed
3. **Explicit `-K` flag for sudo** — user opts in; `manage-svc.sh` decides sudo need automatically
4. **Executes a task within a role** via `ansible.builtin.include_role: tasks_from: <entry>` — loads host/group vars from the role without running `main.yml`
5. **Matrix events in the generated playbook** — pre_task logs start, post_task logs completion with success/failure status (guarded by `when: matrix_access_token | length > 0`, `ignore_errors: true`)

## Issue merging

1. too much matrix code, not important
2. too much thought about sudo.  we can pretty much assume "states in main.yml" will require sudo....tasks in a role, is iffy????
3. states names can be renames to "prepare","deploy" and "remove" to take away that issue
4. checks for env vars to make the script seem sensible for me...there will not be very many.
5. dns_service is not like the others...it is forced ansible roles.  it is a tool.

## A concept

A unified script, do not remove old one.

```
svc_manage.sh [-i INVENTORY] [-h HOST] [-y] <service> [-s] <state action>  [-t] <task_within_state>  [options]
```

## Resolved design

The command argument is self-routing — no `-s`/`-t` flags needed:

- If `<command>` is `prepare`, `deploy`, or `remove` → **state mode**: generates a role playbook, always probes for sudo
- Otherwise → **task mode**: generates an `include_role: tasks_from:` playbook, sudo only if `-K`

### Interface

```
svc-manage.sh [-i INVENTORY] [-h HOST] [-y] [-K] <service> <command> [options]
```

### Sudo simplification

State commands always need `--become`. The script probes `sudo -n true` to decide
whether to ask for a password (`--become` vs `--become --ask-become-pass`).
The `DELETE_DATA` special case for `remove` is dropped — simpler, same result.

Task commands never use sudo unless `-K` is given.

### Generated playbook: state mode

```yaml
---
# Generated by svc-manage: redis deploy
- name: deploy redis
  hosts: redis_svc
  vars:
    redis_state: present
  roles:
    - role: redis
```

### Generated playbook: task mode

```yaml
---
# Generated by svc-manage: redis/verify
- name: Execute verify for redis
  hosts: redis_svc
  gather_facts: false
  tasks:
    - name: "redis/verify"
      ansible.builtin.include_role:
        name: redis
        tasks_from: verify
```

Matrix pre/post tasks are removed from the generated playbook (too much noise).
The optional `bin/matrix-log.py` shell call is kept — it is silent on failure.

### dns_service

`dns_service` is a tool, not a container service. It always targets `localhost`
regardless of `-h HOST`. It is kept in the service list but separate from the
container services.

### State → Ansible state mapping (internal)

| Command | `<service>_state` var |
|---------|----------------------|
| prepare | prepare              |
| deploy  | present              |
| remove  | absent               |
