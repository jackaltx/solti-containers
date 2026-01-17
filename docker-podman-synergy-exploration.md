# Docker-Podman Synergy Exploration

**Date:** 2025-12-01
**Context:** Comparing solti-containers (Podman/dev tools) with TrueNAS Docker (persistent services)

---

## 🎯 Core Insight: Different Missions, Shared DNA

**solti-containers (Podman):** Development/testing tools - ephemeral workloads
**TrueNAS (Docker):** Production infrastructure - persistent services

But underneath, they share nearly **identical lifecycle requirements**.

---

## 🔄 Lifecycle Synergy Map

### Current State Comparison

| Phase | Podman (solti-containers) | Docker (TrueNAS) | Gap |
|-------|--------------------------|------------------|-----|
| **Initialize** | `./manage-svc.sh redis prepare`<br>Creates dirs, SELinux contexts, network | Manual: `mkdir /mnt/zpool/Docker/Stacks/redis`<br>`chown 1000:1000 ...` | ❌ No automation |
| **Deploy** | `./manage-svc.sh redis deploy`<br>Templates Quadlets → systemd → verify | Manual: `cd redis && sudo docker compose up -d` | ❌ No templating |
| **Verify** | `./svc-exec.sh redis verify`<br>API tests, data persistence checks | Manual: Check Dozzle logs, curl endpoints | ❌ No standardized tests |
| **Update** | Redeploy (data preserved by default) | `docker compose pull && up -d` | ⚠️ Manual, no safety checks |
| **Remove** | `./manage-svc.sh redis remove`<br>`DELETE_DATA=true` for full cleanup | `docker compose down` (data persists)<br>Manual dir removal | ⚠️ No data cleanup option |

### 💡 Key Realization

The **service_properties pattern is runtime-agnostic**. It describes WHAT a service needs, not HOW to deploy it.

**Current (Podman):**
```yaml
service_properties:
  root: "redis"
  quadlets: ["redis.pod", "redis-svc.container"]
  data_dir: "~/redis-data"
  dirs: [{path: "config", mode: "0755"}, {path: "data", mode: "0750"}]
  container_images: ["redis:7.2-alpine"]
```

**Translated (Docker):**
```yaml
service_properties:
  root: "redis"
  compose_file: "compose.yaml"
  data_dir: "/mnt/zpool/Docker/Stacks/redis"
  dirs: [{path: "config", mode: "0755"}, {path: "data", mode: "0750"}]
  container_images: ["redis:7.2-alpine"]
  networks: ["backend_storage"]
  traefik_domain: "redis.a0a0.org"
```

Same structure, different rendering backend.

---

## 🏗️ Architecture Synergy: The Three Pillars

Your Podman project has **three innovations** that apply directly to Docker:

### 1. **Dynamic Playbook Generation** → **Template-Driven Compose Files**

**Podman (current):**
```bash
# manage-svc.sh generates Ansible playbooks on-the-fly
./manage-svc.sh redis deploy
# → Generates tmp/redis-present.yml
# → Runs ansible-playbook
# → Deploys Quadlets → systemd
```

**Docker (opportunity):**
```bash
# Same interface, different backend
./manage-svc.sh redis deploy
# → Generates redis/compose.yaml from template
# → Runs docker compose up -d
# → Runs verification tasks
```

**Why this matters:** You have **11 services** on TrueNAS. Hand-editing 11 compose files with duplicate Traefik labels, volume patterns, and network configs is error-prone. Template generation eliminates this.

### 2. **service_properties Abstraction** → **Declarative Service Definitions**

**Instead of:**
```yaml
# redis/compose.yaml (hand-written, duplicates patterns)
# jellyfin/compose.yaml (hand-written, duplicates patterns)
# minio/compose.yaml (hand-written, duplicates patterns)
```

**You'd have:**
```yaml
# redis/service.yml (declarative properties)
service_properties:
  name: redis
  image: redis:7.2-alpine
  port: 6379
  network: backend_storage
  traefik_enabled: true
  volumes:
    - {local: "data", container: "/data"}
    - {local: "config/redis.conf", container: "/usr/local/etc/redis/redis.conf", readonly: true}
  healthcheck:
    command: "redis-cli ping"
    interval: "30s"
```

**Then:** Template engine generates compose.yaml with correct Traefik labels, volume mappings, network config.

### 3. **_base Role Inheritance** → **Shared Compose Patterns**

**Podman's _base role** handles:
- Directory creation (using `service_properties.dirs`)
- Network setup (ct-net for all services)
- Cleanup logic (data/image deletion options)
- SELinux contexts (RHEL-specific)

**Docker equivalent:**
- **base_service.yml.j2** template with Traefik labels, network config, restart policies
- **prepare.yml** playbook creates dirs from `service_properties.dirs`
- **cleanup.yml** playbook handles `docker compose down [--volumes] [--rmi all]`

---

## 🔧 The UID/GID Reality: Podman vs Docker

> **📚 See [Podman-User-Namespaces.md](docs/Podman-User-Namespaces.md) for comprehensive explanation**

### Critical Difference: User Namespace Mapping

**Podman (rootless):**
- Uses **user namespace mapping** for security
- Container UID 1000 → Host UID 525287 (mapped via /etc/subuid)
- Files appear owned by "strange" UIDs like 525287, 525288
- **This is correct behavior** - it's a security feature
- More isolated, more secure

**Docker (daemon-based):**
- Direct UID mapping (or PUID/PGID env vars)
- Container UID 1000 → Host UID 1000 (direct)
- Files owned by numeric UIDs (may be orphaned on host)
- Less isolated, simpler to understand

### Example: Gitea on Both Platforms

**Podman (local - Fedora):**
```bash
~/gitea-data/data/
├── git/      525287:525287  ← Container UID 1000 mapped through namespace
├── gitea/    525287:525287  ← Container UID 1000 mapped through namespace
└── ssh/      1000:1000      ← Your user (potential security issue)

# The math: 524288 (subuid base) + (1000 - 1) = 525287
```

**Docker (TrueNAS):**
```bash
/mnt/zpool/Docker/Stacks/gitea/
├── git/      1000:1000  ← Container UID 1000 (from USER_UID env var)
├── gitea/    1000:1000  ← No corresponding user on host (orphaned)
└── ssh/      0:568      ← Root inside container

# No namespace mapping - direct UID assignment
```

### Implications for "Prepare" Phase

**Podman:**
- ❌ **DON'T** pre-create directories with specific UIDs
- ✅ **DO** let containers create structure (they handle mapping)
- ✅ **DO** use `podman unshare` if you need to manipulate files
- Current prepare phase is **too prescriptive** for rootless Podman

**Docker:**
- ✅ **CAN** pre-create directories if needed
- ✅ **DO** let containers create structure (they know best UID/GID)
- Numeric UIDs (1000, 568) are fine - no user in /etc/passwd needed
- Prepare phase should be **minimal** - just ensure mount point exists

### Revised Prepare Philosophy (Both Platforms)

**What Prepare Should Do:**
1. Create top-level mount point only
2. Generate configuration files (in separate config directory)
3. Validate prerequisites (network, dependencies)

**What Prepare Should NOT Do:**
1. ❌ Pre-create internal directory structure
2. ❌ Set specific UIDs/GIDs on data directories
3. ❌ Assume what ownership container will use

**Rationale:** Containers know their own UID/GID requirements better than we do. Let them create their own structure with appropriate ownership on first run.

---

## 🔗 Practical Synergy Opportunities

### Opportunity 1: **Unified Management Interface**

Both projects could use the same `manage-svc.sh` interface:

```bash
# Local Podman (development)
./manage-svc.sh -p podman -h localhost redis deploy

# Remote Docker (production)
./manage-svc.sh -p docker -h truenas.a0a0.org redis deploy
```

**Implementation:**
- `-p podman`: Uses quadlet templates + ansible-playbook
- `-p docker`: Uses compose templates + docker compose commands
- Same service definitions, different backends

### Opportunity 2: **Shared Verification Framework**

Your verification tasks are **99% identical** between platforms:

**Podman (current):**
```yaml
- name: Test Redis write
  command: podman exec redis-svc redis-cli SET test_key test_value

- name: Test Redis read
  command: podman exec redis-svc redis-cli GET test_key
  register: result
```

**Docker (translated):**
```yaml
- name: Test Redis write
  command: docker compose -f redis/compose.yaml exec -T redis redis-cli SET test_key test_value

- name: Test Redis read
  command: docker compose -f redis/compose.yaml exec -T redis redis-cli GET test_key
  register: result
```

Only the container runtime command changes. You could create **shared verification libraries**:

```yaml
# services/redis/verify.yml (shared)
verify_tasks:
  - command: "redis-cli SET {{test_key}} {{test_value}}"
  - command: "redis-cli GET {{test_key}}"
    expected: "{{test_value}}"
```

Then platform-specific wrappers inject `podman exec` or `docker compose exec`.

### Opportunity 3: **Development → Production Pipeline**

**The killer feature:**

1. **Develop service config locally (Podman)**
   ```bash
   ./manage-svc.sh redis prepare
   ./manage-svc.sh redis deploy
   ./svc-exec.sh redis verify
   # Iterate on templates, test persistence, etc.
   ```

2. **Deploy to production (Docker on TrueNAS)**
   ```bash
   ./manage-svc.sh -h truenas.a0a0.org redis deploy
   ./svc-exec.sh -h truenas.a0a0.org redis verify
   # Same service definition, different platform
   ```

**Same configs, tested locally, deployed remotely.**

### Opportunity 4: **Inventory-Driven Configuration**

Both projects could share inventory structure:

**Development (inventory/localhost.yml):**
```yaml
all:
  vars:
    domain: example.com
    traefik_enabled: false  # No Traefik on localhost
  children:
    redis_svc:
      vars:
        redis_data_dir: "~/redis-data"
        redis_password: changeme
```

**Production (inventory/truenas.yml):**
```yaml
all:
  vars:
    domain: a0a0.org
    traefik_enabled: true
    traefik_network: backend_storage
  children:
    redis_svc:
      hosts:
        truenas.a0a0.org:
      vars:
        redis_data_dir: "/mnt/zpool/Docker/Stacks/redis"
        redis_password: "{{ vault_redis_password }}"
```

Same service definitions, environment-specific overrides.

---

## ⚖️ Where Synergy BREAKS (Platform Differences)

### 1. **systemd Integration**

**Podman Quadlets:**
```bash
systemctl --user status redis-pod.service
journalctl --user -u redis-pod -f
```
Native systemd units, automatic restarts, boot persistence.

**Docker Compose:**
```bash
docker compose ps
docker compose logs -f
```
No native systemd integration (unless you create wrapper units).

**Impact:** Podman fits server management paradigm better. Docker is more "application-centric."

### 2. **Traefik Reverse Proxy**

**Your TrueNAS pattern:** All services behind Traefik with SSL
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.redis.rule=Host(`redis.a0a0.org`)"
```

**Podman equivalent:** Would need Traefik container + labels in Quadlets (possible but uncommon).

**Impact:** Traefik is Docker-ecosystem native. For Podman, you'd typically use nginx/HAProxy or direct service exposure.

### 3. **Rootless vs PUID/PGID**

**Podman:** Rootless by design, containers run as your user UID
**Docker:** Daemon-based, uses PUID/PGID env vars for LinuxServer.io images

**Impact:** Permission models differ. Podman is more secure by default, Docker requires PUID management.

### 4. **Network Models**

**Podman:** User-scoped networks (`podman network create ct-net`)
**Docker:** System bridge networks (`docker network create backend_storage`)

**Impact:** Podman networks isolated per user, Docker networks system-wide.

---

## 🎯 Strategic Recommendation: Hybrid Architecture

### Keep Projects Separate, Share Patterns

**Don't merge repos**, but extract common patterns:

```
solti-common/          # Shared library repo
├── roles/
│   └── service_base/  # Common lifecycle tasks
│       ├── tasks/
│       │   ├── prepare.yml      # Dir creation (minimal!)
│       │   ├── verify.yml       # Generic healthchecks
│       │   └── cleanup.yml      # Data/image removal
│       └── templates/
│           └── service_properties.schema.yml
├── library/
│   └── service_properties.py    # Custom Ansible module
└── docs/
    └── Service-Pattern.md       # Architecture docs

solti-containers/      # Podman-specific
├── roles/
│   ├── _base/         # Includes solti-common/service_base
│   └── redis/         # Podman Quadlet templates
└── manage-svc.sh      # Podman backend

true-docker/           # Docker-specific
├── roles/
│   ├── _base/         # Includes solti-common/service_base
│   └── redis/         # Docker Compose templates
└── manage-svc.sh      # Docker Compose backend
```

**Shared:**
- service_properties abstraction
- Verification task patterns
- Minimal directory creation (mount points only)
- Documentation patterns

**Platform-specific:**
- Deployment backends (Quadlets vs Compose)
- Network configuration
- Security contexts (SELinux vs PUID)
- UID/GID handling (rootless vs daemon-based)

---

## 📋 Concrete Next Steps for TrueNAS

Based on solti-containers patterns, your TrueNAS project needs:

### 1. **Lifecycle Automation** (Missing entirely)

Create `manage-svc.sh` for Docker:

```bash
#!/bin/bash
# manage-svc.sh for Docker Compose lifecycle

ACTION=$1  # prepare|deploy|remove
SERVICE=$2

case $ACTION in
  prepare)
    # Create top-level data directory (minimal!)
    # Generate compose.yaml from template
    # Do NOT pre-create internal structure - let container handle it
    ;;
  deploy)
    # Run prepare if needed
    # docker compose up -d
    # Run verification tasks
    ;;
  remove)
    # docker compose down
    # Optional: Remove volumes (DELETE_DATA=true)
    # Optional: Remove images (DELETE_IMAGES=true)
    ;;
esac
```

### 2. **Service Properties Pattern**

Convert hand-written compose files to templates:

**Before (hand-written):**
```yaml
# redis/compose.yaml - 50 lines of boilerplate
services:
  redis:
    image: redis:7.2-alpine
    container_name: redis
    labels:
      - "traefik.enable=true"
      # ... 10 more label lines
```

**After (generated from properties):**
```yaml
# redis/service.yml - 10 lines of config
name: redis
image: redis:7.2-alpine
port: 6379
network: backend_storage
volumes:
  - data:/data
healthcheck: "redis-cli ping"
```

Template expands this to full compose.yaml with Traefik labels.

### 3. **Verification Framework**

Add health checks to every service:

```yaml
# redis/verify.yml
- name: Check Redis container running
  command: docker compose ps redis --format json
  register: status

- name: Test Redis connectivity
  command: docker compose exec -T redis redis-cli ping
  register: result
  failed_when: result.stdout != "PONG"

- name: Test data persistence
  command: docker compose exec -T redis redis-cli SET test_key test_value
```

Run after deployment: `./svc-exec.sh redis verify`

### 4. **Inventory-Driven Secrets**

Replace plaintext `.env` files with Ansible vault:

```yaml
# inventory/truenas.yml
all:
  vars:
    traefik_domain: a0a0.org
  children:
    redis_svc:
      vars:
        redis_password: "{{ vault_redis_password }}"
    minio_svc:
      vars:
        minio_root_user: "{{ vault_minio_user }}"
        minio_root_password: "{{ vault_minio_password }}"
```

```bash
# vault.yml (encrypted)
vault_redis_password: "actual_secure_password"
vault_minio_user: "admin"
vault_minio_password: "another_secure_password"
```

### 5. **Template Inheritance**

Create base compose template:

```jinja2
# templates/base_service.yml.j2
services:
  {{ service_name }}:
    image: {{ service_image }}
    container_name: {{ service_name }}
    {% if traefik_enabled %}
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network={{ network }}"
      - "traefik.http.routers.{{ service_name }}.rule=Host(`{{ service_name }}.{{ domain }}`)"
      - "traefik.http.routers.{{ service_name }}.entrypoints=websecure"
      - "traefik.http.routers.{{ service_name }}.tls.certresolver=letsencrypt"
      - "traefik.http.services.{{ service_name }}.loadbalancer.server.port={{ service_port }}"
    {% endif %}
    networks:
      - {{ network }}
    restart: unless-stopped
```

Every service inherits this pattern.

---

## 🚀 Migration Path (If You Want This)

**Phase 1: Proof of Concept (1 service)**
- Pick Redis (simplest service)
- Create `service_properties.yml`
- Build compose template + generate script
- Add verification tasks
- Test: `./manage-svc.sh redis deploy`

**Phase 2: Expand Pattern (3-4 services)**
- MinIO (multi-container)
- Jellyfin (media volumes)
- Traefik (network dependencies)
- Validate template patterns work across complexity

**Phase 3: Full Migration**
- Template all 11 services
- Migrate .env → inventory.yml + vault
- Document patterns
- Archive hand-written compose files

**Phase 4: Cross-Platform**
- Test service definitions on Podman
- Validate dev → prod pipeline
- Extract solti-common library

---

## 🤔 The Deeper Question: Should You?

**Arguments FOR adopting solti-containers patterns:**
- ✅ Consistent lifecycle across all container platforms
- ✅ Reduced duplication (11 services × 20 lines Traefik labels = 220 lines eliminated)
- ✅ Verification framework catches deployment issues
- ✅ Dev/prod parity (test locally, deploy confidently)
- ✅ Vault integration (no more plaintext passwords in .env)

**Arguments AGAINST:**
- ❌ Learning curve (Ansible, Jinja templates, inventory patterns)
- ❌ Over-engineering (Arcane GUI already works well)
- ❌ Complexity (adds abstraction layer)
- ❌ Docker Compose is simpler (readable YAML vs generated files)

**My take:**

The synergy is **very strong** for the lifecycle/verification/inventory patterns, but the **value proposition differs** based on scale:

- **< 5 services:** Hand-written compose files fine, Arcane GUI sufficient
- **5-15 services:** Template generation starts paying off (you're at 11)
- **15+ services:** Automation essential, solti-containers patterns mandatory

Since you're evaluating TrueNAS for "persistent containers" vs Podman for "dev tools," I'd suggest:

**Incremental adoption:**
1. Add verification tasks (high value, low effort)
2. Create inventory.yml with vault (security win)
3. Evaluate templating after 15+ services (if you get there)
4. Keep Arcane GUI (it works, don't break what works)

The **real synergy** is: Test service configs on Podman locally (fast iteration), deploy to TrueNAS for production (persistent storage). Same service definitions, different backends.

---

## 🐛 Active Issue: Gitea UID/GID Investigation

### Current Observations

**Local Podman (Fedora):**
```bash
~/gitea-data/                    1000:1000  (lavender user)
├── config/                      1000:1000
├── data/                        1000:1000
└── logs/                        1000:1000
```

**TrueNAS Docker:**
```bash
/mnt/zpool/Docker/Stacks/gitea/  568:568   (apps user, top-level)
├── git/                         1000:1000  (orphaned UID, created by container)
├── gitea/                       1000:1000  (orphaned UID, created by container)
│   ├── gitea.db                 1000:1000
│   ├── conf/                    1000:1000
│   ├── log/                     1000:1000
│   └── sessions/                1000:1000  (0700 permissions)
└── ssh/                         0:568      (root:apps)
```

**Key Facts:**
- UID 1000 on local system = lavender (real user)
- UID 1000 on TrueNAS = **no corresponding user** (numeric orphan)
- Gitea respects `USER_UID=1000` from env vars
- Container creates files as UID 1000 regardless of host user database
- This is **working as intended** - no action needed

### Why This Works

Docker containers use **numeric UIDs**, not usernames:
- Container internally runs as UID 1000
- Writes files to /data mount as UID 1000
- Host stores files with UID 1000 (even if no user exists)
- No /etc/passwd entry needed on host

**Lesson:** Don't try to "fix" orphaned UIDs. If the service works, the ownership is correct.

### Next Investigation

Need to understand:
- Why top-level is 568:568 (apps) but subdirs are 1000:1000
- Whether this causes any permission issues
- If Gitea SSH functionality works with mixed ownership
