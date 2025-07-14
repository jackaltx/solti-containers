# Traefik Development SSL Proxy Role

## 🎯 **Purpose**

This Traefik role provides **centralized SSL termination** for development environments, making it easy to test applications with real HTTPS certificates during development.

**Why use this instead of individual SSL per app?**

- ✅ **Centralized certificate management** - Let's Encrypt handles all SSL
- ✅ **Automatic renewals** - No manual certificate updates
- ✅ **Real SSL testing** - Test with actual HTTPS instead of self-signed
- ✅ **Simple service integration** - Just add labels to containers
- ✅ **Production-like routing** - Simulate real deployment scenarios

## ⚠️ **Development Focus**

While this provides real SSL certificates, it's optimized for **development ease**:

- Dashboard is publicly accessible (insecure mode)
- No rate limiting or advanced security features
- Single-container deployment (not HA)
- Simplified configuration for quick setup

## 🏗️ **How It Works**

```
Internet → Your Domain → Traefik → Your Apps
                          ↓
                    Let's Encrypt
                    (Real SSL Certs)
```

1. **Container Discovery**: Traefik discovers your services via Podman labels
2. **Automatic SSL**: Let's Encrypt provides real certificates via DNS challenge
3. **Routing**: Traffic gets automatically routed to the right service with HTTPS

## 🌐 **DNS Setup Required**

You need a **real domain** with DNS hosted at a supported provider:

### **Linode DNS (Default)**

```bash
# Set your API token
export LINODE_TOKEN="your_linode_api_token"

# Point wildcard DNS to your dev machine
*.yourdomain.com → 192.168.1.100
```

### **Other Providers**

Traefik supports 100+ DNS providers. Update `traefik.yaml.j2` to change provider.

## 🚀 **Quick Start**

### **1. Prepare**

```bash
./manage-svc.sh traefik prepare
```

### **2. Deploy**

```bash
./manage-svc.sh traefik deploy
```

### **3. Verify Setup**

```bash
# Quick connectivity test
./svc-exec.sh traefik test

# Full verification with routing details
./svc-exec.sh traefik verify

# Diagnostic mode (detailed API inspection)
./svc-exec.sh traefik verify1
```

## 🔍 **Verification Commands**

### **`./svc-exec.sh traefik test`**

Quick health check - just verifies API is responding:

```
✅ Traefik API responding
Dashboard: http://localhost:9999
Version: 3.3.3
```

### **`./svc-exec.sh traefik verify`**

Standard verification - shows routing and connectivity:

```
🚀 TRAEFIK STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
API: ✅ ONLINE
Routes: 8
Services: 6

redis-ui.yourdomain.com ➜ redis
mattermost.yourdomain.com ➜ mattermost

🔗 CONNECTIVITY TESTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
redis-ui.yourdomain.com ➜ ✅ 200
mattermost.yourdomain.com ➜ 🔒 401
```

### **`./svc-exec.sh traefik verify1`**

Diagnostic mode - detailed API structure inspection for troubleshooting.

## 🏷️ **Service Configuration**

Add these labels to your service containers:

```yaml
quadlet_options:
  - "Label=traefik.enable=true"
  - "Label=traefik.http.routers.myservice.rule=Host(`myservice.{{ domain }}`)"
  - "Label=traefik.http.routers.myservice.entrypoints=websecure"
  - "Label=traefik.http.routers.myservice.service=myservice"
  - "Label=traefik.http.services.myservice.loadbalancer.server.port=8080"
  - "Label=traefik.http.routers.myservice.middlewares=secHeaders@file"
```

**Result**: `https://myservice.yourdomain.com` → your container port 8080

## 🔧 **Ports Used**

| Port | Purpose | Access | Note |
|------|---------|---------|------|
| 8080 | HTTP/HTTPS | `0.0.0.0:8080` | Main traffic port |
| 8443 | HTTPS Alt | `0.0.0.0:8443` | Alternative HTTPS |
| 9999 | Dashboard | `127.0.0.1:9999` | Management UI |

## 🛠️ **Troubleshooting**

### **No Routes Showing**

```bash
# Check if containers have proper labels
podman inspect myservice | jq '.Config.Labels'

# Verify Traefik can discover containers
./svc-exec.sh traefik verify1
```

### **SSL Certificate Issues**

```bash
# Check ACME logs
podman logs traefik-svc | grep -i acme

# Verify DNS provider token
echo $LINODE_TOKEN

# Check certificate storage
ls -la ~/traefik-data/acme/
```

### **Connectivity Problems**

```bash
# Test specific route
curl -H 'Host: myservice.yourdomain.com' http://localhost:8080

# Check Traefik dashboard
open http://localhost:9999
```

## 🌟 **Example Integration**

With Redis Commander:

```yaml
# In redis role quadlet
- "Label=traefik.enable=true"
- "Label=traefik.http.routers.redis.rule=Host(`redis-ui.{{ domain }}`)"
- "Label=traefik.http.routers.redis.service=redis"
- "Label=traefik.http.services.redis.loadbalancer.server.port=8081"
```

**Result**: Redis Commander gets automatic HTTPS at `https://redis-ui.yourdomain.com`

## 🔄 **Cleanup**

```bash
# Remove Traefik (keep certificates)
./manage-svc.sh traefik remove

# Remove everything including certificates
TRAEFIK_DELETE_DATA=true ./manage-svc.sh traefik remove
```

## 🎁 **What You Get**

- ✅ **Real HTTPS** for all your development services
- ✅ **Automatic certificate renewal** via Let's Encrypt
- ✅ **Easy service discovery** via container labels
- ✅ **Production-like testing** with real SSL
- ✅ **Clean verification tools** to monitor status
- ✅ **Simple troubleshooting** with diagnostic commands

Perfect for testing web applications, APIs, and microservices that need HTTPS during development!
