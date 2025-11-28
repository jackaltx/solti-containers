# Claude Code Commands for SOLTI Containers

This file defines custom commands that Claude Code can execute for this project.

## /verify-all

**Purpose:** Discover all supported services and run verification for each one.

**Process:**

1. Discover which services have `verify.yml` files by checking `roles/*/tasks/verify.yml`
2. Extract service names from paths (e.g., `roles/hashivault/tasks/verify.yml` → `hashivault`)
3. Check which services are currently running using `podman pod ps`
4. Load `labenv` environment once
5. Execute `./svc-exec.sh <service> verify` for each running service with verify.yml
6. Report summary of passed/failed/skipped verifications

**Important:** Service directory names (e.g., `hashivault`) are used with `./svc-exec.sh`, not the pod names (e.g., `vault`). The script handles name mapping internally.

**Usage:**

```
/verify-all
```

**Prerequisites:**

- `labenv` alias must be configured and available
- Environment variables from labenv must be loaded before running svc-exec.sh

**Example execution:**

```bash
# 1. Find all services with verify.yml
# Output: roles/elasticsearch/tasks/verify.yml, roles/hashivault/tasks/verify.yml, etc.

# 2. Check running pods
podman pod ps --format "{{.Name}}"
# Output: elasticsearch, vault, redis, etc.

# 3. Map service names to pod names (hashivault → vault, others match 1:1)

# 4. Run verifications in single shell session with labenv loaded
source $HOME/.secrets/LabProvision && \
  ./svc-exec.sh elasticsearch verify && \
  ./svc-exec.sh gitea verify && \
  ./svc-exec.sh grafana verify && \
  ./svc-exec.sh hashivault verify && \
  ./svc-exec.sh influxdb3 verify && \
  ./svc-exec.sh mattermost verify && \
  ./svc-exec.sh minio verify && \
  ./svc-exec.sh redis verify && \
  ./svc-exec.sh traefik verify
```

**Expected behavior:**

- Discovers services with verify.yml files dynamically from `roles/*/tasks/verify.yml`
- Uses `podman pod ps` to check running pods (more reliable than systemctl grep)
- Loads labenv environment once at the start
- Runs verification for all running services with verify tasks sequentially
- Provides summary table with pass/fail status for each service
- Notes which services were skipped (not running or no verify.yml)
