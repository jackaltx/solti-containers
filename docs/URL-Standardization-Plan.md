# URL/Service Naming Standardization Plan

**Date:** 2025-11-18
**Status:** In Progress (Gitea Complete)
**Purpose:** Standardize service URL construction across all solti-containers roles for multi-host deployments

---

## Background

The collection had inconsistent patterns for defining service URLs and FQDNs:
- **Minio, Redis, Grafana**: Used `*_svc_name` variables with FQDN calculation ✅
- **Gitea**: Hardcoded domains with mismatched naming (gitea1 vs gitea-test) ❌
- **Elasticsearch, HashiVault, InfluxDB3, Mattermost**: Fully hardcoded hostnames ❌

This creates problems for multi-host deployments where each host needs unique service names.

---

## Standard Pattern

### Inventory Structure

```yaml
{service}_svc:
  hosts:
    firefly:
      {service}_svc_name: "{service}"        # Production: base name
    podma:
      {service}_svc_name: "{service}-test"   # Test: -test suffix
  vars:
    {service}_external_port: 8080            # Port for Traefik access
```

### Role Defaults (roles/{service}/defaults/main.yml)

```yaml
# Service naming and URL construction
{service}_svc_name: "{service}"                                      # Base default (overridden by inventory)
{service}_fqdn: "{{ {service}_svc_name }}.{{ domain }}"             # Calculated FQDN
{service}_external_port: 8080                                        # External access port
{service}_external_url: "https://{{ {service}_fqdn }}:{{ {service}_external_port }}"
```

### Traefik Labels (roles/{service}/tasks/quadlet_rootless.yml)

```yaml
label:
  traefik.enable: "true"
  traefik.http.routers.{service}.rule: "Host(`{{ {service}_fqdn }}`)"
  traefik.http.routers.{service}.entrypoints: "websecure"
  traefik.http.routers.{service}.service: "{service}"
  traefik.http.services.{service}.loadbalancer.server.port: "{internal_port}"
```

---

## Services Status

| Service | Status | Pattern | Notes |
|---------|--------|---------|-------|
| **Gitea** | ✅ **COMPLETE** | `svc_name` → FQDN | Tested on podma |
| **Grafana** | ✅ Already correct | `svc_name` → FQDN calculation | Uses set_fact |
| **Minio** | ✅ Already correct | Dual `svc_name` (API + Console) | Complex but correct |
| **Redis** | ✅ Already correct | `svc_name` → inline FQDN | Simple pattern |
| **Elasticsearch** | ❌ **TODO** | Hardcoded | Dual routes: elasticsearch + es |
| **HashiVault** | ❌ **TODO** | Hardcoded | Dual routes: vault + hashivault |
| **InfluxDB3** | ❌ **TODO** | Hardcoded | Single route |
| **Mattermost** | ❌ **TODO** | Hardcoded | Single route |
| **Traefik** | ⏸️ Optional | Dashboard | Low priority |
| **Wazuh** | ⏸️ Deprecated | N/A | Skip (removal only) |

---

## Completed Work: Gitea

### Changes Made

**1. Inventory (inventory.yml:332-354)**
```yaml
gitea_svc:
  hosts:
    firefly:
      gitea_svc_name: "gitea"
    podma:
      gitea_svc_name: "gitea-test"
  vars:
    gitea_external_port: 8080
```

**2. Defaults (roles/gitea/defaults/main.yml:18-27)**
```yaml
# Service naming and URL construction
gitea_svc_name: "gitea"  # Override per host in inventory
gitea_fqdn: "{{ gitea_svc_name }}.{{ domain }}"
gitea_external_port: 8080  # Port users access through Traefik
gitea_external_url: "https://{{ gitea_fqdn }}:{{ gitea_external_port }}"

# Application settings (backward compatibility)
gitea_domain: "{{ gitea_fqdn }}"
gitea_root_url: "{{ gitea_external_url }}"
```

**3. Traefik Labels (roles/gitea/tasks/quadlet_rootless.yml:89)**
```yaml
traefik.http.routers.gitea.rule: "Host(`{{ gitea_fqdn }}`)"
```

**4. Verification Output (roles/gitea/tasks/verify.yml:118)**
```yaml
- "Traefik: {{ gitea_external_url }}"
```

### Results

- **firefly**: `https://gitea.a0a0.org:8080`
- **podma**: `https://gitea-test.a0a0.org:8080`

### Additional Fixes (rootless container issues)

- Added `become: false` to all podman commands in:
  - initialize-gitea.yml (3 tasks)
  - verify.yml (6 tasks)
  - quadlet_rootless.yml (2 tasks)
- Fixed password creation (shell module + single quotes)
- Added `service_state: absent` to cleanup task call
- Fixed `/logs` typo (removed leading slash)

### Commits

1. `3c4ab7f` - Fix prepare task issues across roles (include_role → include_tasks, real_user setup)
2. `6c8ffe6` - Standardize gitea URL/service naming pattern
3. `56f11ae` - Fix gitea admin password creation
4. `d8df96c` - Add become:false to gitea verify podman commands

---

## Remaining Work

### Phase 1: User-Facing Services (High Priority)

#### Mattermost
**Current state:**
```yaml
# Hardcoded in quadlet_rootless.yml
Label=traefik.http.routers.mattermost.rule=Host(`mattermost.{{ domain }}`)
```

**Required changes:**

1. **inventory.yml** - Add service naming:
```yaml
mattermost_svc:
  hosts:
    firefly:
      mattermost_svc_name: "mattermost"
    podma:
      mattermost_svc_name: "mattermost-test"
  vars:
    mattermost_external_port: 8080
```

2. **roles/mattermost/defaults/main.yml** - Add URL construction:
```yaml
mattermost_svc_name: "mattermost"
mattermost_fqdn: "{{ mattermost_svc_name }}.{{ domain }}"
mattermost_external_port: 8080
mattermost_external_url: "https://{{ mattermost_fqdn }}:{{ mattermost_external_port }}"
```

3. **roles/mattermost/tasks/quadlet_rootless.yml** - Update Traefik labels:
```yaml
Label=traefik.http.routers.mattermost.rule=Host(`{{ mattermost_fqdn }}`)
```

4. **Update any verification/output** - Use `mattermost_external_url`

**Result:**
- firefly: `mattermost.a0a0.org:8080`
- podma: `mattermost-test.a0a0.org:8080`

---

### Phase 2: Backend Services (Medium Priority)

#### Elasticsearch (Dual Routes)

**Current state:**
```yaml
# Hardcoded dual routes in quadlet
- "Label=traefik.http.routers.elasticsearch0.rule=Host(`elasticsearch.{{ domain }}`)"
- "Label=traefik.http.routers.elasticsearch1.rule=Host(`es.{{ domain }}`)"
```

**Required changes:**

1. **inventory.yml**:
```yaml
elasticsearch_svc:
  hosts:
    firefly:
      elasticsearch_svc_name: "elasticsearch"
      elasticsearch_svc_name_short: "es"
    podma:
      elasticsearch_svc_name: "elasticsearch-test"
      elasticsearch_svc_name_short: "es-test"
```

2. **roles/elasticsearch/defaults/main.yml**:
```yaml
elasticsearch_svc_name: "elasticsearch"
elasticsearch_svc_name_short: "es"
elasticsearch_fqdn: "{{ elasticsearch_svc_name }}.{{ domain }}"
elasticsearch_fqdn_short: "{{ elasticsearch_svc_name_short }}.{{ domain }}"
```

3. **roles/elasticsearch/tasks/quadlet_rootless.yml**:
```yaml
- "Label=traefik.http.routers.elasticsearch0.rule=Host(`{{ elasticsearch_fqdn }}`)"
- "Label=traefik.http.routers.elasticsearch1.rule=Host(`{{ elasticsearch_fqdn_short }}`)"
```

**Result:**
- firefly: `elasticsearch.a0a0.org` + `es.a0a0.org`
- podma: `elasticsearch-test.a0a0.org` + `es-test.a0a0.org`

---

#### HashiVault (Dual Routes)

**Current state:**
```yaml
# Hardcoded dual routes
- "Label=traefik.http.routers.vault-primary.rule=Host(`vault.{{ domain }}`)"
- "Label=traefik.http.routers.vault-secondary.rule=Host(`hashivault.{{ domain }}`)"
```

**Required changes:**

1. **inventory.yml**:
```yaml
hashivault_svc:
  hosts:
    firefly:
      hashivault_svc_name: "vault"
      hashivault_svc_name_alt: "hashivault"
    podma:
      hashivault_svc_name: "vault-test"
      hashivault_svc_name_alt: "hashivault-test"
```

2. **roles/hashivault/defaults/main.yml**:
```yaml
hashivault_svc_name: "vault"
hashivault_svc_name_alt: "hashivault"
hashivault_fqdn: "{{ hashivault_svc_name }}.{{ domain }}"
hashivault_fqdn_alt: "{{ hashivault_svc_name_alt }}.{{ domain }}"
```

3. **roles/hashivault/tasks/quadlet_rootless.yml**:
```yaml
- "Label=traefik.http.routers.vault-primary.rule=Host(`{{ hashivault_fqdn }}`)"
- "Label=traefik.http.routers.vault-secondary.rule=Host(`{{ hashivault_fqdn_alt }}`)"
```

**Result:**
- firefly: `vault.a0a0.org` + `hashivault.a0a0.org`
- podma: `vault-test.a0a0.org` + `hashivault-test.a0a0.org`

---

#### InfluxDB3 (Simple Single Route)

**Current state:**
```yaml
# Hardcoded
- "Label=traefik.http.routers.influxdb3.rule=Host(`influxdb3.{{ domain }}`)"
```

**Required changes:**

1. **inventory.yml**:
```yaml
influxdb3_svc:
  hosts:
    firefly:
      influxdb3_svc_name: "influxdb3"
    podma:
      influxdb3_svc_name: "influxdb3-test"
```

2. **roles/influxdb3/defaults/main.yml**:
```yaml
influxdb3_svc_name: "influxdb3"
influxdb3_fqdn: "{{ influxdb3_svc_name }}.{{ domain }}"
influxdb3_external_port: 8080
influxdb3_external_url: "https://{{ influxdb3_fqdn }}:{{ influxdb3_external_port }}"
```

3. **roles/influxdb3/tasks/quadlet_rootless.yml**:
```yaml
- "Label=traefik.http.routers.influxdb3.rule=Host(`{{ influxdb3_fqdn }}`)"
```

**Result:**
- firefly: `influxdb3.a0a0.org:8080`
- podma: `influxdb3-test.a0a0.org:8080`

---

## Benefits

1. **Multi-host deployment support** - Different instances on different hosts with unique names
2. **Consistency** - All services follow identical pattern
3. **No hardcoding** - All URLs calculated from service name variable
4. **Traefik integration** - Automatic cert generation for each unique FQDN
5. **Testing flexibility** - Easy to differentiate dev/test/prod instances
6. **Documentation** - Clear, consistent naming convention

---

## Migration Strategy

### Recommended Approach

**Option 1: Sequential (Safer)**
- Implement one service at a time
- Test each thoroughly before proceeding
- Start with user-facing (Mattermost), then backend services

**Option 2: Batch by Type (Faster)**
- Batch 1: Simple single-route services (Mattermost, InfluxDB3)
- Batch 2: Complex dual-route services (Elasticsearch, HashiVault)

**Option 3: All at Once (Fastest)**
- Update all 4 remaining services in one session
- More efficient but higher risk
- Requires careful testing

### Testing Checklist (Per Service)

- [ ] Service deploys successfully on firefly
- [ ] Service deploys successfully on podma
- [ ] Traefik routing works (both routes if dual)
- [ ] Verification tasks pass
- [ ] Service-specific functionality works
- [ ] Removal/cleanup works
- [ ] Documentation updated

---

## DNS/TLS Considerations

### Current Setup
- Manual DNS configuration required for each FQDN
- Traefik handles Let's Encrypt certificate generation
- Wildcard DNS: `*.a0a0.org` → localhost

### Future Enhancement (Optional)
Enable Traefik DNS challenge for automatic DNS record creation:

```yaml
# In Traefik configuration
certificatesResolvers:
  letsencrypt:
    acme:
      dnsChallenge:
        provider: linode
        resolvers:
          - "1.1.1.1:53"

# Environment variable
LINODE_TOKEN: "{{ lookup('env', 'LINODE_API_TOKEN') }}"
```

**Benefits:**
- Automatic DNS record creation
- No manual DNS setup per service
- Certificates work immediately on deployment

**Trade-offs:**
- Requires Linode API token management
- More complex configuration
- DNS provider dependency

---

## Open Questions

1. **External port consistency**: Should all services use 8080, or allow per-service customization?
   - Current: Mix of hardcoded ports
   - Recommendation: Standardize on 8080 with per-service override option

2. **Dual-route naming**: For services with multiple hostnames, should test instances keep one consistent?
   - Example: `elasticsearch-test` + `es-test` vs `elasticsearch-test` + `es`
   - Recommendation: Suffix both for clarity

3. **Root URL vs External URL**: Some services (like Gitea) need root_url for internal config
   - Pattern: Define both `*_fqdn` (for Traefik) and `*_external_url` (for app config)

4. **Migration timing**: When to update each service?
   - Recommendation: User-facing services (Mattermost) first, backend services as needed

---

## References

- Original analysis: Agent research session 2025-11-18
- Gitea implementation: Commits 3c4ab7f, 6c8ffe6, 56f11ae, d8df96c
- Working examples: minio (dual service), redis (simple), grafana (set_fact pattern)
- Architecture doc: Container-Role-Architecture.md

---

## Next Actions

1. **Review this plan** - Confirm approach and priorities
2. **Choose migration strategy** - Sequential, batched, or all-at-once
3. **Start implementation** - Begin with highest priority service
4. **Test thoroughly** - Each service on both firefly and podma
5. **Update documentation** - Record patterns and lessons learned
