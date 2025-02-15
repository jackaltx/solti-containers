# HashiCorp Vault Role

This role deploys HashiCorp Vault in a rootless Podman container with systemd integration.

## Directory Structure

```
roles/
└── vault/
    ├── defaults/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    ├── tasks/
    │   ├── main.yml
    │   ├── prerequisites.yml
    │   ├── containers.yml
    │   ├── systemd.yml
    │   ├── tls.yml
    │   └── cleanup.yml
    └── templates/
        ├── vault.pod.j2
        ├── vault.container.j2
        ├── vault.hcl.j2
        └── vault-ui.container.j2
```

## Implementation

### defaults/main.yml

```yaml
---
# Installation state
vault_state: present
vault_force_reload: false

# Container settings
vault_image: "docker.io/hashicorp/vault:1.15"
vault_ui_image: "docker.io/hashicorp/vault-ui:latest"  # If using separate UI container
vault_data_dir: "{{ ansible_user_dir }}/vault-data"
vault_api_port: 8200
vault_cluster_port: 8201
vault_ui_port: 8200  # Same as API port when using integrated UI

# Security settings
vault_enable_ui: true
vault_initial_root_token: ""  # Generated on first init if not provided
vault_enable_audit: true

# Storage settings
vault_storage_type: "file"  # Options: file, raft, consul
vault_raft_node_id: "node1"
vault_raft_retry_join: []  # List of raft peer addresses

# TLS Configuration
vault_enable_tls: false
vault_tls_cert_file: ""
vault_tls_key_file: ""
vault_tls_ca_file: ""
vault_tls_min_version: "tls12"

# Cleanup settings
vault_delete_data: false
```

### handlers/main.yml

```yaml
---
- name: reload systemd
  ansible.builtin.systemd:
    daemon_reload: yes
    scope: user

- name: restart vault
  ansible.builtin.systemd:
    name: "pod-vault"
    state: restarted
    scope: user
  listen: "restart vault"
```

### tasks/main.yml

```yaml
---
- name: Install Vault
  when: vault_state == 'present'
  block:
    - name: Include prerequisites tasks
      ansible.builtin.include_tasks: prerequisites.yml

    - name: Include TLS tasks
      ansible.builtin.include_tasks: tls.yml
      when: vault_enable_tls | bool

    - name: Include container tasks
      ansible.builtin.include_tasks: containers.yml

    - name: Include systemd tasks
      ansible.builtin.include_tasks: systemd.yml

- name: Remove Vault
  when: vault_state == 'absent'
  block:
    - name: Include cleanup tasks
      ansible.builtin.include_tasks: cleanup.yml
```

### tasks/prerequisites.yml

```yaml
---
- name: Verify prerequisites
  assert:
    that:
      - vault_data_dir is defined
      - vault_api_port is defined
    fail_msg: "Required variables not properly configured"

- name: Create Vault directories
  file:
    path: "{{ vault_data_dir }}/{{ item }}"
    state: directory
    mode: "0750"
  loop:
    - ""  # Base directory
    - config
    - data
    - logs
    - tls

- name: Configure SELinux for Vault directories
  when: ansible_os_family == "RedHat"
  block:
    - name: Set SELinux context
      sefcontext:
        target: "{{ vault_data_dir }}(/.*)?"
        setype: container_file_t
        state: present

    - name: Apply SELinux context
      command: restorecon -Rv "{{ vault_data_dir }}"

- name: Template Vault configuration
  template:
    src: vault.hcl.j2
    dest: "{{ vault_data_dir }}/config/vault.hcl"
    mode: "0640"
  notify: restart vault
```

### tasks/containers.yml

```yaml
---
- name: Create Vault pod
  containers.podman.podman_pod:
    name: vault
    ports:
      - "127.0.0.1:{{ vault_api_port }}:8200"
      - "127.0.0.1:{{ vault_cluster_port }}:8201"

- name: Deploy Vault container
  containers.podman.podman_container:
    name: vault-server
    pod: vault
    image: "{{ vault_image }}"
    state: started
    command: "server"
    volume:
      - "{{ vault_data_dir }}/config:/vault/config:Z,U"
      - "{{ vault_data_dir }}/data:/vault/data:Z,U"
      - "{{ vault_data_dir }}/logs:/vault/logs:Z,U"
      - "{{ vault_data_dir }}/tls:/vault/tls:Z,U"
    env:
      VAULT_ADDR: "http://127.0.0.1:8200"
      VAULT_API_ADDR: "http://127.0.0.1:8200"
      VAULT_CLUSTER_ADDR: "http://127.0.0.1:8201"
    cap_add:
      - IPC_LOCK
    restart_policy: always

- name: Verify container status
  command: podman ps --format {% raw %}"{{.Names}}"{% endraw %} --filter "pod=vault"
  register: container_status
  changed_when: false
```

### templates/vault.hcl.j2

```hcl
ui = {{ vault_enable_ui | lower }}

storage "{{ vault_storage_type }}" {
{% if vault_storage_type == "file" %}
  path = "/vault/data"
{% elif vault_storage_type == "raft" %}
  path = "/vault/data"
  node_id = "{{ vault_raft_node_id }}"
  {% if vault_raft_retry_join | length > 0 %}
  retry_join {
    {% for peer in vault_raft_retry_join %}
    leader_api_addr = "{{ peer }}"
    {% endfor %}
  }
  {% endif %}
{% endif %}
}

listener "tcp" {
  address = "0.0.0.0:8200"
  {% if vault_enable_tls %}
  tls_cert_file = "/vault/tls/{{ vault_tls_cert_file | basename }}"
  tls_key_file  = "/vault/tls/{{ vault_tls_key_file | basename }}"
  {% if vault_tls_ca_file %}
  tls_ca_file   = "/vault/tls/{{ vault_tls_ca_file | basename }}"
  {% endif %}
  tls_min_version = "{{ vault_tls_min_version }}"
  {% else %}
  tls_disable = true
  {% endif %}
}

api_addr = "{% if vault_enable_tls %}https{% else %}http{% endif %}://127.0.0.1:{{ vault_api_port }}"
cluster_addr = "{% if vault_enable_tls %}https{% else %}http{% endif %}://127.0.0.1:{{ vault_cluster_port }}"

{% if vault_enable_audit %}
audit "file" {
  path = "/vault/logs/audit.log"
}
{% endif %}
```

### templates/vault.pod.j2

```ini
[Pod]
Name=vault
PublishPort=127.0.0.1:${VAULT_API_PORT}:8200
PublishPort=127.0.0.1:${VAULT_CLUSTER_PORT}:8201

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### templates/vault.container.j2

```ini
[Unit]
Description=HashiCorp Vault Container
After=network-online.target

[Container]
Image={{ vault_image }}
ContainerName=vault-server
Pod=vault
Volume={{ vault_data_dir }}/config:/vault/config:Z,U
Volume={{ vault_data_dir }}/data:/vault/data:Z,U
Volume={{ vault_data_dir }}/logs:/vault/logs:Z,U
Volume={{ vault_data_dir }}/tls:/vault/tls:Z,U
Environment=VAULT_ADDR=http://127.0.0.1:8200
Environment=VAULT_API_ADDR=http://127.0.0.1:8200
Environment=VAULT_CLUSTER_ADDR=http://127.0.0.1:8201
AddCapability=IPC_LOCK
Command=server

[Service]
Restart=always
TimeoutStartSec=300
TimeoutStopSec=70

[Install]
WantedBy=default.target
```

## Usage Example

```yaml
- hosts: vault_servers
  roles:
    - role: vault
      vars:
        vault_enable_ui: true
        vault_storage_type: file
        vault_enable_audit: true
```

## First-Time Setup

After deploying Vault, you'll need to initialize it:

1. Initialize Vault:

```bash
podman exec vault-server vault operator init
```

2. Unseal Vault (using keys from init):

```bash
podman exec -it vault-server vault operator unseal
```

3. Access the UI:

- Open <http://localhost:8200> in your browser
- Login using the root token from initialization

## Security Considerations

1. Always change the root token after first login
2. Enable audit logging in production
3. Use TLS in production environments
4. Consider using Raft storage for high availability
5. Back up initialization keys and root token securely

## Verification Steps

Create a verification playbook that checks:

- Pod and container status
- Vault health check
- UI accessibility
- TLS configuration (if enabled)
