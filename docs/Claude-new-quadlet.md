# Creating New Quadlet Roles - MongoDB Reference Implementation

## Overview

This guide documents the complete process of creating a new quadlet role for the SOLTI containers collection, using the MongoDB implementation as a working reference. Follow these patterns to create consistent, production-ready container services.

## Prerequisites

- Understanding of Podman quadlets and systemd integration
- Familiarity with the SOLTI pattern (_base role inheritance)
- Access to `manage-svc.sh` and `svc-exec.sh` workflows
- For Traefik SSL: LINODE_TOKEN for DNS management

## Phase 1: Role Structure

### Directory Tree

```text
roles/<service>/
├── defaults/
│   └── main.yml          # Service properties and defaults
├── tasks/
│   ├── main.yml          # Entry point with state-based flow
│   ├── prerequisites.yml # Config file generation and validation
│   ├── quadlet_rootless.yml # Container/pod deployment
│   └── verify.yml        # Health checks and functional tests
├── templates/
│   ├── <service>.env.j2  # Environment file for credentials (mode 0600)
│   └── <service>.conf.j2 # Service configuration file
├── handlers/
│   └── main.yml          # Service restart handlers
└── README.md             # User documentation
```

## Phase 2: Service Properties (defaults/main.yml)

### Pattern: Define Everything Up Front

```yaml
---
# Service-specific variables
mongodb_image: "docker.io/library/mongo:7.0"
mongodb_express_image: "docker.io/library/mongo-express:latest"
mongodb_data_dir: "{{ lookup('env', 'HOME') }}/mongodb-data"
mongodb_port: 27017
mongodb_gui_port: 8081

# Credentials from environment with defaults
mongodb_root_username: "{{ lookup('env', 'MONGODB_ROOT_USERNAME', default='admin') }}"
mongodb_root_password: "{{ lookup('env', 'MONGODB_ROOT_PASSWORD', default='changeme') }}"
mongodb_database: "{{ lookup('env', 'MONGODB_DATABASE', default='admin') }}"

# Feature flags
mongodb_enable_gui: true
mongodb_enable_traefik: false

# Service properties - used by _base role
service_properties:
  root: "mongodb"
  name: "mongodb-pod.service"
  pod_key: "mongodb.pod"
  quadlets:
    - "mongodb-svc.container"
    - "mongodb-gui.container"
    - "mongodb.pod"
  data_dir: "{{ mongodb_data_dir }}"
  config_dir: "config"
  delete_data: "{{ lookup('env', 'DELETE_DATA') | default(false) | bool }}"
  delete_images: "{{ lookup('env', 'DELETE_IMAGES') | default(false) | bool }}"
  container_images:
    - "{{ mongodb_image }}"
    - "{{ mongodb_express_image }}"
  dirs:
    - {path: "", mode: "0750"}
    - {path: "config", mode: "0755"}
    - {path: "data", mode: "0750"}
    - {path: "logs", mode: "0755"}
  ports:
    - "127.0.0.1:{{ mongodb_port }}:27017"
    - "127.0.0.1:{{ mongodb_gui_port }}:8081"
  volumes:
    - "{{ mongodb_data_dir }}/config:/data/configdb:Z"
    - "{{ mongodb_data_dir }}/data:/data/db:Z"
    - "{{ mongodb_data_dir }}/logs:/var/log/mongodb:Z"

# State management
mongodb_state: present
```

### Key Concepts

**Environment Variable Pattern:**
```yaml
variable_name: "{{ lookup('env', 'ENV_VAR_NAME', default='fallback') }}"
```

**Service Properties Structure:**
- `root`: Service identifier (used in paths, naming)
- `name`: Systemd service name (`<service>-pod.service`)
- `pod_key`: Pod quadlet reference (`<service>.pod`)
- `quadlets`: List of all quadlet files to manage
- `dirs`: Directory structure to create (path relative to data_dir)
- `ports`: Port mappings (always bind to `127.0.0.1` for security)
- `volumes`: Volume mounts with SELinux context (`:Z`)
- `container_images`: List of images for cleanup

## Phase 3: Task Files

### tasks/main.yml - State-Based Entry Point

```yaml
---
- name: Validate state parameter
  ansible.builtin.fail:
    msg: "mongodb_state must be one of: prepare, present, absent"
  when: mongodb_state not in ['prepare', 'present', 'absent']

# Get real user info (immune to become)
- name: Get real user info from environment
  ansible.builtin.set_fact:
    real_user: "{{ lookup('env', 'USER') }}"
    real_user_dir: "{{ lookup('env', 'HOME') }}"
    real_user_uid: "{{ lookup('pipe', 'id -u') }}"

# Prepare block - one-time setup
- name: Prepare MongoDB (one-time setup)
  when: mongodb_state == 'prepare'
  block:
    - name: Include base preparation tasks
      ansible.builtin.include_tasks: ../_base/tasks/prepare.yml

# Install block - deploy and start service
- name: Install MongoDB
  when: mongodb_state == 'present'
  block:
    - name: Include prerequisites
      ansible.builtin.include_tasks: prerequisites.yml

    - name: Include network setup
      ansible.builtin.include_tasks: ../_base/tasks/networks.yml

    - name: Include quadlet deployment
      ansible.builtin.include_tasks: quadlet_rootless.yml

    - name: Include verification tasks
      ansible.builtin.include_tasks: verify.yml
      when: mongodb_verify | default(true)

# Remove block - stop and remove service
- name: Remove MongoDB
  when: mongodb_state == 'absent'
  block:
    - name: Include cleanup tasks
      ansible.builtin.include_tasks: ../_base/tasks/cleanup.yml
```

### tasks/prerequisites.yml - Configuration Generation

```yaml
---
- name: Verify MongoDB credentials are set
  ansible.builtin.assert:
    that:
      - mongodb_root_password != "changeme"
      - mongodb_root_password != ""
      - mongodb_root_username != ""
    fail_msg: "MongoDB credentials must be set via environment variables"

- name: Get directory info for ownership
  ansible.builtin.stat:
    path: "{{ mongodb_data_dir }}"
  register: dir_info

- name: Create environment file directory
  ansible.builtin.file:
    path: "{{ real_user_dir }}/.config/containers/systemd/env"
    state: directory
    mode: "0700"
    owner: "{{ real_user }}"
    group: "{{ real_user }}"

- name: Create environment file for MongoDB credentials
  ansible.builtin.template:
    src: mongodb.env.j2
    dest: "{{ real_user_dir }}/.config/containers/systemd/env/mongodb.env"
    mode: "0600"  # CRITICAL: Restrict credential access
    owner: "{{ real_user }}"
    group: "{{ real_user }}"

- name: Create MongoDB configuration file
  ansible.builtin.template:
    src: mongod.conf.j2
    dest: "{{ mongodb_data_dir }}/config/mongod.conf"
    mode: "0644"
    owner: "{{ dir_info.stat.uid }}"
    group: "{{ dir_info.stat.gid }}"
```

### tasks/quadlet_rootless.yml - Container Deployment

```yaml
---
# Step 1: Create pod quadlet
- name: Create MongoDB pod Quadlet
  become: false
  containers.podman.podman_pod:
    name: mongodb
    state: quadlet  # KEY: Creates systemd unit, doesn't start
    dns: "{{ service_dns_servers }}"
    dns_search: "{{ service_dns_search }}"
    network: "{{ service_network }}"
    quadlet_dir: "{{ real_user_dir }}/.config/containers/systemd"
    ports:
      - "127.0.0.1:{{ mongodb_port }}:27017"
      - "127.0.0.1:{{ mongodb_gui_port }}:8081"
    quadlet_options:
      - |
        [Service]
        Restart=always
      - |
        [Install]
        WantedBy=default.target

# Step 2: Create main service container
- name: Create MongoDB server container Quadlet
  become: false
  containers.podman.podman_container:
    name: mongodb-svc
    pod: mongodb.pod  # Reference to pod
    image: "{{ mongodb_image }}"
    state: quadlet
    quadlet_dir: "{{ real_user_dir }}/.config/containers/systemd"
    volume:
      - "{{ mongodb_data_dir }}/config:/data/configdb:Z"
      - "{{ mongodb_data_dir }}/data:/data/db:Z"
    command:
      - "mongod"
      - "--config"
      - "/data/configdb/mongod.conf"
    quadlet_options:
      - "EnvironmentFile={{ real_user_dir }}/.config/containers/systemd/env/mongodb.env"
      - |
        [Unit]
        Description=MongoDB Server Container
        After=network-online.target
      - |
        [Service]
        Restart=always
        TimeoutStartSec=300
        TimeoutStopSec=70

# Step 3: Create GUI container (conditional)
- name: Create Mongo Express GUI container Quadlet
  when: mongodb_enable_gui | bool
  become: false
  containers.podman.podman_container:
    name: mongodb-gui
    pod: mongodb.pod
    image: "{{ mongodb_express_image }}"
    state: quadlet
    quadlet_dir: "{{ real_user_dir }}/.config/containers/systemd"
    env:
      ME_CONFIG_MONGODB_ADMINUSERNAME: "{{ mongodb_root_username }}"
      ME_CONFIG_MONGODB_ADMINPASSWORD: "{{ mongodb_root_password }}"
      ME_CONFIG_MONGODB_URL: "mongodb://{{ mongodb_root_username }}:{{ mongodb_root_password }}@mongodb-svc:27017/"
      ME_CONFIG_BASICAUTH: "false"
    label:
      traefik.enable: "{{ mongodb_enable_traefik | lower }}"
      traefik.http.routers.mongodb.rule: "Host(`{{ mongodb_svc_name | default('mongodb') }}.{{ domain }}`)"
      traefik.http.services.mongodb.loadbalancer.server.port: "8081"
    quadlet_options:
      - |
        [Unit]
        Description=Mongo Express Web Interface
        After=mongodb-svc.service
      - |
        [Service]
        Restart=always

# Step 4: Reload systemd and start
- name: Reload systemd user daemon
  ansible.builtin.shell: |
    export XDG_RUNTIME_DIR=/run/user/{{ real_user_uid }}
    systemctl --user daemon-reload
  become: false
  changed_when: false

- name: Start rootless pod with systemd
  ansible.builtin.shell: |
    export XDG_RUNTIME_DIR=/run/user/{{ real_user_uid }}
    systemctl --user start {{ service_properties.name }}
  become: false
  changed_when: true
```

### tasks/verify.yml - Health Checks

```yaml
---
# IMPORTANT: Use {%raw%}{{.Name}}{%endraw%} to avoid Jinja2 conflicts
- name: Verify MongoDB pod is running
  ansible.builtin.command: podman pod ps --format "{%raw%}{{.Name}}{%endraw%}"
  register: pod_status
  failed_when: "'mongodb' not in pod_status.stdout"
  changed_when: false

- name: Verify MongoDB container is running
  ansible.builtin.command: podman ps --format "{%raw%}{{.Names}}{%endraw%}" --filter "pod=mongodb"
  register: container_status
  changed_when: false

- name: Display running containers
  ansible.builtin.debug:
    msg: "Running containers: {{ container_status.stdout_lines }}"

- name: Wait for MongoDB to be ready
  ansible.builtin.wait_for:
    host: 127.0.0.1
    port: "{{ mongodb_port }}"
    state: started
    delay: 5
    timeout: 60

- name: Test MongoDB connection
  ansible.builtin.command: >
    podman exec mongodb-svc
    mongosh -u {{ mongodb_root_username }} -p {{ mongodb_root_password }} --authenticationDatabase admin
    --quiet --eval "db.adminCommand('ping')"
  register: mongo_ping
  changed_when: false
  retries: 5
  delay: 3
  until: mongo_ping.rc == 0
  no_log: true  # Hide credentials in logs

- name: Test MongoDB write operation
  ansible.builtin.command: >
    podman exec mongodb-svc
    mongosh -u {{ mongodb_root_username }} -p {{ mongodb_root_password }} --authenticationDatabase admin
    --quiet --eval "db.{{ test_collection | default('test') }}.insertOne({test: 'verification', timestamp: new Date()})"
  register: mongo_write
  changed_when: false
  no_log: true

- name: Get MongoDB version
  ansible.builtin.command: >
    podman exec mongodb-svc
    mongosh -u {{ mongodb_root_username }} -p {{ mongodb_root_password }} --authenticationDatabase admin
    --quiet --eval "db.version()"
  register: mongo_version
  changed_when: false
  no_log: true

- name: Display MongoDB version
  ansible.builtin.debug:
    msg: "MongoDB version: {{ mongo_version.stdout }}"

- name: Verify Mongo Express GUI (if enabled)
  when: mongodb_enable_gui | bool
  block:
    - name: Check Mongo Express is running
      ansible.builtin.uri:
        url: "http://127.0.0.1:{{ mongodb_gui_port }}"
        method: GET
        status_code: 200
      register: gui_check
      retries: 5
      delay: 3
      until: gui_check.status == 200
```

## Phase 4: Templates

### templates/mongodb.env.j2 - Credentials File

```bash
# MongoDB environment variables for initialization
# This file contains sensitive credentials - mode: 0600

MONGO_INITDB_ROOT_USERNAME={{ mongodb_root_username }}
MONGO_INITDB_ROOT_PASSWORD={{ mongodb_root_password }}
MONGO_INITDB_DATABASE={{ mongodb_database }}
```

**Security Notes:**
- File mode must be `0600` (owner read/write only)
- No shell expansion needed (Podman reads directly)
- One variable per line

### templates/mongod.conf.j2 - Service Configuration

```yaml
# MongoDB configuration file
# Generated by Ansible for {{ ansible_managed | default('solti-containers') }}

# Network settings
net:
  port: 27017
  bindIp: 0.0.0.0

# Storage settings
storage:
  dbPath: /data/db

# Security settings
security:
  authorization: enabled

# Logging disabled (MongoDB will log to stdout/stderr by default)
# systemLog captured by podman/systemd

# Process management
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
```

**MongoDB 7.0 Breaking Changes:**
- ❌ Removed: `storage.journal.enabled` (deprecated)
- ❌ Removed: File-based logging (permission issues in containers)
- ✅ Use: stdout/stderr logging (captured by systemd)

## Phase 5: Handlers

### handlers/main.yml

```yaml
---
- name: Restart mongodb
  ansible.builtin.systemd:
    name: "{{ service_properties.name }}"
    state: restarted
    scope: user
  listen: "restart mongodb"
  become: false
```

## Phase 6: Integration with Management Scripts

### Update manage-svc.sh

```bash
# Add to SUPPORTED_SERVICES array
SUPPORTED_SERVICES=(
    "elasticsearch"
    "hashivault"
    "redis"
    # ... existing services ...
    "mongodb"  # ADD THIS
)
```

### Update svc-exec.sh

```bash
# Add to SUPPORTED_SERVICES array (same pattern as manage-svc.sh)
SUPPORTED_SERVICES=(
    # ... existing services ...
    "mongodb"  # ADD THIS
)
```

### Update inventory/localhost.yml

```yaml
# Add after last service section
# ========================================
mongodb_svc:
  hosts:
    firefly:
      # host_vars
      mongodb_svc_name: "mongodb"

  # .......................................
  # mongodb_svc only vars
  vars:
    debug_level: warn
    mongodb_data_dir: "{{ lookup('env', 'HOME') }}/mongodb-data"

    # MongoDB credentials (loaded from environment)
    mongodb_root_username: "{{ lookup('env', 'MONGODB_ROOT_USERNAME', default='') }}"
    mongodb_root_password: "{{ lookup('env', 'MONGODB_ROOT_PASSWORD', default='') }}"
    mongodb_database: "{{ lookup('env', 'MONGODB_DATABASE', default='admin') }}"

    # Test/verification variables
    test_collection: "test_ansible"
    test_document: '{"test": "verification", "timestamp": "{{ ansible_facts.date_time.iso8601 }}"}'

    # Traefik integration
    mongodb_enable_traefik: true
```

## Phase 7: DNS Configuration (Optional - For Traefik SSL)

### Automatic DNS Update

```bash
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly  # For localhost deployment
# or
./update-dns-auto.sh podma    # For remote host deployment
```

This creates: `mongodb.a0a0.org` → `firefly.a0a0.org`

### Manual DNS Update

Edit `update-dns.sh` and add to SERVICES array:

```bash
SERVICES=(
    # ... existing services ...
    "mongodb"
)
```

Then run:
```bash
source ~/.secrets/LabProvision
./update-dns.sh
```

## Phase 8: Testing & Verification

### Complete Test Workflow

```bash
# 1. Prepare (one-time setup)
ansible-playbook --become-password-file ~/.secrets/lavender.pass \
  tmp/mongodb-prepare-*.yml -i inventory/localhost.yml

# 2. Deploy
export MONGODB_ROOT_USERNAME=admin
export MONGODB_ROOT_PASSWORD=TestPass123!
export MONGODB_DATABASE=admin

ansible-playbook --become-password-file ~/.secrets/lavender.pass \
  tmp/mongodb-deploy-*.yml -i inventory/localhost.yml

# 3. Verify
./svc-exec.sh mongodb verify

# 4. Manual testing
podman exec -it mongodb-svc mongosh -u admin -p TestPass123!
> show dbs
> use testdb
> db.users.insertOne({name: "test"})
> db.users.find()

# 5. Check Traefik labels
podman inspect mongodb-gui | jq '.[0].Config.Labels | with_entries(select(.key | startswith("traefik")))'

# Expected output:
# {
#   "traefik.enable": "true",
#   "traefik.http.routers.mongodb.rule": "Host(`mongodb.a0a0.org`)",
#   "traefik.http.services.mongodb.loadbalancer.server.port": "8081"
# }

# 6. Remove (cleanup)
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh mongodb remove
```

## Common Issues & Solutions

### Issue 1: Jinja2 Template Conflicts

**Problem:** `{{.Name}}` in Podman format strings conflicts with Jinja2

**Solution:**
```yaml
# BAD
command: podman ps --format "{{.Names}}"

# GOOD
command: podman ps --format "{%raw%}{{.Names}}{%endraw%}"
```

### Issue 2: Deprecated MongoDB Options

**Problem:** `storage.journal.enabled` causes "Unrecognized option" error in MongoDB 7.0

**Solution:** Remove deprecated options from config file

### Issue 3: Container Log File Permissions

**Problem:** MongoDB can't write to `/var/log/mongodb/mongod.log`

**Solution:** Use stdout/stderr logging (captured by systemd):
```yaml
# Remove systemLog section entirely, or comment it out
# Logs visible via: journalctl --user -u mongodb-svc
```

### Issue 4: Verification Happens Too Fast

**Problem:** Verification fails because containers haven't started yet

**Solution:** Add wait_for task:
```yaml
- name: Wait for MongoDB to be ready
  ansible.builtin.wait_for:
    host: 127.0.0.1
    port: "{{ mongodb_port }}"
    state: started
    delay: 5
    timeout: 60
```

### Issue 5: Authentication Failures in Verification

**Problem:** `mongosh` commands fail with "Authentication failed"

**Solution:** Include credentials in all mongosh commands:
```yaml
command: >
  podman exec mongodb-svc
  mongosh -u {{ mongodb_root_username }} -p {{ mongodb_root_password }}
  --authenticationDatabase admin
  --quiet --eval "db.adminCommand('ping')"
```

### Issue 6: Traefik Labels Not Applied

**Problem:** Container has old labels after quadlet update

**Solution:** Restart the pod to pick up new labels:
```bash
systemctl --user restart mongodb-pod
```

## Best Practices Checklist

### Security
- [ ] Credentials via environment files (mode 0600)
- [ ] Use `no_log: true` for tasks with credentials
- [ ] Default port binding: `127.0.0.1` (not 0.0.0.0)
- [ ] Authentication enabled by default
- [ ] Never commit credentials to git

### Consistency
- [ ] Follow Redis pattern for simple services
- [ ] Follow Mattermost pattern for multi-container services
- [ ] Use _base role for common functionality
- [ ] Service properties fully defined in defaults/main.yml
- [ ] State-based flow in tasks/main.yml

### Reliability
- [ ] Verification tasks with retries
- [ ] Wait for service readiness (wait_for)
- [ ] Functional tests (write/read operations)
- [ ] Health check endpoints
- [ ] Resource limits (optional)

### Documentation
- [ ] README.md with quick start
- [ ] Configuration options documented
- [ ] Troubleshooting section
- [ ] Example usage commands
- [ ] Traefik integration steps

### Testing
- [ ] Prepare workflow succeeds
- [ ] Deploy workflow succeeds
- [ ] Verify workflow passes all checks
- [ ] Traefik labels correctly configured
- [ ] DELETE_DATA removes all data
- [ ] DELETE_IMAGES removes images

## Phase 9: Multi-Host Deployment Testing

After successfully testing on localhost, validate the role works on remote hosts by adding to additional inventory files.

### Add to Remote Host Inventory

**File:** `inventory/podma.yml` (or other remote host inventory)

**Key Considerations:**

1. **Unique Service Names**: Each host needs unique CNAME to avoid DNS conflicts
2. **Port Conflicts**: Check for existing services using same ports
3. **Traefik Labels**: Service name becomes DNS hostname

**Example Configuration:**

```yaml
# ========================================
mongodb_svc:
  hosts:
    podma:
      # host_vars - UNIQUE service name for this host
      mongodb_svc_name: "mongodb-podma"

  # .......................................
  # mongodb_svc only vars
  vars:
    debug_level: warn
    mongodb_data_dir: "{{ lookup('env', 'HOME') }}/mongodb-data"
    mongodb_gui_port: 8082  # Changed from 8081 to avoid conflict

    # MongoDB credentials (loaded from environment)
    mongodb_root_username: "{{ lookup('env', 'MONGODB_ROOT_USERNAME', default='') }}"
    mongodb_root_password: "{{ lookup('env', 'MONGODB_ROOT_PASSWORD', default='') }}"
    mongodb_database: "{{ lookup('env', 'MONGODB_DATABASE', default='admin') }}"

    # Test/verification variables
    test_collection: "test_ansible"
    test_document: '{"test": "verification", "timestamp": "{{ ansible_facts.date_time.iso8601 }}"}'

    # Traefik integration
    mongodb_enable_traefik: true
```

### Remote Host Testing Workflow

```bash
# 1. Test connectivity
ansible -i inventory/podma.yml podma -m ping

# 2. Prepare
./manage-svc.sh -h podma -i inventory/podma.yml mongodb prepare

# 3. Deploy with credentials
export MONGODB_ROOT_USERNAME=admin
export MONGODB_ROOT_PASSWORD=TestPass123!
export MONGODB_DATABASE=admin
./manage-svc.sh -h podma -i inventory/podma.yml mongodb deploy

# 4. Verify deployment
./svc-exec.sh -h podma -i inventory/podma.yml mongodb verify

# Expected output:
# ✓ MongoDB pod running
# ✓ MongoDB version: 7.0.28
# ✓ Connection test: OK
# ✓ Write operation: OK
# ✓ Read operation: OK
# ✓ GUI accessible at http://127.0.0.1:8082
```

### Common Remote Host Issues

#### Issue 1: Port Already in Use

**Symptom:**

```text
Error: starting container: rootlessport listen tcp 127.0.0.1:8081: bind: address already in use
```

**Diagnosis:**

```bash
ssh podma.a0a0.org "ss -tlnp | grep 8081"
```

**Solution:** Override port in inventory:

```yaml
vars:
  mongodb_gui_port: 8082  # or any unused port
```

#### Issue 2: CNAME Conflicts

**Problem:** Multiple hosts trying to use same CNAME (e.g., `mongodb.a0a0.org`)

**Solution:** Use host-specific service names:
```yaml
# inventory/localhost.yml
hosts:
  firefly:
    mongodb_svc_name: "mongodb"  # → mongodb.a0a0.org

# inventory/podma.yml
hosts:
  podma:
    mongodb_svc_name: "mongodb-podma"  # → mongodb-podma.a0a0.org
```

#### Issue 3: SELinux Context Denied

**Symptom:** Permission denied when writing to data directories

**Diagnosis:**

```bash
ssh podma.a0a0.org "ls -laZ ~/mongodb-data/"
```

**Solution:** Re-run prepare step (automatically applies SELinux context):

```bash
./manage-svc.sh -h podma -i inventory/podma.yml mongodb prepare
```

### Verification Checklist (Remote Host)

After deployment on remote host, verify:

- [ ] Pod running: `ssh podma.a0a0.org "systemctl --user status mongodb-pod"`
- [ ] Containers up: `ssh podma.a0a0.org "podman ps --filter pod=mongodb"`
- [ ] Port listening: `ssh podma.a0a0.org "ss -tlnp | grep 27017"`
- [ ] MongoDB responding: Verification tasks pass
- [ ] Traefik labels correct: `mongodb-<hostname>.a0a0.org`
- [ ] DNS record needed: `mongodb-<hostname>.a0a0.org → <hostname>.a0a0.org`

### Multi-Host Summary

**Deployment Results (MongoDB Example):**

| Host | Service Name | MongoDB Port | GUI Port | CNAME Required | Status |
|------|--------------|--------------|----------|----------------|--------|
| firefly | mongodb | 27017 | 8081 | mongodb.a0a0.org | ✅ Working |
| podma | mongodb-podma | 27017 | 8082 | mongodb-podma.a0a0.org | ✅ Working |

**Key Learnings:**

1. Service names must be unique across inventory files to avoid DNS conflicts
2. Check for port conflicts before deployment (especially GUI ports)
3. Verification may need retry logic as containers start asynchronously
4. Traefik labels automatically use service name as hostname prefix
5. Remote hosts benefit from prepare step to ensure proper permissions

## Reference Files

Complete working examples from MongoDB implementation:

- [roles/mongodb/defaults/main.yml](../roles/mongodb/defaults/main.yml)
- [roles/mongodb/tasks/main.yml](../roles/mongodb/tasks/main.yml)
- [roles/mongodb/tasks/prerequisites.yml](../roles/mongodb/tasks/prerequisites.yml)
- [roles/mongodb/tasks/quadlet_rootless.yml](../roles/mongodb/tasks/quadlet_rootless.yml)
- [roles/mongodb/tasks/verify.yml](../roles/mongodb/tasks/verify.yml)
- [roles/mongodb/templates/mongodb.env.j2](../roles/mongodb/templates/mongodb.env.j2)
- [roles/mongodb/templates/mongod.conf.j2](../roles/mongodb/templates/mongod.conf.j2)
- [roles/mongodb/handlers/main.yml](../roles/mongodb/handlers/main.yml)
- [roles/mongodb/README.md](../roles/mongodb/README.md)

## Summary

This pattern enables:
- **Single-command deployment**: `./manage-svc.sh <service> deploy`
- **Consistent structure**: All services follow same pattern
- **Rootless security**: Containers run as regular user
- **Automatic systemd integration**: Podman quadlets → systemd services
- **Flexible credential management**: Environment variables → HashiVault ready
- **Complete cleanup**: Optional data/image removal
- **Traefik SSL support**: Labels configured for automatic HTTPS

The MongoDB implementation demonstrates all these features working together in a production-ready role.
