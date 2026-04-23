# Rootless Podman Network Architecture: Why Localhost-Only

**Audience:** Developers and AI tools (ref.tools)
**Purpose:** Explain the design choice to bind all services to 127.0.0.1 (not a technical limitation)
**Date:** 2026-01-28
**System:** Fedora 43, Podman 5.7.1, netavark networking

---

## Executive Summary

**Design Choice**: All services bind to 127.0.0.1 (localhost) only, not external network interfaces.

**Technical Reality**: Modern Podman with netavark/pasta CAN expose rootless containers on external interfaces, but this architecture deliberately doesn't use that capability.

**Why This Was Chosen** (Security over Flexibility):

- Defense-in-depth: Services not directly exposed to network
- Centralized security policy via Traefik
- Single TLS termination point
- Simpler firewall configuration

**Trade-offs** (What We Lose):

- No network segmentation (all services share 127.0.0.1 namespace)
- Cannot partition services by interface (eth0 vs wlan0)
- Port management critical (conflicts possible on single interface)
- Less flexible routing options

**Status**: Pragmatic security choice, not ideal, works

---

## Network Binding Options for Rootless Podman

### What This Architecture Uses

```yaml
# ✅ CHOSEN PATTERN - Localhost binding
ports:
  - "127.0.0.1:9200:9200"       # Elasticsearch
  - "127.0.0.1:6379:6379"       # Redis
  - "127.0.0.1:8065:8065"       # Mattermost
  - "127.0.0.1:3000:3000"       # Grafana
```

### What's Technically Possible (But Not Used)

With modern Podman (5.x+) and netavark/pasta networking:

```yaml
# ✅ TECHNICALLY WORKS (not used in this architecture)
# pasta/netavark can expose on external interfaces
ports:
  - "0.0.0.0:9200:9200"         # All interfaces (unprivileged ports >1024)
  - "192.168.1.100:9200:9200"   # Specific host IP
```

**Limitations that still exist**:

- Privileged ports (<1024) require `sysctl net.ipv4.ip_unprivileged_port_start` adjustment
- pasta mode: No NAT by default, copies host IPs into container namespace
- netavark mode: CNI-based bridge networking with port forwarding

### Why We Don't Use External Binding

**Security**: Defense-in-depth - services not directly exposed to network

**Simplicity**: Single pattern (localhost) vs mixed patterns (some localhost, some external)

**Traefik Advantages**: TLS termination, authentication, routing, rate limiting all in one place

**Consistency**: Same approach works for all services regardless of port number

---

## Why Localhost-Only is the Design Choice

### Technical Capabilities (What's Possible)

Modern Podman 5.x with **netavark** or **pasta** networking modes CAN expose rootless containers on external interfaces:

**netavark** (Current system - Fedora 43, Podman 5.7.1):

- CNI-based bridge networking
- Port forwarding to external interfaces supported
- Unprivileged ports (>1024) work without sysctl changes

**pasta** (Alternative mode):

- No NAT by default - copies host IPs into container namespace
- Can bind to external interfaces automatically
- Newer approach, default on RHEL 9.5+

### Security Model: User Namespace Isolation

Rootless Podman runs containers in **user namespaces** for security:

1. Container processes run as your user (UID 1000)
2. No root privileges on host system
3. Limited kernel network capabilities
4. Privileged ports (<1024) require sysctl configuration
5. External binding possible but not automatically privileged

**This security model is why localhost-only is the better choice.**

### Network Architecture Comparison

**Option 1: External Binding (Possible, Not Used)**:

```
┌─────────────────────────────────────────────────────────┐
│  Host Network Interfaces                                │
│  ├─ eth0: 192.168.1.100                                │
│  │   └─ :9200 → elasticsearch (direct exposure)       │
│  │   └─ :6379 → redis (direct exposure)               │
│  ├─ wlan0: 192.168.1.50                                │
│  │   └─ :8065 → mattermost (direct exposure)          │
│  └─ lo: 127.0.0.1                                      │
│      └─ (unused)                                       │
└─────────────────────────────────────────────────────────┘
```

**Problems**: Each service exposed, no central policy, TLS per-service, complex firewall rules

**Option 2: Localhost-Only + Proxy (Our Choice)**:

```
┌─────────────────────────────────────────────────────────┐
│  eth0: 192.168.1.100                                    │
│  └─ :8443 → Traefik (single entry point)              │
│             ├─ TLS termination                          │
│             ├─ Authentication                           │
│             └─ Routes to localhost services             │
│                                                         │
│  lo: 127.0.0.1 (all services here)                     │
│  ├─ :9200 → elasticsearch (internal only)              │
│  ├─ :6379 → redis (internal only)                      │
│  ├─ :8065 → mattermost (internal only)                 │
│  └─ :3000 → grafana (internal only)                    │
└─────────────────────────────────────────────────────────┘
```

**Benefits**: Single exposure point, centralized security, simple firewall, consistent TLS

---

## Initial Architecture Goal vs What We Got

### What Was Wanted: Network Segmentation

```
Original Vision:
┌────────────────────────────────────────────────────────┐
│  eth0:9200     → Elasticsearch                         │
│  eth0:6379     → Redis                                 │
│  eth0:8065     → Mattermost                            │
│  wlan0:3000    → Grafana (separate interface)          │
│  192.168.1.10  → MinIO (dedicated IP)                  │
│  192.168.1.11  → Gitea (dedicated IP)                  │
└────────────────────────────────────────────────────────┘

Desired Benefits:
✓ Network isolation per service
✓ Firewall rules per interface
✓ Separate routing tables
✓ Independent traffic shaping
✓ Clear service boundaries
```

**This IS technically possible with modern Podman**, but security concerns led to a different choice.

### What We Actually Implemented: Shared Localhost Namespace

```
Chosen Implementation (Security over Flexibility):
┌────────────────────────────────────────────────────────┐
│  ALL on 127.0.0.1 (localhost)                          │
│  ├─ :9200  → Elasticsearch                             │
│  ├─ :6379  → Redis                                     │
│  ├─ :8065  → Mattermost                                │
│  ├─ :8087  → InfluxDB3                                 │
│  ├─ :3000  → Grafana                                   │
│  ├─ :9000  → MinIO                                     │
│  ├─ :3001  → Gitea                                     │
│  └─ :8200  → HashiVault                                │
└────────────────────────────────────────────────────────┘

What This Gives Us:
✓ Services not exposed to network by default
✓ Single Traefik entry point for security policy
✓ Centralized TLS termination
✓ Simple mental model (localhost = internal)

What We Lose:
✗ No network-level segmentation
✗ All services share same interface (port conflicts possible)
✗ Cannot partition by network (eth0 for public, wlan0 for private, etc.)
✗ Less flexible than desired
```

**The Honest Assessment**: This works and is secure, but it's a compromise. The original vision of network segmentation would be preferable if security could be maintained.

---

## The Security Benefit: Forced Proxy Pattern

### Why Localhost-Only Helps Security

**Problem with Direct External Exposure**:

```
┌─────────────────────────────────────────────────────────┐
│ External Network (192.168.1.0/24)                       │
│                                                         │
│ Attacker can directly access:                           │
│  ├─ 192.168.1.100:9200 → Elasticsearch (bypass proxy)  │
│  ├─ 192.168.1.100:6379 → Redis (no auth check)         │
│  ├─ 192.168.1.100:8065 → Mattermost (no TLS)           │
│  └─ 192.168.1.100:3000 → Grafana (no rate limiting)    │
│                                                         │
│ Security depends on EACH service implementing:          │
│  - TLS configuration                                    │
│  - Authentication                                       │
│  - Rate limiting                                        │
│  - Access logging                                       │
└─────────────────────────────────────────────────────────┘
```

**Even with Traefik deployed**, if services are on external interfaces, attackers can bypass Traefik entirely.

**Solution: Localhost-Only Forces Proxy Use**:

```
┌─────────────────────────────────────────────────────────┐
│ External Network (192.168.1.0/24)                       │
│                                                         │
│ Only entry point:                                       │
│  └─ 192.168.1.100:8443 → Traefik                       │
│                           ├─ TLS termination            │
│                           ├─ Authentication checks      │
│                           ├─ Rate limiting              │
│                           ├─ Access logging             │
│                           └─ Routes to 127.0.0.1:port   │
│                                                         │
│ Services unreachable from network:                      │
│  ├─ 127.0.0.1:9200 → Elasticsearch (localhost only)    │
│  ├─ 127.0.0.1:6379 → Redis (localhost only)            │
│  ├─ 127.0.0.1:8065 → Mattermost (localhost only)       │
│  └─ 127.0.0.1:3000 → Grafana (localhost only)          │
│                                                         │
│ Attacker CANNOT bypass Traefik - services not on net   │
└─────────────────────────────────────────────────────────┘
```

### Defense-in-Depth Benefits

**Single Point of Security Enforcement**:

- TLS configured once (Traefik), not per-service
- Authentication policy centralized
- Rate limiting applied uniformly
- Access logs in one place
- Security updates to one component (Traefik) vs many services

**Attack Surface Reduction**:

- 1 port exposed externally (8443) instead of 8+ ports
- 1 TLS implementation to audit instead of 8+ different implementations
- Services cannot be accidentally exposed (must be localhost)
- Misconfiguration of one service doesn't expose it

**Forced Architecture**:

- Developers cannot bypass proxy (services not on network)
- New services inherit proxy security automatically
- Cannot forget to enable TLS (Traefik handles it)
- Consistent security model across all services

**The Trade-off is Worth It**: Loss of network flexibility in exchange for guaranteed proxy enforcement and centralized security.

---

## Architectural Implications

### 1. Port Management Critical

**Problem**: Port conflicts on single interface

```bash
# Port registry required (from CLAUDE.md)
Service         Port   Note
─────────────────────────────────────────
elasticsearch   9200   HTTP API
redis           6379   Default
influxdb3       8087   Changed from 8181 (Redis conflict)
mattermost      8065   Default
grafana         3000   Default
minio           9000   API, 9001 Console
gitea           3001   Changed from 3000 (Grafana conflict)
hashivault      8200   Default
traefik         8080   HTTP, 8443 HTTPS
```

**Solution**: Strict port coordination, centralized registry

### 2. Security Relies on Port Access Control

**Cannot use**:
- Interface-based firewall rules
- Network segmentation
- Separate routing tables

**Must use**:
- Application-level authentication
- Port-based access control (iptables on localhost)
- Process-level isolation (systemd, SELinux)

### 3. External Access Requires Proxy

**Direct external binding not possible**:
```yaml
# ❌ Cannot expose directly to internet
ports:
  - "0.0.0.0:8065:8065"  # FAILS
```

**Solution: Traefik reverse proxy**:
```yaml
# ✅ Two-tier architecture
Traefik (privileged/rootful):
  - "8080:8080"    # HTTP (privileged port via special setup)
  - "8443:8443"    # HTTPS
  → Proxies to localhost services

Services (rootless):
  - "127.0.0.1:8065:8065"  # Mattermost
  - "127.0.0.1:9200:9200"  # Elasticsearch
  → Only accessible via Traefik externally
```

See [TLS-Architecture-Decision.md](TLS-Architecture-Decision.md) for full details.

---

## Container-to-Container Networking

### Internal Network: ct-net

Services communicate via **ct-net** (Podman bridge network):

```bash
# Network creation
podman network create ct-net

# DNS resolution between containers
ping elasticsearch-svc  # Works inside ct-net
ping redis-svc          # Works inside ct-net
```

**Key properties**:
- Containers reference each other by name
- Internal DNS resolution
- No exposure to host network
- Traffic never leaves container network namespace

```yaml
# Example: Grafana connecting to InfluxDB
[Container]
Environment=INFLUXDB_URL=http://influxdb3-svc:8086
Network=ct-net
```

**This internal networking is independent of host binding constraints.**

---

## Why This Architecture Still Works

### Advantages Despite Constraints

**1. Localhost is Fast**
- No network stack overhead
- Kernel shortcuts for lo interface
- Minimal latency

**2. Simple Security Model**
- Services not exposed externally by default
- Explicit proxy required for external access
- Clear separation: internal (fast) vs external (secure)

**3. Development Friendly**
- Easy testing: `curl http://127.0.0.1:9200`
- No firewall configuration during development
- Port forwards work without privilege

**4. Traefik Provides Missing Features**
- SSL/TLS termination (Let's Encrypt)
- External routing
- URL-based routing (not just ports)
- Single entry point for security scanning

### Trade-offs Accepted

| Feature | Ideal | Actual | Impact |
|---------|-------|--------|--------|
| **Network Segmentation** | Per-service interfaces | Single localhost | Low - application-level auth compensates |
| **Port Flexibility** | Any port, any interface | Localhost only, coordinated ports | Low - registry prevents conflicts |
| **External Access** | Direct binding | Via proxy | None - Traefik adds value (TLS, routing) |
| **Firewall Rules** | Per-interface | Per-port on localhost | Medium - less granular control |

---

## Comparison: Rootful vs Rootless Networking

### Rootful Podman/Docker

```yaml
# Full network control
ports:
  - "8080:80"              # Can bind to any interface
  - "192.168.1.100:80:80"  # Can bind to specific IP
  - "0.0.0.0:443:443"      # Can bind to all interfaces

capabilities:
  - CAP_NET_BIND_SERVICE   # Can use privileged ports
  - CAP_NET_ADMIN          # Can modify network config
```

**Security**: Runs as root, container escape = root access

### Rootless Podman

```yaml
# Restricted network access
ports:
  - "127.0.0.1:8080:80"    # Localhost only
  - "127.0.0.1:9443:443"   # High ports only (or sysctl change)

capabilities:
  - (none on host network)  # User namespace isolation
```

**Security**: Runs as user, container escape = user access (not root)

**Trade-off**: Network flexibility for security isolation

---

## Workarounds and Alternatives

### Option 1: Rootful Traefik (Current Solution)

```yaml
# Traefik runs with privilege to bind :8443
# Services run rootless on localhost
# Traefik proxies localhost → external
```

**Pros**: Services stay rootless, Traefik isolated
**Cons**: One component requires privilege

### Option 2: socat/systemd Socket Activation

```bash
# Systemd listens on privileged port, forwards to rootless service
[Socket]
ListenStream=80
[Service]
ExecStart=/usr/bin/socat - TCP:127.0.0.1:8080
```

**Pros**: Granular per-port privilege
**Cons**: Complex configuration, many systemd units

### Option 3: IP Forwarding Rules

```bash
# iptables NAT to forward external → localhost
iptables -t nat -A PREROUTING -p tcp --dport 80 \
  -j DNAT --to-destination 127.0.0.1:8080
```

**Pros**: Works at kernel level
**Cons**: Requires root, complex to manage, debugging difficult

### Option 4: VPN/Tunneling

```bash
# WireGuard or SSH tunneling to expose services
ssh -L 8080:localhost:8080 user@host
```

**Pros**: Secure remote access
**Cons**: Not suitable for production external access

**Verdict**: Rootful Traefik proxy (Option 1) is cleanest solution.

---

## Developer Mental Model

### Understanding the Constraints

**Think of rootless containers as "localhost-only citizens":**

```
┌──────────────────────────────────────────────────────┐
│  Host System (your user)                             │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  Localhost (127.0.0.1)                         │ │
│  │                                                │ │
│  │  ┌──────────────────────────────────────────┐ │ │
│  │  │  Rootless Container Ecosystem            │ │ │
│  │  │  - All services bind here                │ │ │
│  │  │  - Port-based isolation only             │ │ │
│  │  │  - Fast, simple, secure                  │ │ │
│  │  └──────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  External Network (eth0, etc.)                 │ │
│  │  - Requires privilege to bind                  │ │
│  │  - Traefik gateway handles this               │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

**Rules**:
1. Services can ONLY bind to 127.0.0.1
2. Container-to-container via ct-net (internal DNS)
3. External access MUST go through privileged proxy (Traefik)
4. Port conflicts resolved via central registry

---

## Troubleshooting Network Issues

### Symptom: "Port already in use"

```bash
# Check what's using the port
ss -tlnp | grep :9200
lsof -i :9200

# Check Podman port allocations
podman port --all

# Review port registry
grep "Port" docs/CLAUDE.md
```

### Symptom: "Cannot bind to 0.0.0.0"

**Error**: `rootlessport cannot expose privileged port`

**Fix**: Change to 127.0.0.1 binding

```yaml
# Before
ports:
  - "9200:9200"

# After
ports:
  - "127.0.0.1:9200:9200"
```

### Symptom: "Service not accessible externally"

**Expected**: Rootless services are localhost-only

**Solution**: Configure Traefik labels

```yaml
# Add to quadlet
Label=traefik.enable=true
Label=traefik.http.routers.myservice.rule=Host(`myservice.example.com`)
Label=traefik.http.services.myservice.loadbalancer.server.port=9200
```

### Symptom: "Container can't reach other container"

**Check**: Both on ct-net?

```bash
# Verify network membership
podman inspect elasticsearch-svc | grep -A 5 Networks
podman inspect grafana-svc | grep -A 5 Networks

# Test DNS resolution
podman exec grafana-svc ping elasticsearch-svc
```

---

## Best Practices

### 1. Always Bind to 127.0.0.1 Explicitly

```yaml
# ✅ Explicit (good)
PublishPort=127.0.0.1:9200:9200

# ⚠️  Implicit (can fail on some systems)
PublishPort=9200:9200
```

### 2. Maintain Central Port Registry

Keep `docs/port-registry.md` or section in `CLAUDE.md` updated:

```markdown
| Service       | Port | Protocol | Note              |
|---------------|------|----------|-------------------|
| elasticsearch | 9200 | HTTP     | API               |
| redis         | 6379 | TCP      | Default           |
| influxdb3     | 8087 | HTTP     | Metrics (was 8181)|
```

### 3. Use Traefik for External Access

```yaml
# Don't try to expose directly
# Let Traefik handle external routing
Label=traefik.enable=true
Label=traefik.http.routers.svc.rule=Host(`svc.example.com`)
```

### 4. Container Communication via ct-net

```yaml
# Use service names, not localhost
Environment=DB_HOST=postgresql-svc
Environment=CACHE_HOST=redis-svc

# NOT this:
Environment=DB_HOST=127.0.0.1  # Wrong - references host, not container
```

### 5. Document Why localhost-only

```yaml
# In role defaults/main.yml
# Port bindings restricted to localhost (rootless container constraint)
# External access via Traefik reverse proxy
elasticsearch_host: "127.0.0.1"
elasticsearch_port: 9200
```

---

## The WireGuard Exception: Network Segmentation Opportunity

### Current Network Interfaces

This system has **multiple network interfaces** with different security contexts:

```bash
# Check interfaces
ip addr show

# Example output:
# eth0: 192.168.1.100/24  (local LAN - untrusted)
# wg0:  10.10.0.2/24      (WireGuard VPN - trusted peers only)
# lo:   127.0.0.1         (localhost - current service binding)
```

### The Opportunity: WireGuard Interface Binding

**WireGuard provides a trusted network context** that could be used for service segmentation:

```yaml
# Option: Bind services to WireGuard interface
# Services accessible ONLY to WireGuard peers, not local LAN

PublishPort=10.10.0.2:9200:9200    # Elasticsearch on WireGuard
PublishPort=10.10.0.2:6379:6379    # Redis on WireGuard
PublishPort=10.10.0.2:3000:3000    # Grafana on WireGuard
```

**Benefits**:

- Network segmentation achieved (wg0 vs eth0)
- Services not exposed to untrusted LAN
- No Traefik needed for WireGuard peers
- Access control via WireGuard peer configuration
- Direct service access for remote collectors

**Use Cases**:

- Remote monitoring agents (Telegraf, Alloy) pushing to InfluxDB/Loki
- Trusted remote access without Traefik overhead
- Service mesh across WireGuard peers
- Separation: localhost (dev), wg0 (production collectors), eth0 (blocked)

### Why This Wasn't Done (Yet)

**DNS Complexity**:

- Traefik routes by hostname (`grafana.example.com`), not IP
- Would need DNS resolution: `grafana.example.com` → `10.10.0.2` for WireGuard peers
- Different DNS views: local (`127.0.0.1`) vs remote (`10.10.0.2`)

**Split-brain DNS Required**:

```text
┌─────────────────────────────────────────────────────┐
│ Local queries (from host):                          │
│   grafana.example.com → 127.0.0.1:3000              │
│                                                     │
│ WireGuard peer queries:                             │
│   grafana.example.com → 10.10.0.2:3000              │
│                                                     │
│ External queries (via Traefik):                     │
│   grafana.example.com → <public-ip>:8443           │
│   (Traefik proxies to 127.0.0.1:3000)              │
└─────────────────────────────────────────────────────┘
```

**Current State**: All services on `127.0.0.1`, WireGuard used only for monitoring data collection (InfluxDB, Loki receiving metrics/logs from remote Alloy/Telegraf)

**Potential Future**: Bind services to `10.10.0.2` (WireGuard), set up split-horizon DNS, achieve true network segmentation

### How to Implement WireGuard Binding

**1. DNS Configuration** (Critical step):

```bash
# Option A: Split-horizon DNS
# - Local DNS server returns 127.0.0.1 for local queries
# - Local DNS server returns 10.10.0.2 for WireGuard peer queries
# - External DNS returns public IP (Traefik)

# Option B: Different domains
# - grafana.lan.example.com → 127.0.0.1 (local)
# - grafana.vpn.example.com → 10.10.0.2 (WireGuard)
# - grafana.example.com → public IP (Traefik)
```

**2. Change Port Bindings**:

```yaml
# In quadlet templates (.pod.j2)
# Current:
PublishPort=127.0.0.1:{{ service_port }}:{{ container_port }}

# WireGuard option:
PublishPort=10.10.0.2:{{ service_port }}:{{ container_port }}

# Or bind to both:
PublishPort=127.0.0.1:{{ service_port }}:{{ container_port }}
PublishPort=10.10.0.2:{{ service_port }}:{{ container_port }}
```

**3. Firewall Rules** (WireGuard interface):

```bash
# Allow traffic on WireGuard interface
firewall-cmd --zone=trusted --add-interface=wg0 --permanent

# Or selective per-service
firewall-cmd --zone=trusted --add-port=9200/tcp --permanent  # InfluxDB
firewall-cmd --zone=trusted --add-port=3100/tcp --permanent  # Loki
```

**4. Update Traefik Labels** (if keeping Traefik for external):

```yaml
# Traefik can still proxy to 127.0.0.1 or 10.10.0.2
Label=traefik.http.services.grafana.loadbalancer.server.url=http://10.10.0.2:3000
```

### WireGuard Segmentation Architecture

**Proposed Multi-Interface Setup**:

```text
┌─────────────────────────────────────────────────────────┐
│ External Network (eth0: 192.168.1.100)                  │
│  └─ :8443 → Traefik (HTTPS public access)              │
│             └─ Routes to 127.0.0.1 OR 10.10.0.2         │
│                                                         │
│ WireGuard VPN (wg0: 10.10.0.2/24) - TRUSTED PEERS      │
│  ├─ :8086 → InfluxDB (remote Telegraf collectors)      │
│  ├─ :3100 → Loki (remote Alloy log shippers)           │
│  ├─ :3000 → Grafana (trusted remote users)             │
│  └─ :9200 → Elasticsearch (trusted apps)               │
│                                                         │
│ Localhost (lo: 127.0.0.1) - LOCAL DEV                   │
│  ├─ Same services for local testing                     │
│  └─ Or only non-production services                     │
└─────────────────────────────────────────────────────────┘
```

**Benefits**:

- **Network segmentation achieved**: wg0 (trusted) vs eth0 (untrusted)
- **Access control via WireGuard peer config**: Only allowed peers can reach services
- **Performance**: No Traefik overhead for WireGuard peers
- **Flexibility**: Different services on different interfaces based on trust level

**Complexity**:

- DNS must resolve correctly for each network context
- More complex firewall rules
- Need to manage WireGuard peer configurations
- Testing becomes more involved (local vs VPN vs external)

---

## If You Wanted External Interface Binding (Not Recommended)

### What You'd Need to Change

**1. Podman Network Mode**:

Check current mode and consider pasta:

```bash
# Current: netavark (Fedora 43 default)
podman info | grep networkBackend

# Switch to pasta (if desired)
# Edit ~/.config/containers/containers.conf
[network]
default_rootless_network_cmd = "pasta"
```

**pasta advantages**: No NAT, copies host IPs, simpler external binding

**2. Port Configuration in Quadlets**:

```ini
# Current (localhost-only)
[Pod]
PublishPort=127.0.0.1:9200:9200

# External binding options
PublishPort=0.0.0.0:9200:9200         # All interfaces
PublishPort=192.168.1.100:9200:9200   # Specific IP
```

**3. Privileged Ports (<1024)**:

If you need ports like 80/443 without Traefik:

```bash
# Allow unprivileged binding to ports <1024
sudo sysctl net.ipv4.ip_unprivileged_port_start=80
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-unprivileged-ports.conf
```

**4. Firewall Configuration**:

```bash
# Would need per-service firewall rules
firewall-cmd --add-port=9200/tcp --permanent  # Elasticsearch
firewall-cmd --add-port=6379/tcp --permanent  # Redis
# ... etc for each service
```

**5. Security Considerations**:

- Each service needs TLS configuration
- Each service needs authentication
- Each service needs rate limiting
- Cannot guarantee proxy enforcement
- Larger attack surface

### Why This Isn't Recommended

**Security**: Bypassing Traefik removes centralized security

**Complexity**: Managing TLS, auth, and firewall rules per-service

**Consistency**: Different services might have different security models

**Maintenance**: Updates to 8+ TLS configs vs 1 Traefik config

**Risk**: Accidental service exposure (forgot firewall rule, misconfigured TLS, etc.)

### When It Might Make Sense

**Use Cases for External Binding**:

- Single-service deployments (only running Gitea, for example)
- High-performance requirements (avoiding proxy overhead)
- Network segmentation more important than unified security
- Advanced routing scenarios (different services on different networks)

**Better Alternative**: Multiple Proxmox VMs with one service per VM, each with own IP, managed by orchestration layer.

---

## Key Takeaways

1. **Modern Podman CAN bind rootless containers to external interfaces** (netavark/pasta support it)
2. **This architecture CHOOSES localhost-only** for security (forces Traefik proxy usage)
3. **Trade-off**: Network flexibility lost, security and simplicity gained
4. **All services share 127.0.0.1 namespace** - port management critical
5. **Traefik cannot be bypassed** - services literally not on network
6. **ct-net handles container-to-container** - internal network independent of host binding
7. **WireGuard interface (wg0) provides network segmentation opportunity** - trusted peers could access services directly on 10.10.0.x, but requires DNS configuration

**Bottom Line**: Localhost-only is a deliberate security choice that forces all external access through a managed proxy. It's not ideal from a network architecture perspective (no segmentation on primary interfaces), but it provides strong security guarantees. The WireGuard interface offers an opportunity for network segmentation with trusted peers, but the DNS complexity has kept that option unexplored. For this use case (development/lab environment with multiple services), the current trade-off is acceptable.

---

## References

### Official Documentation

- [Podman Network Documentation](https://docs.podman.io/en/stable/markdown/podman-network.1.html) - Network configuration options
- [Pasta - Plug A Simple Socket Transport](https://passt.top/passt/about/) - Alternative network mode
- [Use Pasta Networking with Podman on Oracle Linux](https://docs.oracle.com/en/learn/ol-podman-pasta-networking/) - Pasta networking guide
- [Red Hat: Communicating Among Containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_communicating-among-containers_building-running-and-managing-containers) - Container networking patterns
- [Configuring container networking with Podman](https://www.redhat.com/en/blog/container-networking-podman) - Network configuration deep dive

### Community Resources

- [eriksjolund/podman-networking-docs](https://github.com/eriksjolund/podman-networking-docs) - Rootless Podman networking examples
- [Podman Discussion #24823: Host-to-rootless connections](https://github.com/containers/podman/discussions/24823) - Best practices discussion
- [Podman Issue #22771: Pasta host-service ports](https://github.com/containers/podman/issues/22771) - Pasta networking challenges
- [Podman 5.3 Enhanced Rootless Networking](https://linuxiac.com/podman-5-3-promises-an-enhanced-rootless-networking/) - Recent improvements

### This Project Documentation

- [TLS-Architecture-Decision.md](TLS-Architecture-Decision.md) - Why Traefik handles external access
- [Podman-User-Namespaces.md](Podman-User-Namespaces.md) - UID/GID mapping details
- [Container-Role-Architecture.md](Container-Role-Architecture.md) - Overall design patterns

---

## Document History

- 2026-01-28: Initial documentation explaining localhost-only constraint and architectural implications
- Audience: Developers and AI tools (ref.tools) understanding why network segmentation isn't possible
