# TLS Architecture Decision: SSL Termination Proxy Pattern

## Executive Summary

**Decision**: Use Traefik as SSL termination proxy instead of enabling TLS on individual services.

**Rationale**: Services running on localhost (127.0.0.1) cannot be meaningfully protected by TLS. SSL termination at a reverse proxy provides actual security for external access while keeping internal communication simple and fast.

**Status**: Implemented. Legacy TLS variables retained for historical context (Phase 1).

---

## The Evolution

### Original Plan: Service-Level TLS

Initial design included TLS configuration for each service:

```yaml
# Planned for all services
elasticsearch_enable_tls: true
redis_enable_tls: true
mattermost_enable_tls: true
vault_enable_tls: true
gitea_enable_tls: true

# With associated config
<service>_tls_cert_file: "path/to/cert.pem"
<service>_tls_key_file: "path/to/key.pem"
<service>_tls_min_version: "TLSv1.2"
# ... etc
```

**Assumption**: Each service should encrypt its own traffic end-to-end.

---

## The Reality Check

### Problem: Localhost Security Limitations

Services in this architecture bind to `127.0.0.1` (localhost):

```yaml
# Typical port binding
ports:
  - "127.0.0.1:9200:9200"  # Elasticsearch
  - "127.0.0.1:6379:6379"  # Redis
  - "127.0.0.1:8065:8065"  # Mattermost
```

**Security Reality**:
- ✗ Any local process can connect to 127.0.0.1 ports
- ✗ TLS doesn't prevent local access
- ✗ Containers share network namespace with host
- ✗ No meaningful isolation benefit from TLS

**Complexity Cost**:
- Certificate management per service
- Different TLS implementations (Go, Python, Node.js)
- Debugging encrypted traffic
- Performance overhead
- Configuration duplication

**Verdict**: TLS at service level adds complexity without security benefit for localhost-bound services.

---

## The Solution: SSL Termination Proxy

### Architecture Pattern

```
┌─────────────────────────────────────────────────────────┐
│  External Access                                        │
│                                                         │
│  Internet → Traefik (port 8443)                        │
│             ├─ TLS/SSL termination                     │
│             ├─ Let's Encrypt automation                │
│             └─ Wildcard cert: *.a0a0.org               │
│                      │                                  │
│                      ↓ (plain HTTP)                     │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Internal Services (localhost only)              │  │
│  │                                                  │  │
│  │  127.0.0.1:9200  ← Elasticsearch                │  │
│  │  127.0.0.1:6379  ← Redis                        │  │
│  │  127.0.0.1:8065  ← Mattermost                   │  │
│  │  127.0.0.1:8181  ← InfluxDB3                    │  │
│  │  127.0.0.1:3000  ← Grafana                      │  │
│  │  127.0.0.1:9000  ← MinIO                        │  │
│  │  127.0.0.1:3001  ← Gitea                        │  │
│  │  127.0.0.1:8200  ← HashiVault                   │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Benefits

**Security Where It Matters**:
- ✓ External traffic encrypted (HTTPS)
- ✓ Single certificate management point
- ✓ Automatic Let's Encrypt renewal
- ✓ Services remain on localhost (not exposed)

**Operational Simplicity**:
- ✓ Services use plain HTTP (fast, simple)
- ✓ Easy debugging (unencrypted logs)
- ✓ No per-service certificate management
- ✓ Traefik handles all SSL complexity

**Industry Standard**:
- This is the **standard cloud-native pattern**
- Used by: Kubernetes Ingress, AWS ALB, Nginx, HAProxy
- Separation of concerns: proxy handles TLS, services handle business logic

---

## Implementation Details

### Traefik Configuration

**Only service with TLS enabled**:
```yaml
# roles/traefik/defaults/main.yml
traefik_enable_ssl: true
traefik_acme_email: "jack@lavnet.net"
traefik_acme_staging: false
```

**Automatic routing via labels**:
```yaml
# Example: InfluxDB3 Quadlet
traefik.enable=true
traefik.http.routers.influxdb3.rule=Host(`influxdb3.a0a0.org`)
traefik.http.routers.influxdb3.entrypoints=websecure
traefik.http.routers.influxdb3.tls.certresolver=letsencrypt
traefik.http.services.influxdb3.loadbalancer.server.port=8181
```

### DNS Configuration

**Wildcard DNS** points all subdomains to localhost:
```
*.a0a0.org → 127.0.0.1
```

**Result**:
- `https://grafana.a0a0.org:8443` → Traefik → `http://127.0.0.1:3000`
- `https://es.a0a0.org:8443` → Traefik → `http://127.0.0.1:9200`
- All traffic encrypted externally, plain internally

---

## Legacy Variables (Phase 1: Documented)

### Variables Kept But Unused

These variables exist in role defaults but are **not actively used**:

**Elasticsearch** (`roles/elasticsearch/defaults/main.yml`):
```yaml
elasticsearch_enable_tls: false
elasticsearch_tls_cert_file: ""
elasticsearch_tls_key_file: ""
elasticsearch_tls_min_version: "TLSv1.2"
elasticsearch_tls_verify_client: "optional"
```

**Redis** (`roles/redis/defaults/main.yml`):
```yaml
redis_enable_tls: false
redis_tls_cert_file: ""
redis_tls_key_file: ""
redis_tls_auth_clients: "no"
```

**Mattermost** (`roles/mattermost/defaults/main.yml`):
```yaml
mattermost_enable_tls: false
mattermost_tls_cert_file: ""
mattermost_tls_key_file: ""
mattermost_force_tls: false
mattermost_tls_strict_transport: false
mattermost_tls_min_version: "1.2"
```

**HashiVault** (`roles/hashivault/defaults/main.yml`):
```yaml
vault_enable_tls: false
vault_tls_cert_file: ""
vault_tls_key_file: ""
vault_tls_ca_file: ""
vault_tls_min_version: "tls12"
```

**Gitea** (`roles/gitea/defaults/main.yml`):
```yaml
gitea_enable_tls: true  # ← Note: set to true but not implemented
```

**MinIO** (`roles/minio/defaults/main.yml`):
```yaml
minio_enable_tls: false
minio_tls_cert_file: ""
minio_tls_key_file: ""
```

### Why Keep Them (Phase 1)

**Reasons to retain for now**:
1. **Historical context**: Shows architectural evolution
2. **Documentation**: Helps understand why they're not used
3. **No harm**: They don't cause problems (set to false/empty)
4. **Future flexibility**: If architecture changes (unlikely)
5. **Grep-able**: Easy to find and remove later

**Status**: Marked as **DEPRECATED** in comments (see Phase 2 plan below)

---

## Phase 2: Future Cleanup Plan

### When Ready to Remove

**Scope**: Remove unused TLS configuration from service roles

**Services to clean up**:
- elasticsearch (5 TLS variables)
- redis (4 TLS variables)
- mattermost (6 TLS variables)
- hashivault (5 TLS variables)
- gitea (1 TLS variable)
- minio (3 TLS variables)

**Keep**: Traefik TLS configuration (actively used)

### Cleanup Steps

```bash
# 1. Find all TLS variables
grep -r "_enable_tls\|_tls_cert\|_tls_key" roles/*/defaults/main.yml

# 2. Remove from role defaults
# Edit each file, remove TLS variable blocks

# 3. Remove from templates (if any)
grep -r "enable_tls\|tls_cert\|tls_key" roles/*/templates/

# 4. Test each service
./manage-svc.sh <service> deploy
./manage-svc.sh <service> remove

# 5. Checkpoint
git commit -m "refactor: remove unused service-level TLS config"
```

### Estimated Impact

- **Lines removed**: ~50-60 lines across 6 services
- **Risk**: Very low (variables already unused)
- **Testing needed**: Smoke test deployments
- **Time**: ~30 minutes

---

## Lessons Learned

### 1. Security in Context

**Theory**: End-to-end encryption everywhere
**Practice**: Encrypt where threat model requires it

Localhost services have a different threat model than exposed services.

### 2. Separation of Concerns

**Good separation**:
- Traefik: SSL termination, routing, certificates
- Services: Business logic, data processing

**Bad separation**:
- Every service reimplements TLS configuration
- Certificates managed in 8 different places

### 3. Industry Patterns Exist for Reasons

SSL termination proxy is the standard pattern because:
- It works
- It scales
- It's operationally simple
- It separates concerns correctly

**Don't reinvent unless you have a specific reason.**

### 4. Pragmatism Over Purity

**Initial thought**: "Every service should handle its own security"
**Reality**: "Use the right tool for the job"

Sometimes the pragmatic solution (proxy) is better than the "pure" solution (service-level TLS).

---

## Related Decisions

### Why Not mTLS (Mutual TLS)?

**Question**: Should services authenticate to each other via mTLS?

**Answer**: Not needed for this architecture:
- All services on localhost (same security boundary)
- No multi-tenant concerns
- Trust boundary is at Traefik, not between services
- Complexity not justified by threat model

**If needed in future**: Service mesh (Istio, Linkerd) would be better than DIY mTLS.

### Why Not VPN/Wireguard?

**Question**: Should services communicate over VPN?

**Answer**: Overkill for localhost:
- VPN is for network-level isolation
- Services already isolated (localhost binding)
- Would add complexity without benefit

**If deploying across machines**: Then VPN/Wireguard would make sense.

---

## Verification

### Confirm External SSL Works

```bash
# Access via Traefik (should show valid SSL)
curl -v https://grafana.a0a0.org:8443

# Should see:
# * TLS 1.2 connection using TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
# * Server certificate: *.a0a0.org
```

### Confirm Internal Plain HTTP

```bash
# Direct service access (plain HTTP)
curl -v http://localhost:3000

# Should see:
# * Connected to localhost (127.0.0.1) port 3000
# > GET / HTTP/1.1
# (no TLS negotiation)
```

### Confirm Localhost Binding

```bash
# Services should NOT be accessible externally
netstat -tlnp | grep -E ':(9200|6379|8065|3000)'

# Should show:
# 127.0.0.1:9200   (not 0.0.0.0:9200)
# 127.0.0.1:6379   (not 0.0.0.0:6379)
# 127.0.0.1:8065   (not 0.0.0.0:8065)
```

---

## References

### External Resources

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Let's Encrypt Docs](https://letsencrypt.org/docs/)
- [OWASP Transport Layer Protection](https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Protection_Cheat_Sheet.html)
- [Kubernetes Ingress Pattern](https://kubernetes.io/docs/concepts/services-networking/ingress/)

### Internal Documentation

- [Container-Role-Architecture.md](Container-Role-Architecture.md) - Overall architecture
- [Delete-Data-Refactoring.md](Delete-Data-Refactoring.md) - Similar variable cleanup pattern
- `roles/traefik/` - SSL termination implementation

---

## Appendix: Pattern Comparison

### Pattern A: Service-Level TLS (Not Used)

```
Internet → Service (TLS enabled)
           ├─ Certificate management per service
           ├─ Different TLS implementations
           └─ Still accessible on localhost anyway
```

**Pros**: Theoretical end-to-end encryption
**Cons**: Complex, redundant, doesn't solve threat model

### Pattern B: SSL Termination (Current)

```
Internet → Traefik (TLS) → Services (plain HTTP, localhost)
           ├─ Single cert management
           ├─ Standard pattern
           └─ Services isolated by network binding
```

**Pros**: Simple, secure where needed, industry standard
**Cons**: Internal traffic not encrypted (acceptable for localhost)

### Pattern C: Service Mesh (Future Consideration)

```
Internet → Traefik (TLS) → Service Mesh (mTLS) → Services
           ├─ External encryption
           ├─ Internal mTLS
           └─ Policy enforcement
```

**Pros**: Maximum security, policy control
**Cons**: Significant complexity, only needed for multi-host or zero-trust

---

**Document Version**: 1.0
**Date**: 2025-01-09
**Author**: jackaltx with Claude Code
**Status**: Phase 1 - Documented (variables retained)
