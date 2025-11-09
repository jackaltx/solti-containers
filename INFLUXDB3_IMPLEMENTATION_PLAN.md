# InfluxDB 3 Core Implementation Plan

**Target**: Add InfluxDB 3 Core as a container service following the SOLTI pattern
**Date**: 2025-11-09
**Status**: Planning Phase

---

## Table of Contents

1. [Overview](#overview)
2. [Key Architecture Decisions](#key-architecture-decisions)
3. [InfluxDB v3 vs v2 Differences](#influxdb-v3-vs-v2-differences)
4. [Access Patterns](#access-patterns)
5. [Workflow](#workflow)
6. [Implementation Tasks](#implementation-tasks)
7. [Configuration Reference](#configuration-reference)
8. [Testing Checklist](#testing-checklist)

---

## Overview

### Purpose
Deploy InfluxDB 3 Core as a rootless Podman container following the SOLTI container pattern, with SSL termination via Traefik and token-based authentication.

### Key Technologies
- **Container**: InfluxDB 3 Core (`docker.io/influxdata/influxdb:3-core`)
- **Port**: 8181 (HTTP API)
- **Storage**: Parquet/Apache Arrow (not TSM)
- **Auth**: Token-only (no username/password)
- **SSL**: Traefik termination (transparent to container)

### Design Patterns
- Follows `_base` role inheritance
- Dynamic playbook generation (`manage-svc.sh`, `svc-exec.sh`)
- Post-deploy configuration via `initialize.yml` and `configure.yml`
- State-driven: `prepare` → `present` → `absent`

---

## Key Architecture Decisions

### 1. SSL/Access Pattern

**Three Access Methods:**

| Method | URL/Command | SSL | Use Case |
|--------|------------|-----|----------|
| **Inside Container** | `podman exec influxdb3-svc influxdb3 ...` | ❌ No | **Primary**: Initialization, configuration |
| **Host Localhost** | `http://127.0.0.1:8181` | ❌ No | **Secondary**: Verification, testing |
| **Traefik SSL** | `https://influxdb3.a0a0.org:8080` | ✅ Yes | **External**: Production access, clients |

**Critical Understanding:**
- Container always listens on plain HTTP (port 8181)
- Traefik handles SSL termination externally
- All Ansible tasks use `podman exec` with `http://localhost:8181`
- Container has NO SSL awareness/configuration

### 2. Configuration Workflow

```
manage-svc.sh influxdb3 prepare
  └─> Creates directories, sets up system

manage-svc.sh influxdb3 deploy
  ├─> prerequisites.yml (config templates)
  ├─> tls.yml (placeholder - Traefik handles it)
  ├─> quadlet_rootless.yml (start container)
  ├─> initialize.yml (create operator token)
  └─> verify.yml (health check)

svc-exec.sh influxdb3 configure
  ├─> Load operator token
  ├─> Create databases (from inventory list)
  ├─> Create resource tokens (from inventory list)
  └─> Save tokens locally

svc-exec.sh influxdb3 verify
  └─> Health checks, test data write/query
```

### 3. Token-Based Authentication (No Users!)

**InfluxDB v3 Core does NOT have user accounts**

| Concept | Implementation |
|---------|---------------|
| "Admin user" | Operator token with `--admin` flag |
| "Service users" | Named tokens with descriptions |
| "Permissions" | Token permissions (database:name:read/write) |

**Example Token Mapping:**
```yaml
# These are NOT users - they are named tokens
influxdb3_tokens:
  - description: "telegraf-writer"      # Like a "telegraf user"
    permissions: "database:telegraf:write"

  - description: "grafana-reader"       # Like a "grafana user"
    permissions: "database:*:read"

  - description: "logs-service"         # Like a "logs user"
    permissions: "database:logs:write,read"
```

### 4. Traefik Configuration

**From roles/traefik:**
- Port **8080** → HTTPS only (Let's Encrypt)
- NO HTTP entrypoint (commented out)
- Entrypoint: `websecure` on port 8080

**InfluxDB3 Traefik Labels:**
```yaml
- "Label=traefik.enable=true"
- "Label=traefik.http.routers.influxdb3.rule=Host(`influxdb3.{{ domain }}`)"
- "Label=traefik.http.routers.influxdb3.entrypoints=websecure"
- "Label=traefik.http.services.influxdb3.loadbalancer.server.port=8181"
- "Label=traefik.http.routers.influxdb3.middlewares=secHeaders@file"
```

---

## InfluxDB v3 vs v2 Differences

| Aspect | InfluxDB v2 (solti-monitoring) | InfluxDB v3 Core (solti-containers) |
|--------|-------------------------------|-------------------------------------|
| **Port** | 8086 | 8181 |
| **CLI** | `influx` | `influxdb3` |
| **Storage** | TSM engine | Parquet/Apache Arrow |
| **Auth Model** | Users + Tokens | **Tokens only** |
| **Setup Command** | `influx setup --username --password` | `influxdb3 create token --admin` |
| **Buckets/DBs** | `influx bucket create` | `influxdb3 create database` |
| **Token Creation** | `influx auth create --write-bucket` | `influxdb3 create token --permission` |
| **Config Check** | `influx config ls --json` | Check for admin token file |
| **Web UI** | Built-in (port 8086) | None (use Grafana) |
| **Permissions** | Bucket-based | Database-based with ABAC |

---

## Access Patterns

### Internal Configuration (Primary)

All initialization and configuration uses `podman exec`:

```bash
# Create operator token
podman exec influxdb3-svc influxdb3 create token --admin

# Create database
podman exec -e INFLUXDB3_AUTH_TOKEN=${TOKEN} \
  influxdb3-svc influxdb3 create database telegraf

# Query (inside container)
podman exec influxdb3-svc \
  curl -s "http://localhost:8181/health"
```

### Localhost Access (Testing)

```bash
# Health check
curl http://127.0.0.1:8181/health

# Write data (v3 API)
curl -X POST "http://127.0.0.1:8181/api/v3/write?db=telegraf" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "cpu,host=server01 usage=23.5"

# Query data (v3 API)
curl "http://127.0.0.1:8181/api/v3/query?db=telegraf&q=SELECT * FROM cpu" \
  -H "Authorization: Bearer ${TOKEN}"
```

### External Access (Production)

```bash
# Via Traefik SSL (HTTPS only on port 8080)
curl https://influxdb3.a0a0.org:8080/health

# Write via Traefik
curl -X POST "https://influxdb3.a0a0.org:8080/api/v3/write?db=telegraf" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "cpu,host=server01 usage=23.5"
```

### v1 API Compatibility

```bash
# v1 write endpoint (username ignored, password=token)
curl --user "ignored:${TOKEN}" \
  "http://127.0.0.1:8181/write?db=telegraf" \
  --data-binary "cpu,host=server01 value=23.5"

# v1 query endpoint
curl --user "ignored:${TOKEN}" \
  "http://127.0.0.1:8181/query?db=telegraf&q=SELECT * FROM cpu"
```

---

## Workflow

### 1. Preparation (One-time)

```bash
./manage-svc.sh influxdb3 prepare
```

**Actions:**
- Creates `~/influxdb3-data/` directory structure
- Sets permissions (0750 for data, 0755 for config)
- Configures SELinux contexts (RHEL)
- Sets up container network (`ct-net`)

**Directory Structure:**
```
~/influxdb3-data/
├── config/          # Environment files
├── data/            # Parquet storage
└── plugins/         # Optional plugins
```

### 2. Deployment

```bash
./manage-svc.sh influxdb3 deploy
```

**Execution Flow:**
1. `prerequisites.yml` - Template environment file
2. `tls.yml` - Placeholder (Traefik handles SSL)
3. `quadlet_rootless.yml` - Create pod/container, start service
4. `initialize.yml` - Create operator token, save to `~/.secrets/`
5. `verify.yml` - Basic health checks

**Result:**
- Container running on `127.0.0.1:8181`
- Operator token saved to `~/.secrets/influxdb3-secrets/admin-token.json`
- Service accessible via Traefik at `https://influxdb3.a0a0.org:8080`

### 3. Configuration

```bash
./svc-exec.sh influxdb3 configure
```

**Actions:**
1. Load operator token from file
2. List existing databases
3. Create databases from `influxdb3_databases` (inventory)
4. Create resource tokens from `influxdb3_tokens` (inventory)
5. Save all tokens to `./data/influxdb3-tokens-firefly.yml`

**Output File Example:**
```yaml
# ./data/influxdb3-tokens-firefly.yml
- description: telegraf-writer
  token: "influxdb3_xxxxxxxxxxxxxxxxxx"
  permissions: "database:telegraf:write"

- description: grafana-reader
  token: "influxdb3_yyyyyyyyyyyyyyyyyyyy"
  permissions: "database:*:read"
```

### 4. Verification

```bash
./svc-exec.sh influxdb3 verify
```

**Tests:**
- Pod/container status
- API health endpoint
- Create test database
- Write test data point
- Query test data
- Verify token permissions
- Clean up test database

### 5. Removal

```bash
./manage-svc.sh influxdb3 remove
```

**Actions:**
- Stop and remove containers
- Preserve data by default (`influxdb3_delete_data: false`)
- Remove quadlet files
- Optionally remove data directory (if `influxdb3_delete_data: true`)

---

## Implementation Tasks

### File Structure

```
roles/influxdb3/
├── defaults/
│   └── main.yml                    # Variables, service properties
├── tasks/
│   ├── main.yml                    # State flow (prepare/present/absent)
│   ├── prepare.yml                 # Includes _base/prepare
│   ├── prerequisites.yml           # Config templates, system setup
│   ├── tls.yml                     # Placeholder (Traefik handles it)
│   ├── quadlet_rootless.yml        # Pod + container quadlets
│   ├── initialize.yml              # Create operator token
│   ├── configure.yml               # Create databases/tokens
│   └── verify.yml                  # Health checks, tests
├── templates/
│   └── influxdb3.env.j2           # Environment variables
└── README.md                       # Usage documentation
```

### Task Breakdown

#### 1. Create Role Directory Structure
```bash
mkdir -p roles/influxdb3/{defaults,tasks,templates,handlers,meta}
```

#### 2. defaults/main.yml

Define all variables and service properties:

```yaml
---
# Installation state
influxdb3_state: present
influxdb3_force_reload: false

# Container settings
influxdb3_image: "docker.io/influxdata/influxdb:3-core"
influxdb3_port: 8181

# Directory settings
influxdb3_data_dir: "{{ ansible_user_dir }}/influxdb3-data"
influxdb3_secrets_dir: "{{ ansible_user_dir }}/.secrets/influxdb3-secrets"

# Server settings
influxdb3_node_id: "{{ inventory_hostname }}-influxdb3"
influxdb3_object_store: "file"  # file, memory, or s3

# Admin token (loaded from environment or file)
influxdb3_admin_token: "{{ lookup('env', 'INFLUXDB3_ADMIN_TOKEN', default='') }}"

# Cleanup settings
influxdb3_delete_data: false

# Traefik integration
influxdb3_enable_traefik: true

# Service properties (for _base role)
service_network: "ct-net"
service_dns_servers:
  - "1.1.1.1"
  - "8.8.8.8"
service_dns_search: "example.com"

service_properties:
  root: "influxdb3"
  name: "influxdb3-pod"
  pod_key: "influxdb3.pod"
  quadlets:
    - "influxdb3-svc.container"
    - "influxdb3.pod"
  data_dir: "{{ influxdb3_data_dir }}"
  config_dir: "config"
  dirs:
    - { path: "", mode: "0750" }
    - { path: "config", mode: "0755" }
    - { path: "data", mode: "0750" }
    - { path: "plugins", mode: "0755" }
```

#### 3. tasks/main.yml

State-driven entry point:

```yaml
---
# Validate state
- name: Validate state parameter
  ansible.builtin.fail:
    msg: "influxdb3_state must be one of: prepare, present, absent. Current value: {{ influxdb3_state }}"
  when: influxdb3_state not in ['prepare', 'present', 'absent']

- name: Test become capability
  ansible.builtin.command: whoami
  register: become_test
  changed_when: false

# PREPARATION
- name: Prepare InfluxDB3 (one-time setup)
  when: influxdb3_state == 'prepare'
  block:
    - name: Check if already prepared
      ansible.builtin.stat:
        path: "{{ influxdb3_data_dir }}"
      register: data_dir_check

    - name: Fail if already prepared
      ansible.builtin.fail:
        msg: "InfluxDB3 appears to be already prepared. Directory {{ influxdb3_data_dir }} exists."
      when: data_dir_check.stat.exists

    - name: Base prepare
      ansible.builtin.include_tasks:
        file: ../_base/tasks/prepare.yml

# DEPLOYMENT
- name: Install InfluxDB3
  when: influxdb3_state == 'present'
  block:
    - name: Verify required directories exist
      become: true
      ansible.builtin.stat:
        path: "{{ influxdb3_data_dir }}/{{ service_properties.config_dir }}"
      register: config_dir_check
      failed_when: not config_dir_check.stat.exists
      changed_when: false

    - name: Include prerequisites tasks
      ansible.builtin.include_tasks: prerequisites.yml

    - name: Include TLS tasks
      ansible.builtin.include_tasks: tls.yml
      when: influxdb3_enable_traefik | bool

    - name: Ensure network setup
      ansible.builtin.include_tasks:
        file: "../_base/tasks/networks.yml"

    - name: Include container tasks
      ansible.builtin.include_tasks: quadlet_rootless.yml

    - name: Initialize InfluxDB3
      ansible.builtin.include_tasks: initialize.yml

    - name: Verify deployment
      ansible.builtin.include_tasks: verify.yml

# CLEANUP
- name: Remove InfluxDB3
  when: influxdb3_state == 'absent'
  block:
    - name: Include cleanup tasks
      ansible.builtin.include_tasks:
        file: "../_base/tasks/cleanup.yml"
      vars:
        service_state: absent
        service_delete_data: "{{ influxdb3_delete_data }}"
```

#### 4. tasks/prerequisites.yml

```yaml
---
# Verify variables
- name: Verify prerequisite variables
  assert:
    that:
      - influxdb3_data_dir is defined
      - influxdb3_port is defined
      - influxdb3_node_id is defined
    fail_msg: "Required variables not properly configured"

# Get container user mapping
- name: Get directory ownership
  ansible.builtin.stat:
    path: "{{ influxdb3_data_dir }}/config"
  register: dir_info

# Template environment file
- name: Template InfluxDB3 environment file
  become: true
  ansible.builtin.template:
    src: influxdb3.env.j2
    dest: "{{ influxdb3_data_dir }}/config/influxdb3.env"
    mode: "0644"
    owner: "{{ dir_info.stat.uid }}"
    group: "{{ dir_info.stat.gid }}"

# SELinux configuration
- name: Configure SELinux for data directories
  when: ansible_os_family == "RedHat" and ansible_selinux.status == "enabled"
  become: true
  block:
    - name: Set SELinux context for InfluxDB3 directories
      ansible.builtin.sefcontext:
        target: "{{ influxdb3_data_dir }}(/.*)?"
        setype: container_file_t
        state: present

    - name: Apply SELinux context
      ansible.builtin.command: restorecon -R -v "{{ influxdb3_data_dir }}"
      register: restorecon_result
      changed_when: restorecon_result.rc == 0
```

#### 5. tasks/tls.yml

```yaml
---
# TLS is handled by Traefik proxy
- name: TLS configuration
  ansible.builtin.debug:
    msg: "TLS is handled by Traefik proxy - container uses plain HTTP"
```

#### 6. tasks/quadlet_rootless.yml

```yaml
---
# Create pod
- name: Create InfluxDB3 pod Quadlet
  containers.podman.podman_pod:
    name: influxdb3
    state: quadlet
    dns: "{{ service_dns_servers }}"
    dns_search: "{{ service_dns_search }}"
    network: "{{ service_network }}"
    quadlet_dir: "{{ ansible_env.HOME }}/.config/containers/systemd"
    ports:
      - "127.0.0.1:{{ influxdb3_port }}:8181"
    quadlet_options:
      - |
        [Service]
        Restart=always
      - |
        [Install]
        WantedBy=default.target

# Create container
- name: Create InfluxDB3 server container Quadlet
  containers.podman.podman_container:
    name: influxdb3-svc
    pod: influxdb3.pod
    image: "{{ influxdb3_image }}"
    state: quadlet
    quadlet_dir: "{{ ansible_env.HOME }}/.config/containers/systemd"
    volume:
      - "{{ influxdb3_data_dir }}/data:/var/lib/influxdb3/data:Z"
      - "{{ influxdb3_data_dir }}/plugins:/var/lib/influxdb3/plugins:Z"
    env:
      INFLUXDB3_NODE_IDENTIFIER_PREFIX: "{{ influxdb3_node_id }}"
    command:
      - "serve"
      - "--http-bind=0.0.0.0:8181"
      - "--object-store={{ influxdb3_object_store }}"
      - "--data-dir=/var/lib/influxdb3/data"
    quadlet_options:
      # Traefik labels (if enabled)
      - "Label=traefik.enable={{ influxdb3_enable_traefik | lower }}"
      - "Label=traefik.http.routers.influxdb3.rule=Host(`influxdb3.{{ domain }}`)"
      - "Label=traefik.http.routers.influxdb3.entrypoints=websecure"
      - "Label=traefik.http.services.influxdb3.loadbalancer.server.port=8181"
      - "Label=traefik.http.routers.influxdb3.middlewares=secHeaders@file"
      - |
        [Unit]
        Description=InfluxDB 3 Core Container
        After=network-online.target
      - |
        [Service]
        Restart=always
        TimeoutStartSec=300
        TimeoutStopSec=70
      - |
        [Install]
        WantedBy=default.target

# Reload systemd
- name: Reload systemd user daemon
  ansible.builtin.systemd:
    daemon_reload: yes
    scope: user

# Start service
- name: Enable and start rootless pod with systemd
  ansible.builtin.systemd:
    name: "{{ service_properties.name }}"
    state: started
    enabled: yes
    scope: user

# Wait for service
- name: Wait for InfluxDB3 to be ready
  ansible.builtin.wait_for:
    host: 127.0.0.1
    port: "{{ influxdb3_port }}"
    timeout: 120
```

#### 7. tasks/initialize.yml

```yaml
---
# Create secrets directory
- name: Ensure secrets directory exists
  ansible.builtin.file:
    path: "{{ influxdb3_secrets_dir }}"
    state: directory
    mode: "0700"

# Check if already initialized
- name: Check if admin token exists
  ansible.builtin.stat:
    path: "{{ influxdb3_secrets_dir }}/admin-token.json"
  register: admin_token_file

# Create operator token
- name: Create operator (admin) token
  when: not admin_token_file.stat.exists
  block:
    - name: Generate operator token
      ansible.builtin.command:
        cmd: podman exec influxdb3-svc influxdb3 create token --admin --json
      register: token_result
      no_log: true
      changed_when: true

    - name: Save admin token securely
      ansible.builtin.copy:
        content: "{{ token_result.stdout }}"
        dest: "{{ influxdb3_secrets_dir }}/admin-token.json"
        mode: "0600"

    - name: Parse token
      ansible.builtin.set_fact:
        influxdb3_admin_token: "{{ (token_result.stdout | from_json).token }}"
      no_log: true

    - name: Display initialization status
      ansible.builtin.debug:
        msg:
          - "=============================================================="
          - "InfluxDB3 initialized successfully!"
          - "Operator token saved to: {{ influxdb3_secrets_dir }}/admin-token.json"
          - "IMPORTANT: Store this token securely - it cannot be retrieved later"
          - "=============================================================="

# Load existing token
- name: Load existing admin token
  when: admin_token_file.stat.exists
  block:
    - name: Read existing token file
      ansible.builtin.slurp:
        src: "{{ influxdb3_secrets_dir }}/admin-token.json"
      register: encoded_token

    - name: Parse existing token
      ansible.builtin.set_fact:
        influxdb3_admin_token: "{{ (encoded_token.content | b64decode | from_json).token }}"
      no_log: true

    - name: Display status
      ansible.builtin.debug:
        msg: "InfluxDB3 already initialized - using existing operator token"
```

#### 8. tasks/configure.yml

```yaml
---
# Load admin token
- name: Check if admin token exists
  ansible.builtin.stat:
    path: "{{ influxdb3_secrets_dir }}/admin-token.json"
  register: admin_token_file

- name: Fail if admin token doesn't exist
  ansible.builtin.fail:
    msg: "Admin token not found. Please run initialize first."
  when: not admin_token_file.stat.exists

- name: Load admin token
  ansible.builtin.slurp:
    src: "{{ influxdb3_secrets_dir }}/admin-token.json"
  register: encoded_token

- name: Parse admin token
  ansible.builtin.set_fact:
    admin_token: "{{ (encoded_token.content | b64decode | from_json).token }}"
  no_log: true

# List existing databases
- name: List existing databases
  ansible.builtin.command:
    cmd: >
      podman exec
      -e INFLUXDB3_AUTH_TOKEN={{ admin_token }}
      influxdb3-svc influxdb3 query "SHOW DATABASES"
  register: db_list
  changed_when: false
  failed_when: false

# Create databases
- name: Create databases
  ansible.builtin.command:
    cmd: >
      podman exec
      -e INFLUXDB3_AUTH_TOKEN={{ admin_token }}
      influxdb3-svc influxdb3 create database {{ item.name }}
  loop: "{{ influxdb3_databases | default([]) }}"
  when: item.name not in (db_list.stdout | default(''))
  register: db_create
  changed_when: db_create.rc == 0
  failed_when:
    - db_create.rc != 0
    - "'already exists' not in db_create.stderr"

# Create resource tokens
- name: Create resource tokens
  ansible.builtin.command:
    cmd: >
      podman exec
      -e INFLUXDB3_AUTH_TOKEN={{ admin_token }}
      influxdb3-svc influxdb3 create token
      --description {{ item.description }}
      --permission {{ item.permissions }}
      --json
  loop: "{{ influxdb3_tokens | default([]) }}"
  register: token_results
  no_log: true
  changed_when: token_results.rc == 0
  failed_when:
    - token_results.rc != 0
    - "'already exists' not in token_results.stderr"

# Save tokens locally
- name: Save tokens to local file
  ansible.builtin.copy:
    content: |
      # InfluxDB 3 Core Tokens
      # Generated: {{ ansible_date_time.iso8601 }}
      # Host: {{ ansible_hostname }}

      {% for result in token_results.results %}
      {% if result.stdout is defined and result.stdout != '' %}
      {% set token_data = result.stdout | from_json %}
      - description: {{ token_data.description }}
        token: {{ token_data.token }}
        permissions: {{ item.permissions }}
      {% endif %}
      {% endfor %}
    dest: "./data/influxdb3-tokens-{{ ansible_hostname }}.yml"
    mode: "0600"
  delegate_to: localhost
  when: token_results.results | length > 0

- name: Display configuration summary
  ansible.builtin.debug:
    msg:
      - "=============================================================="
      - "InfluxDB3 configuration complete!"
      - "Databases created: {{ influxdb3_databases | default([]) | length }}"
      - "Tokens created: {{ influxdb3_tokens | default([]) | length }}"
      - "Tokens saved to: ./data/influxdb3-tokens-{{ ansible_hostname }}.yml"
      - "=============================================================="
```

#### 9. tasks/verify.yml

```yaml
---
# Verify pod is running
- name: Verify InfluxDB3 pod is running
  ansible.builtin.command: podman pod ps --format "{{.Name}}"
  register: pod_status
  failed_when: "'influxdb3' not in pod_status.stdout"
  changed_when: false

# Verify container is running
- name: Verify InfluxDB3 container is running
  ansible.builtin.command: podman ps --format "{{.Names}}" --filter "pod=influxdb3"
  register: container_status
  changed_when: false

- name: Show container status
  ansible.builtin.debug:
    var: container_status.stdout_lines

# Wait for API to be ready
- name: Wait for InfluxDB3 to be ready
  ansible.builtin.command:
    cmd: podman exec influxdb3-svc curl -s http://localhost:8181/health
  register: health_check
  until: health_check.rc == 0
  retries: 30
  delay: 5
  changed_when: false

- name: Show health status
  ansible.builtin.debug:
    var: health_check.stdout

# Load admin token for tests
- name: Load admin token for verification
  block:
    - name: Read admin token file
      ansible.builtin.slurp:
        src: "{{ influxdb3_secrets_dir }}/admin-token.json"
      register: encoded_token

    - name: Parse admin token
      ansible.builtin.set_fact:
        verify_token: "{{ (encoded_token.content | b64decode | from_json).token }}"
      no_log: true
  when: influxdb3_admin_token == ''

- name: Use provided admin token
  ansible.builtin.set_fact:
    verify_token: "{{ influxdb3_admin_token }}"
  when: influxdb3_admin_token != ''

# Create test database
- name: Create test database
  ansible.builtin.command:
    cmd: >
      podman exec
      -e INFLUXDB3_AUTH_TOKEN={{ verify_token }}
      influxdb3-svc influxdb3 create database test-ansible
  register: test_db
  changed_when: test_db.rc == 0
  failed_when:
    - test_db.rc != 0
    - "'already exists' not in test_db.stderr"

# Write test data
- name: Write test data point
  ansible.builtin.command:
    cmd: >
      podman exec influxdb3-svc
      curl -s -X POST "http://localhost:8181/api/v3/write?db=test-ansible"
      -H "Authorization: Bearer {{ verify_token }}"
      --data-binary "test_measurement,host={{ ansible_hostname }} value=123,status=\"ok\" {{ ansible_date_time.epoch }}000000000"
  register: write_result
  changed_when: false
  no_log: true

- name: Show write result
  ansible.builtin.debug:
    msg: "Test data written successfully"
  when: write_result.rc == 0

# Query test data
- name: Query test data
  ansible.builtin.command:
    cmd: >
      podman exec influxdb3-svc
      curl -s "http://localhost:8181/api/v3/query?db=test-ansible&q=SELECT%20*%20FROM%20test_measurement"
      -H "Authorization: Bearer {{ verify_token }}"
  register: query_result
  changed_when: false
  no_log: true

- name: Show query result
  ansible.builtin.debug:
    var: query_result.stdout_lines

# Cleanup test database
- name: Delete test database
  ansible.builtin.command:
    cmd: >
      podman exec
      -e INFLUXDB3_AUTH_TOKEN={{ verify_token }}
      influxdb3-svc influxdb3 delete database test-ansible
  changed_when: false
  failed_when: false

- name: Display verification summary
  ansible.builtin.debug:
    msg:
      - "=============================================================="
      - "InfluxDB3 verification complete!"
      - "✓ Pod running"
      - "✓ Container running"
      - "✓ API responding"
      - "✓ Database operations working"
      - "✓ Write operations working"
      - "✓ Query operations working"
      - "=============================================================="
```

#### 10. templates/influxdb3.env.j2

```bash
# InfluxDB 3 Core Environment Variables
# Generated by Ansible on {{ ansible_date_time.iso8601 }}

# Node identification
INFLUXDB3_NODE_IDENTIFIER_PREFIX={{ influxdb3_node_id }}

# Object store configuration
INFLUXDB3_OBJECT_STORE={{ influxdb3_object_store }}

# Data directory
INFLUXDB3_DATA_DIR=/var/lib/influxdb3/data

# HTTP binding
INFLUXDB3_HTTP_BIND=0.0.0.0:8181

# Optional: AWS credentials (if using S3)
{% if influxdb3_object_store == 's3' %}
AWS_ACCESS_KEY_ID={{ lookup('env', 'AWS_ACCESS_KEY_ID') }}
AWS_SECRET_ACCESS_KEY={{ lookup('env', 'AWS_SECRET_ACCESS_KEY') }}
{% endif %}
```

#### 11. inventory.yml Configuration

Add to `inventory.yml`:

```yaml
influxdb3_svc:
  hosts:
    firefly:

  vars:
    debug_level: warn
    influxdb3_data_dir: "{{ ansible_env.HOME }}/influxdb3-data"
    influxdb3_port: 8181
    influxdb3_delete_data: false

    # Secrets directory
    influxdb3_secrets_dir: "{{ ansible_env.HOME }}/.secrets/influxdb3-secrets"

    # Admin token (loaded from environment or file)
    influxdb3_admin_token: "{{ lookup('env', 'INFLUXDB3_ADMIN_TOKEN', default='') }}"

    # Databases to create during configure
    influxdb3_databases:
      - name: "telegraf"
      - name: "metrics"
      - name: "logs"
      - name: "traces"

    # Resource tokens to create during configure
    influxdb3_tokens:
      - description: "telegraf-writer"
        permissions: "database:telegraf:write"
      - description: "metrics-reader"
        permissions: "database:metrics:read"
      - description: "grafana-reader"
        permissions: "database:*:read"
      - description: "logs-writer"
        permissions: "database:logs:write,read"

    # Traefik integration
    influxdb3_enable_traefik: true

    service_properties:
      root: "influxdb3"
      name: "influxdb3-pod"
      pod_key: "influxdb3.pod"
      quadlets:
        - "influxdb3-svc.container"
        - "influxdb3.pod"
      data_dir: "{{ influxdb3_data_dir }}"
      config_dir: "config"
      dirs:
        - { path: "", mode: "0750" }
        - { path: "config", mode: "0755" }
        - { path: "data", mode: "0750" }
        - { path: "plugins", mode: "0755" }
```

#### 12. Update manage-svc.sh

Add to `SUPPORTED_SERVICES` array (line 24):

```bash
SUPPORTED_SERVICES=(
    "elasticsearch"
    "hashivault"
    "redis"
    "mattermost"
    "traefik"
    "minio"
    "wazuh"
    "grafana"
    "gitea"
    "influxdb3"  # ADD THIS LINE
)
```

#### 13. Update svc-exec.sh

Add to `SUPPORTED_SERVICES` array (line 24):

```bash
SUPPORTED_SERVICES=(
    "elasticsearch"
    "hashivault"
    "redis"
    "mattermost"
    "traefik"
    "minio"
    "wazuh"
    "grafana"
    "gitea"
    "influxdb3"  # ADD THIS LINE
)
```

#### 14. README.md

Create `roles/influxdb3/README.md` with:
- Service overview
- Quick start guide
- Configuration examples
- Troubleshooting tips
- Token management workflow
- SSL/Traefik integration notes

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INFLUXDB3_AUTH_TOKEN` | - | Operator token for CLI commands |
| `INFLUXDB3_NODE_IDENTIFIER_PREFIX` | `{{ inventory_hostname }}-influxdb3` | Node identifier |
| `INFLUXDB3_OBJECT_STORE` | `file` | Storage backend (file/memory/s3) |
| `INFLUXDB3_DATA_DIR` | `/var/lib/influxdb3/data` | Data directory |
| `INFLUXDB3_HTTP_BIND` | `0.0.0.0:8181` | HTTP API binding |

### Inventory Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `influxdb3_state` | `present` | Service state (prepare/present/absent) |
| `influxdb3_image` | `docker.io/influxdata/influxdb:3-core` | Container image |
| `influxdb3_port` | `8181` | API port |
| `influxdb3_data_dir` | `~/influxdb3-data` | Host data directory |
| `influxdb3_secrets_dir` | `~/.secrets/influxdb3-secrets` | Token storage |
| `influxdb3_delete_data` | `false` | Delete data on removal |
| `influxdb3_databases` | `[]` | List of databases to create |
| `influxdb3_tokens` | `[]` | List of tokens to create |
| `influxdb3_enable_traefik` | `true` | Enable Traefik integration |

### Token Permissions Format

```
database:DATABASE_NAME:ACTIONS
```

**Examples:**
- `database:telegraf:write` - Write-only to telegraf database
- `database:metrics:read` - Read-only to metrics database
- `database:logs:write,read` - Read/write to logs database
- `database:*:read` - Read-only to ALL databases

---

## Testing Checklist

### Preparation Phase
- [ ] `./manage-svc.sh influxdb3 prepare` succeeds
- [ ] Directory `~/influxdb3-data` created with correct structure
- [ ] Subdirectories have correct permissions (750/755)
- [ ] SELinux contexts applied (RHEL systems)

### Deployment Phase
- [ ] `./manage-svc.sh influxdb3 deploy` succeeds
- [ ] Container `influxdb3-svc` is running
- [ ] Pod `influxdb3` is running
- [ ] Port `127.0.0.1:8181` is listening
- [ ] Operator token created in `~/.secrets/influxdb3-secrets/admin-token.json`
- [ ] Health check responds: `curl http://127.0.0.1:8181/health`

### Configuration Phase
- [ ] `./svc-exec.sh influxdb3 configure` succeeds
- [ ] All databases from inventory created
- [ ] All resource tokens created
- [ ] Tokens saved to `./data/influxdb3-tokens-firefly.yml`

### Verification Phase
- [ ] `./svc-exec.sh influxdb3 verify` succeeds
- [ ] Test database created
- [ ] Test data written successfully
- [ ] Test data queried successfully
- [ ] Test database cleaned up

### Traefik Integration
- [ ] Traefik labels applied to container
- [ ] Service registered in Traefik dashboard
- [ ] HTTPS access works: `https://influxdb3.a0a0.org:8080/health`
- [ ] SSL certificate issued by Let's Encrypt

### Removal Phase
- [ ] `./manage-svc.sh influxdb3 remove` succeeds
- [ ] Container stopped and removed
- [ ] Pod removed
- [ ] Data preserved (if `influxdb3_delete_data: false`)
- [ ] Data removed (if `influxdb3_delete_data: true`)

### Edge Cases
- [ ] Re-running `initialize` doesn't create duplicate tokens
- [ ] Re-running `configure` is idempotent (doesn't fail on existing databases)
- [ ] Service survives host reboot (systemd auto-start)
- [ ] Logs accessible: `journalctl --user -u influxdb3-pod`

---

## Questions/Decisions Needed

1. **Object Store**: Default to `file` or support `s3` from the start?
2. **Token Expiration**: Should we set expiration on resource tokens?
3. **Backup Strategy**: Should we add a `backup.yml` task?
4. **Monitoring**: Should we add Prometheus metrics exposure?
5. **Version Pinning**: Use `influxdb:3-core` (latest) or pin to specific version?

---

## References

- [InfluxDB 3 Core Documentation](https://docs.influxdata.com/influxdb3/core/)
- [InfluxDB 3 Core CLI Reference](https://docs.influxdata.com/influxdb3/core/reference/cli/influxdb3/)
- [InfluxDB 3 Core Token Management](https://docs.influxdata.com/influxdb3/core/admin/tokens/)
- [SOLTI Container Pattern](docs/Solti-Container-Pattern.md)
- [Container Role Architecture](Container-Role-Architecture.md)

---

**Plan Status**: Ready for review and implementation
