# Container Mount Options - Architecture Decision

## Context

The `prepare` and `deploy` phases are deliberately separated to handle Podman volume mount options properly. This architectural decision emerged from real-world permission challenges during InfluxDB3 token persistence implementation.

## The Problem

**Container UID != Host UID**: When containers run as different users than the host user who creates directories and files, permission conflicts occur. Specifically:

1. Host user (e.g., UID 1000) creates directory structure during `prepare`
2. Container starts with different internal UID
3. Container cannot read/write files created by host user
4. Results in "Permission denied" errors

## The Solution: Mount Option Flags

Podman provides mount option flags to handle these scenarios:

### `:z` Flag (SELinux Context)

- **Purpose**: Label volume content as shared between containers
- **When to use**: Always on SELinux-enabled systems (RHEL, Fedora, CentOS)
- **Effect**: Sets `svirt_sandbox_file_t` context
- **Example**: `~/service-data/config:/app/config:z`

### `:Z` Flag (SELinux Private Context)

- **Purpose**: Label volume content as private to single container
- **When to use**: When volume should ONLY be accessed by one container
- **Effect**: Sets unique SELinux label per container
- **Example**: `~/service-data/secrets:/app/secrets:Z`

### `:U` Flag (Ownership Mapping)

- **Purpose**: Auto-chown volume contents to match container user
- **When to use**: When container needs to modify files created by host
- **Effect**: Recursively changes ownership to container's UID:GID
- **Example**: `~/service-data/data:/var/lib/app:z,U`
- **Critical**: Solves the "container can't write host-created files" problem

### Common Patterns

```yaml
# Read-only config (host creates, container reads)
- "{{ service_data_dir }}/config:/app/config:z,ro"

# Data directory (container needs write access)
- "{{ service_data_dir }}/data:/var/lib/app:z,U"

# Secrets (private to container, needs write)
- "{{ service_secrets_dir }}:/app/secrets:Z,U"

# Logs (container writes, host reads)
- "{{ service_data_dir }}/logs:/var/log/app:z,U"
```

## Why prepare/deploy Separation?

The two-phase approach exists because:

1. **prepare**: Creates directory structure with host user permissions
   - Creates `~/service-data/{config,data,logs,secrets}`
   - Sets initial ownership to host user
   - Runs BEFORE containers exist

2. **deploy**: Mounts volumes with appropriate flags
   - Container mounts volumes with `:U` flag
   - Podman auto-adjusts ownership on first mount
   - Container can now read/write its volumes

**Without separation**: If we tried to create directories and start containers simultaneously, we'd need to predict which directories need special permissions, leading to brittle permission handling.

**With separation**: Host creates structure, Podman handles permission mapping via mount flags.

## Real-World Example: InfluxDB3 Token Persistence

### Initial Problem

```yaml
# Host creates file (UID 1000)
- name: Save token
  ansible.builtin.copy:
    dest: "{{ influxdb3_secrets_dir }}/admin-token"
    content: "{{ token }}"

# Container mount (no :U flag)
volume:
  - "{{ influxdb3_secrets_dir }}:/var/lib/influxdb3/secrets:z"
```

**Result**: Container (running as influxdb UID) cannot read token file

```
Failed to read admin token file metadata: Permission denied (os error 13)
```

### Solution

```yaml
# Container mount WITH :U flag
volume:
  - "{{ influxdb3_secrets_dir }}:/var/lib/influxdb3/secrets:z,U"

# Host creates file with become
- name: Save token
  become: true
  ansible.builtin.copy:
    dest: "{{ influxdb3_secrets_dir }}/admin-token"
    owner: "{{ ansible_user_id }}"
```

**Result**: `:U` flag ensures container user can read host-created token file

## Guidelines for Service Roles

### When Adding New Services

1. **Identify data types**:
   - Config files: Usually `:z,ro` (read-only)
   - Data directories: Usually `:z,U` (container writes)
   - Secrets: Usually `:Z,U` (private, container writes)
   - Logs: Usually `:z,U` (container writes, host reads)

2. **Test permission scenarios**:
   - Can container read host-created files?
   - Can container write new files?
   - Can host user read container-created files?
   - Do files persist across container restarts?

3. **Review mount options**:
   - Missing `:z` on SELinux systems → denials
   - Missing `:U` when container writes → permission errors
   - Using `:Z` when sharing between containers → conflicts

### Common Pitfalls

❌ **Bad**: No mount flags on SELinux system

```yaml
volume:
  - "{{ service_data_dir }}/data:/var/lib/app"
```

❌ **Bad**: Missing :U when container needs to write

```yaml
volume:
  - "{{ service_data_dir }}/data:/var/lib/app:z"
```

✅ **Good**: Proper flags for container-writable volume

```yaml
volume:
  - "{{ service_data_dir }}/data:/var/lib/app:z,U"
```

## Future Considerations

### Pattern Standardization

Consider adding mount option guidance to `_base` role documentation:

- Standard volume types (config, data, secrets, logs)
- Recommended flags for each type
- Testing checklist for permission verification

### Role Template

Could create a mount options template in `service_properties`:

```yaml
service_properties:
  volumes:
    - { host: "config", container: "/app/config", flags: "z,ro" }
    - { host: "data", container: "/var/lib/app", flags: "z,U" }
    - { host: "secrets", container: "/app/secrets", flags: "Z,U" }
```

### Verification Task

Add to `verify.yml` template:

```yaml
- name: Verify container can write to data directory
  command: podman exec {{ service }}-svc touch /var/lib/app/.write-test
  register: write_test
  failed_when: write_test.rc != 0
```

## References

- Podman volume mount documentation: <https://docs.podman.io/en/latest/markdown/podman-run.1.html#volume-v-source-volume-host-dir-container-dir-options>
- SELinux container contexts: <https://www.redhat.com/sysadmin/privileged-flag-container-engines>
- InfluxDB3 implementation: `roles/influxdb3/tasks/quadlet_rootless.yml:36`

## Related Documents

- [Container Role Architecture](Container-Role-Architecture.md) - Overall pattern
- [SOLTI Container Pattern](Solti-Container-Pattern.md) - Standard structure
- [TLS Architecture Decision](TLS-Architecture-Decision.md) - SSL termination

---

**Document History**:

- 2025-01-10: Created based on InfluxDB3 token persistence implementation
- Key insight: prepare/deploy separation exists to handle mount options properly
