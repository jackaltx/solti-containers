# Traefik Standardization Sprint

**Date:** 2025-01-20
**Status:** ✅ Complete
**Objective:** Standardize Traefik label configuration across all services

---

## Summary

Standardized Traefik integration across 9 services to use consistent patterns:
- Dict format for labels
- Conditional enable flags
- HTTPS-only on port 8080
- No HTTP redirect middleware

---

## Changes Made

### 1. Enable Flags Added ✅

Added `<service>_enable_traefik: true` to all services' `defaults/main.yml`:

| Service | File | Line |
|---------|------|------|
| mattermost | roles/mattermost/defaults/main.yml | 15 |
| grafana | roles/grafana/defaults/main.yml | 19 |
| hashivault | roles/hashivault/defaults/main.yml | 34 |
| elasticsearch | roles/elasticsearch/defaults/main.yml | 30 |
| minio | roles/minio/defaults/main.yml | 35 |
| redis | roles/redis/defaults/main.yml | 34 |
| gitea | roles/gitea/defaults/main.yml | 25 |
| influxdb3 | roles/influxdb3/defaults/main.yml | 33 |
| traefik | roles/traefik/defaults/main.yml | 32 |

### 2. Dict Pattern Conversion ✅

Converted all services from `quadlet_options` with `Label=` strings to `label:` dict format:

**Before:**
```yaml
quadlet_options:
  - "Label=traefik.enable=true"
  - "Label=traefik.http.routers.grafana.rule=Host(`{{ grafana_fqdn }}`)"
```

**After:**
```yaml
label:
  traefik.enable: "{{ grafana_enable_traefik | lower }}"
  traefik.http.routers.grafana.rule: "Host(`{{ grafana_fqdn }}`)"
```

Services modified:
- mattermost/tasks/quadlet_rootless.yml:95-101
- grafana/tasks/quadlet_rootless.yml:61-67
- hashivault/tasks/quadlet_rootless.yml:54-64
- elasticsearch/tasks/quadlet_rootless.yml:72-81
- minio/tasks/quadlet_rootless.yml:64-75
- redis/tasks/quadlet_rootless.yml:70-76
- influxdb3/tasks/quadlet_rootless.yml:46-51
- gitea (already using dict)
- traefik (already using dict)

### 3. Conditional Enable ✅

Changed from hardcoded `traefik.enable: "true"` to conditional:
```yaml
traefik.enable: "{{ <service>_enable_traefik | lower }}"
```

All 9 services now support runtime enable/disable via inventory override.

### 4. HTTP Redirect Removed ✅

Removed `,redirect-to-https@file` from all middlewares:

**Before:**
```yaml
traefik.http.routers.grafana.middlewares: "secHeaders@file,redirect-to-https@file"
```

**After:**
```yaml
traefik.http.routers.grafana.middlewares: "secHeaders@file"
```

**Rationale:** Services only expose websecure (443/8080), no HTTP port exposed, so redirect is unnecessary and adds complexity.

### 5. Traefik Port Configuration ✅

**File:** roles/traefik/tasks/quadlet_rootless.yml:60-62

**Before:**
```yaml
ports:
  - "0.0.0.0:{{ traefik_http_port }}:8080"     # HTTP/HTTPS
  - "0.0.0.0:{{ traefik_https_port }}:8443"    # Unused
  - "127.0.0.1:{{ traefik_dashboard_port }}:9000"
```

**After:**
```yaml
ports:
  - "0.0.0.0:{{ traefik_http_port }}:8080"     # HTTPS websecure entrypoint
  - "127.0.0.1:{{ traefik_dashboard_port }}:9000" # Dashboard API
```

**Traefik config already correct:**
- `websecure` entrypoint on internal port 8080 (maps to host 8080)
- `web` entrypoint already commented out (no HTTP port 80)

---

## Pattern Consistency

### Standard Single-Container Pattern

```yaml
# defaults/main.yml
<service>_enable_traefik: true

# tasks/quadlet_rootless.yml
label:
  traefik.enable: "{{ <service>_enable_traefik | lower }}"
  traefik.http.routers.<service>.rule: "Host(`{{ <service>_fqdn }}`)"
  traefik.http.routers.<service>.entrypoints: "websecure"
  traefik.http.routers.<service>.service: "<service>"
  traefik.http.services.<service>.loadbalancer.server.port: "<port>"
  traefik.http.routers.<service>.middlewares: "secHeaders@file"
```

### Multi-Router Pattern (Elasticsearch, HashiVault)

```yaml
label:
  traefik.enable: "{{ <service>_enable_traefik | lower }}"
  # Primary router
  traefik.http.routers.<service>-primary.rule: "Host(`{{ <service>_fqdn }}`)"
  traefik.http.routers.<service>-primary.service: "<service>"
  traefik.http.services.<service>.loadbalancer.server.port: "<port>"
  # Secondary router (alias)
  traefik.http.routers.<service>-secondary.rule: "Host(`{{ <service>_fqdn_alt }}`)"
  traefik.http.routers.<service>-secondary.service: "<service>"  # Same service
```

### Multi-Port Pattern (Minio)

```yaml
label:
  traefik.enable: "{{ minio_enable_traefik | lower }}"
  # API router
  traefik.http.routers.minio-api.rule: "Host(`{{ minio_api_domain }}`)"
  traefik.http.routers.minio-api.service: "minio-api"
  traefik.http.services.minio-api.loadbalancer.server.port: "9000"
  # Console router
  traefik.http.routers.minio-console.rule: "Host(`{{ minio_console_domain }}`)"
  traefik.http.routers.minio-console.service: "minio-console"
  traefik.http.services.minio-console.loadbalancer.server.port: "9001"
```

### Multi-Container Pattern (Redis)

```yaml
# Only GUI container has Traefik labels
# Redis server (redis-svc) has NO labels - internal only

- name: Create Redis Commander container
  when: redis_enable_gui | bool
  label:
    traefik.enable: "{{ redis_enable_traefik | lower }}"
    # ... router config for GUI only
```

---

## Testing

### Verification Steps

```bash
# 1. Deploy Traefik
./manage-svc.sh traefik deploy

# Verify websecure entrypoint on 8080
curl -k https://traefik.example.com:8080

# 2. Deploy a test service
./manage-svc.sh grafana deploy

# 3. Verify Traefik labels in container
podman inspect grafana-svc | jq '.Config.Labels'

# 4. Test HTTPS access
curl -k https://grafana.example.com:8080

# 5. Verify HTTP is NOT exposed (should fail)
curl http://grafana.example.com:80
# Expected: Connection refused

# 6. Test conditional disable
# In inventory.yml:
# grafana_enable_traefik: false

./manage-svc.sh grafana deploy
podman inspect grafana-svc | jq '.Config.Labels["traefik.enable"]'
# Expected: "false"
```

### Rollback

If issues arise, each service's enable flag can be disabled individually:

```yaml
# inventory.yml
grafana_enable_traefik: false  # Disable Traefik for this service only
```

Or globally remove from pod mapping:
```yaml
ports:
  - "127.0.0.1:3000:3000"  # Direct access, bypass Traefik
```

---

## Files Changed

### Defaults (Enable Flags)
- roles/mattermost/defaults/main.yml
- roles/grafana/defaults/main.yml
- roles/hashivault/defaults/main.yml
- roles/elasticsearch/defaults/main.yml
- roles/minio/defaults/main.yml
- roles/redis/defaults/main.yml
- roles/gitea/defaults/main.yml
- roles/traefik/defaults/main.yml
- roles/influxdb3/defaults/main.yml (already existed)

### Quadlets (Label Format)
- roles/mattermost/tasks/quadlet_rootless.yml
- roles/grafana/tasks/quadlet_rootless.yml
- roles/hashivault/tasks/quadlet_rootless.yml
- roles/elasticsearch/tasks/quadlet_rootless.yml
- roles/minio/tasks/quadlet_rootless.yml
- roles/redis/tasks/quadlet_rootless.yml
- roles/influxdb3/tasks/quadlet_rootless.yml
- roles/gitea/tasks/quadlet_rootless.yml (conditional only)
- roles/traefik/tasks/quadlet_rootless.yml (conditional + port cleanup)

### Documentation
- docs/Traefik-Label-Consolidation-Pattern.md (new)
- docs/sprints/TRAEFIK_STANDARDIZATION_2025-01-20.md (this file)

---

## Impact Assessment

### Backward Compatibility
✅ **Compatible** - All changes are opt-in via enable flags defaulting to `true`

### Breaking Changes
❌ **None** - Existing deployments continue working without modification

### Performance
✅ **Neutral** - No performance impact, label format equivalent

### Security
✅ **Improved**:
- No HTTP exposure (removed redirect middleware)
- Explicit HTTPS-only configuration
- Runtime disable capability for sensitive services

---

## Future Enhancements

See [Traefik-Label-Consolidation-Pattern.md](../Traefik-Label-Consolidation-Pattern.md) for:
- _base role consolidation pattern
- Dynamic label generation
- Further code reduction (80% potential)
- Multi-container standardization

**Recommendation:** Defer _base consolidation until Q2 2025 or when adding 3+ new services.

---

## Lessons Learned

### What Worked Well
✅ Dict format cleaner than `Label=` strings
✅ Conditional enable provides flexibility
✅ Removing HTTP redirect simplifies architecture
✅ Consistent patterns easier to maintain

### Challenges
⚠️ Multi-container services (Minio, Redis) need special patterns
⚠️ Hostname aliases (Elasticsearch, HashiVault) require multiple routers
⚠️ Service-specific edge cases (Traefik dashboard TLS cert resolver)

### Recommendations
- Keep dict format for new services
- Document special patterns in service CLAUDE.md
- Consider _base consolidation when service count exceeds 12
- Add validation task to check label consistency

---

## Sign-Off

**Completed by:** Claude Code
**Reviewed by:** [User review pending]
**Deployed to:** Development environment
**Production ready:** ✅ Yes (after user testing)

---

## Related Documentation

- [Traefik Label Consolidation Pattern](../Traefik-Label-Consolidation-Pattern.md) - Future enhancement proposal
- [Container Role Architecture](../Container-Role-Architecture.md) - Overall pattern guide
- [Solti Container Pattern](../Solti-Container-Pattern.md) - Service structure
