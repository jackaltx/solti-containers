You've hit on a common pain point in Ansible. While it doesn't have traditional programming inheritance or function parameters, there are several patterns we can use to achieve similar goals. Let me outline some approaches:

1. **Reusable Task Files with `vars` include:**

```yaml
# tasks/common/create_directories.yml
- name: Create standard directories
  file:
    path: "{{ dir_base }}/{{ item }}"
    state: directory
    mode: "{{ dir_mode | default('0750') }}"
  loop: "{{ dir_list }}"

# Usage in role:
- name: Include directory creation
  include_tasks: common/create_directories.yml
  vars:
    dir_base: "{{ redis_data_dir }}"
    dir_list:
      - "config"
      - "data"
      - "logs"
```

2. **Role Defaults as "Parameters":**

```yaml
# roles/base_container/defaults/main.yml
container_base_dirs:
  - "config"
  - "data"
container_base_mode: "0750"

# roles/redis/meta/main.yml
dependencies:
  - role: base_container
    vars:
      container_base_dirs: "{{ redis_dirs }}"
```

3. **Using Facts as "Return Values":**

```yaml
# tasks/common/get_container_user.yml
- name: Get container user info
  stat:
    path: "{{ data_dir }}/config"
  register: dir_info

- name: Set container user facts
  set_fact:
    container_user_id: "{{ dir_info.stat.uid }}"
    container_group_id: "{{ dir_info.stat.gid }}"
```

4. **Import with Tags for "Inheritance":**

```yaml
# roles/base_service/tasks/main.yml
- import_tasks: prepare.yml
  tags: ["prepare"]
- import_tasks: configure.yml
  tags: ["configure"]

# roles/redis/tasks/main.yml
- import_tasks: roles/base_service/tasks/main.yml
- name: Redis-specific tasks
  tags: ["redis"]
  block:
    - import_tasks: redis_tasks.yml
```

5. **Using `defaults` Cascading for Optional Parameters:**

```yaml
# common_defaults.yml
service_port: "{{ specific_service_port | default(8080) }}"
service_user: "{{ specific_service_user | default(ansible_user) }}"
```

6. **Template Inheritance Through Includes:**

```yaml
# templates/base/service.conf.j2
[Service]
User={{ service_user }}
{% block service_config %}{% endblock %}

# templates/redis/service.conf.j2
{% include 'base/service.conf.j2' %}
{% block service_config %}
ExecStart=/usr/bin/redis-server
WorkingDirectory={{ redis_dir }}
{% endblock %}
```

7. **Using Group Variables as Common Configuration:**

```yaml
# group_vars/container_services/common.yml
common_dns_servers:
  - "1.1.1.1"
  - "8.8.8.8"
common_networks:
  - name: ct-net
    subnet: "172.24.0.0/16"

# roles/redis/defaults/main.yml
redis_dns_servers: "{{ common_dns_servers }}"
```

8. **Creating a Common Role Structure:**

```yaml
roles/
  ├── _base/  # Base role with common tasks
  │   ├── tasks/
  │   │   ├── directories.yml
  │   │   ├── selinux.yml
  │   │   └── systemd.yml
  │   └── defaults/
  │       └── main.yml
  └── redis/
      ├── meta/
      │   └── main.yml  # Depends on _base
      └── tasks/
          └── main.yml  # Redis-specific tasks
```

Here's how you might implement this for your container services:

```yaml
# roles/_base/tasks/prepare_container.yml
- name: Common container preparation
  block:
    - name: Get directory ownership
      stat:
        path: "{{ service_data_dir }}/config"
      register: dir_info
      
    - name: Create service directories
      file:
        path: "{{ service_data_dir }}/{{ item }}"
        state: directory
        mode: "{{ service_dir_mode | default('0750') }}"
        owner: "{{ dir_info.stat.uid | default(ansible_user_id) }}"
        group: "{{ dir_info.stat.gid | default(ansible_user_id) }}"
      loop: "{{ service_dirs }}"

# roles/redis/tasks/main.yml
- name: Prepare Redis
  include_tasks: roles/_base/tasks/prepare_container.yml
  vars:
    service_data_dir: "{{ redis_data_dir }}"
    service_dirs:
      - "config"
      - "data"
      - "logs"
```

While not perfect, these patterns can help make your Ansible code more maintainable and reusable. The key is to:

1. Use well-structured variable names
2. Leverage facts for passing data
3. Create reusable task files
4. Use role dependencies wisely
5. Take advantage of variable precedence

Would you like me to create an artifact showing how to refactor one of your specific roles using these patterns?
