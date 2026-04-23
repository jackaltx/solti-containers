# Podman Container Service Pattern Guide

This guide documents the standard pattern for creating containerized services using Podman, based on proven implementations like Mattermost and Elasticsearch.

## Directory Structure

```
roles/
└── your_service/
    ├── defaults/
    │   └── main.yml         # Default variables
    ├── handlers/
    │   └── main.yml         # Service restart handlers
    ├── tasks/
    │   ├── main.yml         # Main task orchestration
    │   ├── prerequisites.yml # System preparations
    │   ├── containers.yml   # Container deployment
    │   ├── systemd.yml      # Systemd integration
    │   ├── tls.yml          # TLS configuration (optional)
    │   └── cleanup.yml      # Service removal tasks
    └── templates/
        ├── service.pod.j2           # Pod Quadlet
        ├── service-app.container.j2 # Main service Quadlet
        └── service-db.container.j2  # Database Quadlet (if needed)
```

## Standard Variables (defaults/main.yml)

```yaml
# Installation state
service_state: present
service_force_reload: false

# Container settings
service_image: "docker.io/org/image:tag"
service_data_dir: "{{ ansible_facts.user_dir }}/service-data"
service_port: 8080

# Security settings
service_password: "changeme"
service_enable_security: true

# TLS settings
service_enable_tls: false
service_tls_cert_file: ""
service_tls_key_file: ""

# Cleanup settings
service_delete_data: false
```

## Implementation Steps

### 1. Prerequisites (prerequisites.yml)

```yaml
- name: Verify prerequisites
  assert:
    that:
      - service_password != "changeme"
      - service_data_dir is defined
    fail_msg: "Required variables not properly configured"

- name: Create service directories
  file:
    path: "{{ service_data_dir }}/{{ item }}"
    state: directory
    mode: "0750"
  loop:
    - ""  # Base directory
    - config
    - data
    - logs

- name: Configure SELinux (RHEL only)
  when: ansible_os_family == "RedHat"
  block:
    - name: Set SELinux context
      sefcontext:
        target: "{{ service_data_dir }}(/.*)?"
        setype: container_file_t
        state: present

    - name: Apply SELinux context
      command: restorecon -Rv "{{ service_data_dir }}"
```

### 2. Container Deployment (containers.yml)

```yaml
- name: Create service pod
  containers.podman.podman_pod:
    name: service-pod
    ports:
      - "127.0.0.1:{{ service_port }}:8080"

- name: Deploy service container
  containers.podman.podman_container:
    name: service-app
    pod: service-pod
    image: "{{ service_image }}"
    state: started
    volume:
      - "{{ service_data_dir }}/config:/config:Z,U"
      - "{{ service_data_dir }}/data:/data:Z,U"
    env:
      SERVICE_PASSWORD: "{{ service_password }}"
    restart_policy: always

- name: Verify container status
  command: podman ps --format {% raw %}"{{.Names}}"{% endraw %} --filter "pod=service-pod"
  register: container_status
  changed_when: false
```

### 3. Systemd Integration (systemd.yml)

```yaml
- name: Ensure systemd directories exist
  file:
    path: "{{ ansible_facts.user_dir }}/{{ item }}"
    state: directory
    mode: "0750"
  loop:
    - .config/systemd/user
    - .config/containers/systemd

- name: Template Quadlet files
  template:
    src: "{{ item.src }}"
    dest: "{{ ansible_facts.user_dir }}/.config/containers/systemd/{{ item.dest }}"
    mode: "0644"
  loop:
    - { src: service.pod.j2, dest: service.pod }
    - { src: service-app.container.j2, dest: service-app.container }

- name: Generate systemd units
  command:
    cmd: podman generate systemd --name service-pod --files --new
    chdir: "{{ ansible_facts.user_dir }}/.config/systemd/user"

- name: Enable and start services
  systemd:
    name: pod-service
    state: started
    enabled: yes
    scope: user
```

### 4. Cleanup Tasks (cleanup.yml)

```yaml
- name: Stop and disable services
  systemd:
    name: "pod-service"
    state: stopped
    enabled: no
    scope: user

- name: Remove pod and containers
  containers.podman.podman_pod:
    name: service-pod
    state: absent

- name: Remove systemd files
  file:
    path: "{{ item }}"
    state: absent
  loop:
    - "{{ ansible_facts.user_dir }}/.config/systemd/user/pod-service.service"
    - "{{ ansible_facts.user_dir }}/.config/containers/systemd/service.pod"
    - "{{ ansible_facts.user_dir }}/.config/containers/systemd/service-app.container"

- name: Remove data directory
  file:
    path: "{{ service_data_dir }}"
    state: absent
  when: service_delete_data | bool
```

## Quadlet Templates

### Pod Template (service.pod.j2)

```ini
[Pod]
Name=service-pod
PublishPort=127.0.0.1:${SERVICE_PORT}:8080

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Container Template (service-app.container.j2)

```ini
[Unit]
Description=Service Container
After=network-online.target

[Container]
Image={{ service_image }}
ContainerName=service-app
Pod=service-pod
Volume={{ service_data_dir }}/config:/config:Z,U
Volume={{ service_data_dir }}/data:/data:Z,U
Environment=SERVICE_PASSWORD={{ service_password }}

[Service]
Restart=always
TimeoutStartSec=300
TimeoutStopSec=70

[Install]
WantedBy=default.target
```

## Best Practices

1. **Security**:
   - Always bind ports to localhost (127.0.0.1)
   - Use secure passwords and TLS when possible
   - Follow principle of least privilege

2. **Data Management**:
   - Keep data in user's home directory
   - Use appropriate SELinux contexts
   - Implement backup strategies

3. **Systemd Integration**:
   - Use Quadlets for service definitions
   - Enable user lingering
   - Set appropriate timeouts

4. **Error Handling**:
   - Verify prerequisites
   - Check container status
   - Handle cleanup gracefully

5. **Platform Compatibility**:
   - Support both RHEL and Debian-based systems
   - Handle SELinux appropriately
   - Use distribution-specific package managers

## Verification

Include a verification playbook that checks:

- Pod and container status
- Service accessibility
- Basic functionality
- Configuration parameters

Example from Redis verification:

```yaml
- name: Verify service is running
  command: podman pod ps --format {% raw %}"{{.Name}}"{% endraw %}
  register: pod_status
  failed_when: "'service-pod' not in pod_status.stdout"
  changed_when: false

- name: Test service functionality
  uri:
    url: "http://localhost:{{ service_port }}/health"
    return_content: yes
  register: health_check
```
