# Podman User Namespace UID/GID Mapping

**Audience:** Humans and AI
**Purpose:** Explain how rootless Podman maps container UIDs to host UIDs and why files appear with "strange" ownership
**Date:** 2025-12-01

---

## Executive Summary

**If you see files owned by UIDs like 525287, 525288, etc., this is CORRECT behavior.**

Rootless Podman uses **user namespace mapping** for security isolation. Container processes think they're running as UID 1000, but on the host filesystem, those files appear as UID 525287 (or similar). This is a **security feature**, not a bug.

---

## The Core Concept

### Traditional (Docker) Approach
```
Container UID 1000 → Host UID 1000 (direct mapping)
```
- Files written as UID 1000 in container appear as UID 1000 on host
- If UID 1000 doesn't exist on host, files are "orphaned" but accessible by any UID 1000 process
- Less secure: container compromise = direct access to host files with same UID

### Rootless Podman Approach
```
Container UID 1000 → Host UID 525287 (namespace mapping)
```
- Files written as UID 1000 in container appear as UID 525287 on host
- Your user (UID 1000) **cannot** directly access these files
- More secure: container compromise doesn't grant access to your real user's files

---

## How UID Mapping Works

### 1. Subordinate UID Allocation

Check your allocated UID range:
```bash
$ grep lavender /etc/subuid
lavender:524288:65536
```

This means:
- User `lavender` has subordinate UIDs starting at **524288**
- Total range: 65,536 UIDs (524288 through 589823)

### 2. Container UID Mapping

When you run a rootless container, Podman creates this mapping:

```
Container UID  →  Host UID
─────────────────────────────
0 (root)       →  1000 (your user - lavender)
1              →  524288
2              →  524289
3              →  524290
...
1000           →  525287  ← Common app UID inside containers
...
65535          →  589823
```

### 3. View the Mapping

Inside Podman's user namespace:
```bash
$ podman unshare cat /proc/self/uid_map
         0       1000          1
         1     524288      65536
```

Translation:
- Line 1: Container UID 0 maps to host UID 1000 (length: 1 UID)
- Line 2: Container UIDs 1-65536 map to host UIDs 524288-589823

---

## Real-World Example: Gitea

### What You See on Host

```bash
$ ls -lan ~/gitea-data/data
drwxrwxr-x. 1 lavender lavender  22 Nov  6 18:30 .
drwxr-xr-x. 1 lavender lavender  46 Nov  6 18:30 ..
drwxr-xr-x. 1   525287   525287  38 Nov  6 20:26 git      ← UID 525287
drwxr-xr-x. 1   525287   525287 250 Dec  1 17:38 gitea    ← UID 525287
drwx------. 1 lavender lavender 240 Nov  6 20:02 ssh
```

### What the Container Sees

Inside the Gitea container:
```bash
# Container's perspective (if you exec into it)
$ ls -lan /data
drwxr-xr-x. 1    1000     1000  38 Nov  6 20:26 git      ← Thinks it's UID 1000
drwxr-xr-x. 1    1000     1000 250 Dec  1 17:38 gitea    ← Thinks it's UID 1000
drwx------. 1       0        0 240 Nov  6 20:02 ssh      ← Thinks it's UID 0 (root)
```

### The Math

**Container UID 1000 → Host UID ?**

Using the mapping formula:
```
Host UID = Base UID + (Container UID - 1)
Host UID = 524288 + (1000 - 1)
Host UID = 524288 + 999
Host UID = 525287 ✓
```

---

## Security Implications

### Why This is More Secure

**Scenario: Container is compromised**

**Docker (direct mapping):**
```
Attacker gets UID 1000 in container
→ Can access ANY UID 1000 files on host
→ If another service runs as UID 1000, attacker can access its data
```

**Podman (namespace mapping):**
```
Attacker gets UID 1000 in container (thinks they're UID 1000)
→ Actually UID 525287 on host
→ Cannot access your real UID 1000 files
→ Cannot access other users' files
→ Isolated to subordinate UID range
```

### The `ssh/` Directory Anomaly

In the Gitea example, `ssh/` is owned by `lavender:lavender` (1000:1000), not 525287:525287.

**This is a potential security issue:**
- If the container can write to files owned by your real UID
- It breaks the namespace isolation
- Container could modify your actual user files

**Recommendation:** Investigate why `ssh/` is owned differently. Ideally, all container-created files should use mapped UIDs.

---

## Working with Namespace-Mapped Files

### Problem: Can't Access Container Files as Your User

```bash
$ ls -la ~/gitea-data/data/git
drwxr-xr-x. 1 525287 525287 38 Nov  6 20:26 .
# You (UID 1000) don't have write access

$ touch ~/gitea-data/data/git/test
touch: cannot touch '~/gitea-data/data/git/test': Permission denied
```

### Solution 1: Enter the User Namespace

```bash
# Enter Podman's user namespace
$ podman unshare

# Now you're "UID 0" inside the namespace
# But UID 0 inside namespace = your real UID 1000 outside
# The subordinate UIDs become accessible

# Files now appear with correct ownership
$ ls -la ~/gitea-data/data/git
drwxr-xr-x. 1 git git 38 Nov  6 20:26 .
# Shows as "git" (UID 1000 in namespace)

# You can modify files
$ touch ~/gitea-data/data/git/test
# Success!

# Exit namespace
$ exit
```

### Solution 2: Use `podman unshare` for One-Off Commands

```bash
# Change ownership inside namespace
$ podman unshare chown -R 1000:1000 ~/gitea-data/data/gitea/logs

# View files as container would see them
$ podman unshare ls -la ~/gitea-data/data/git
```

### Solution 3: Exec into Running Container

```bash
# Enter the container itself
$ podman exec -it gitea-svc /bin/sh

# You're now inside the container with its UID mapping
$ ls -la /data/git
drwxr-xr-x 1 git git 38 Nov  6 20:26 .
# Shows as UID 1000 (the container's perspective)

$ touch /data/git/newfile
# Creates file as UID 1000 in container = UID 525287 on host
```

---

## Comparison: Podman vs Docker

| Aspect | Rootless Podman | Docker (daemon-based) |
|--------|-----------------|----------------------|
| **UID Mapping** | User namespaces (UID 1000 → 525287) | Direct (UID 1000 → 1000) |
| **File Ownership** | Mapped UIDs (525287, 525288, etc.) | Direct UIDs (1000, 1001, etc.) or orphaned |
| **Security** | High (namespace isolation) | Lower (shared UID space) |
| **Accessing Files** | Requires `podman unshare` or exec | Direct access if UID matches |
| **PUID/PGID Env Vars** | Not needed (rootless by design) | Common pattern (LinuxServer.io images) |
| **Root in Container** | Maps to your user UID | Maps to actual root (if privileged) |

---

## Common Scenarios

### Backing Up Container Data

**Problem:** tar/rsync as your user can't read UID 525287 files

**Solution:**
```bash
# Option 1: Use podman unshare
podman unshare tar czf backup.tar.gz ~/gitea-data/data

# Option 2: Use rootful backup tool with sudo
sudo tar czf backup.tar.gz ~/gitea-data/data
# (Works because root can read all UIDs)

# Option 3: Run backup from inside container
podman exec gitea-svc tar czf /data/backup.tar.gz /data/gitea
podman cp gitea-svc:/data/backup.tar.gz ~/backup.tar.gz
```

### Restoring Container Data

**Problem:** Can't chown to UID 525287 directly

**Solution:**
```bash
# Extract as yourself, then fix ownership in namespace
tar xzf backup.tar.gz -C ~/gitea-data/
podman unshare chown -R 1000:1000 ~/gitea-data/data/git
podman unshare chown -R 1000:1000 ~/gitea-data/data/gitea
```

### Debugging Permission Issues

```bash
# Check what the container sees
podman exec gitea-svc ls -lan /data/git

# Check what the host sees
ls -lan ~/gitea-data/data/git

# Check your subuid allocation
grep $USER /etc/subuid /etc/subgid

# Check current namespace mapping
podman unshare cat /proc/self/uid_map
```

### Migrating from Docker to Podman

**Challenge:** Docker files are UID 1000, Podman expects UID 525287

**Option 1: Let Podman remap on first run**
```bash
# Copy Docker data as-is (UID 1000 files)
cp -a /docker/gitea/data ~/gitea-data/

# Start container - it will fail with permission errors
podman run ... gitea
# Container expects to write as UID 1000 (which maps to 525287)
# But files are already owned by 1000 (your user)

# Fix ownership using podman unshare
podman unshare chown -R 1000:1000 ~/gitea-data/data
# This changes files from host UID 1000 → namespace UID 1000 (= host 525287)
```

**Option 2: Use `podman unshare` to preserve ownership**
```bash
# Enter namespace BEFORE copying
podman unshare

# Now copy files - they'll be remapped automatically
cp -a /docker/gitea/data ~/gitea-data/
# Your UID 1000 becomes namespace UID 0
# Source files UID 1000 become namespace UID 1000 (= host UID 525287)

exit
```

---

## Troubleshooting

### Files Owned by Your User (Not Mapped)

**Symptom:**
```bash
$ ls -lan ~/gitea-data/data
drwxr-xr-x. 1 1000 1000 240 Nov  6 20:02 ssh   ← Your user, not 525287
```

**Problem:** File created outside the container or with special mount options

**Investigation:**
```bash
# Check how volume is mounted
podman inspect gitea-svc | grep -A 10 Mounts

# Check for :U or :z options that might affect ownership
podman inspect gitea-svc | grep -i option
```

**Fix (if needed):**
```bash
# Move ownership into namespace
podman unshare chown -R 1000:1000 ~/gitea-data/data/ssh
```

### Permission Denied Inside Container

**Symptom:**
```bash
podman exec gitea-svc touch /data/test
touch: cannot touch '/data/test': Permission denied
```

**Causes:**
1. Volume mounted read-only
2. SELinux context mismatch
3. Parent directory owned by different UID

**Investigation:**
```bash
# Check mount options
podman inspect gitea-svc | jq '.[0].Mounts'

# Check SELinux context (Fedora/RHEL)
ls -laZ ~/gitea-data

# Check directory ownership from container perspective
podman exec gitea-svc ls -lan /data
```

### UID 65534 (nobody) Files

**Symptom:**
```bash
$ ls -lan ~/gitea-data/data
drwxr-xr-x. 1 65534 65534 38 Nov  6 20:26 overflow
```

**Cause:** UID outside your subordinate range

Container tried to create files as UID 100000, but your subuid range is only 524288-589823. Overflows to UID 65534 (nobody).

**Fix:** Increase subuid range (requires root):
```bash
sudo usermod --add-subuids 100000-165535 $USER
sudo usermod --add-subgids 100000-165535 $USER
podman system migrate
```

---

## Best Practices

### 1. Let Containers Create Their Own Directories

**Don't pre-create with specific UIDs:**
```yaml
# ❌ Bad for Podman
service_properties:
  dirs:
    - {path: "data/gitea", mode: "0775", owner: "1000", group: "1000"}
```

**Let the container create structure:**
```yaml
# ✅ Good for Podman
service_properties:
  mount_point: "~/gitea-data"  # Just ensure mount point exists
  # Container creates subdirs with correct mapped UIDs
```

### 2. Use `podman unshare` for Maintenance

**Don't use sudo for container file operations:**
```bash
# ❌ Bad - breaks ownership
sudo rm -rf ~/gitea-data/data/gitea/sessions

# ✅ Good - preserves namespace mapping
podman unshare rm -rf ~/gitea-data/data/gitea/sessions
```

### 3. Understand Your Subuid Range

```bash
# Check your allocation
grep $USER /etc/subuid /etc/subgid

# Calculate expected UID for container UID 1000
# Formula: subuid_start + (container_uid - 1)
```

### 4. Document Expected Ownership

In service documentation:
```yaml
# Expected ownership (after container runs):
# ~/redis-data/data → 525287:525287 (container UID 999)
# ~/gitea-data/data/git → 525287:525287 (container UID 1000)
```

### 5. Backup with Namespace Awareness

```bash
# Include in backup scripts
backup_container_data() {
    local service=$1
    local data_dir=$2

    # Use podman unshare to preserve ownership
    podman unshare tar czf "/backups/${service}-$(date +%Y%m%d).tar.gz" "$data_dir"
}
```

---

## Key Takeaways

1. **UID 525287 and similar are NORMAL** - this is Podman's user namespace mapping
2. **More secure than Docker** - container isolation at the UID level
3. **Use `podman unshare`** to access container files from the host
4. **Don't pre-create directories with specific UIDs** - let containers handle it
5. **Namespace mapping is per-user** - different users get different UID ranges
6. **Files owned by your actual UID inside container data = potential security issue**

---

## References

- [Podman Rootless Tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [User Namespaces - Linux man page](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Understanding Podman User Namespace Modes](https://www.redhat.com/sysadmin/rootless-podman)
- `/etc/subuid` and `/etc/subgid` - subordinate UID/GID allocation files

---

## Document History

- 2025-12-01: Initial documentation based on Gitea deployment analysis
- Focus: Clarify that "strange UIDs" are a security feature, not a bug
