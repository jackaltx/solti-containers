# Traefik Development Proxy Role

## ⚠️ **Development Use Only**

This Traefik role is designed for **development and testing environments** to provide SSL termination for containerized services. It is **NOT intended for production use**.

## 🎯 **Purpose**

Provides a reverse proxy with automatic SSL certificates so you can:

- Access your development services with HTTPS
- Test SSL-enabled applications locally
- Simulate production-like routing without complex setup
- Get valid SSL certificates for development domains

## 🏗️ **How It Works**

1. **Traefik** runs as a container and discovers other containers via Podman labels
2. **Let's Encrypt** provides real SSL certificates via DNS challenge
3. **DNS Provider** (Linode/Cloudflare) handles the ACME challenge
4. **Services** get automatic HTTPS routing based on container labels

## 🌐 **DNS Setup Required**

### **Prerequisites**

You need a **real domain** with DNS hosted at a supported provider:

- **Linode** (default in this role)
- **Cloudflare**
- Other providers (requires config changes)

### **Example Setup**

If you own `mydomain.com`:

1. **Point wildcard DNS** to your development machine:

   ```
   *.mydomain.com → 192.168.1.100  (your dev machine IP)
   ```

2. **Set environment variable**:

   ```bash
   export LINODE_TOKEN="your_linode_api_token"
   ```

3. **Update inventory**:

   ```yaml
   domain: mydomain.com
   ```

## 🚀 **Quick Start**

### **1. Prepare**

```bash
./manage-svc.sh traefik prepare
```

### **2. Deploy**

```bash
./manage-svc.sh traefik deploy
```

### **3. Test Dashboard**

```bash
# Access Traefik dashboard
open http://localhost:9999
```

## 🔍 **Testing & Verification**

### **Dashboard Access**

- **URL**: `http://localhost:9999`
- **What to check**:
  - HTTP Routers showing your services
  - Services showing healthy backends
  - TLS certificates being issued

### **Test Service Routing**

```bash
# Test if your services are routed correctly
curl -H "Host: myservice.mydomain.com" http://localhost:8080 -v

# Should redirect to HTTPS:
curl -H "Host: myservice.mydomain.com" https://localhost:8080 -v
```

### **Check Certificate Status**

```bash
# View ACME certificates
ls -la ~/traefik-data/acme/

# Check certificate details in dashboard
open http://localhost:9999
```

## 🏷️ **Service Configuration**

Your services need these Podman labels to work with Traefik:

```yaml
quadlet_options:
  - "Label=traefik.enable=true"
  - "Label=traefik.http.routers.myservice.rule=Host(`myservice.{{ domain }}`)"
  - "Label=traefik.http.routers.myservice.entrypoints=websecure"
  - "Label=traefik.http.routers.myservice.service=myservice"
  - "Label=traefik.http.services.myservice.loadbalancer.server.port=8080"
  - "Label=traefik.http.routers.myservice.middlewares=secHeaders@file"
```

## 🔧 **Ports Used**

| Port | Purpose | Access |
|------|---------|---------|
| 8080 | HTTP/HTTPS traffic | `0.0.0.0:8080` |
| 8443 | HTTPS traffic (alt) | `0.0.0.0:8443` |
| 9999 | Traefik Dashboard | `127.0.0.1:9999` |

## 🛠️ **Troubleshooting**

### **No SSL Certificates**

```bash
# Check ACME logs
podman logs traefik-svc | grep -i acme

# Verify DNS provider token
echo $LINODE_TOKEN

# Check DNS resolution
nslookup myservice.mydomain.com
```

### **Service Not Appearing**

```bash
# Check container labels
podman inspect myservice-container | jq '.[] | .Config.Labels'

# Verify network connectivity
podman exec traefik-svc ping myservice-container
```

### **Dashboard API**

```bash
# Check all routers
curl http://localhost:9999/api/http/routers | jq .

# Check specific service
curl http://localhost:9999/api/http/services | jq .
```

## ⚡ **DNS Provider Setup**

### **Linode** (Default)

1. Get API token from Linode Cloud Manager
2. Set environment: `export LINODE_TOKEN="your_token"`

### **Cloudflare** (Alternative)

1. Get Global API Key from Cloudflare dashboard
2. Modify `traefik.yaml.j2`:

   ```yaml
   dnsChallenge:
     provider: cloudflare
   ```

3. Set environment: `export CF_API_EMAIL="you@example.com"` and `export CF_API_KEY="your_key"`

## 🚫 **What This Role Doesn't Do**

- **Production security** - Dashboard is insecure, no rate limiting
- **High availability** - Single container deployment
- **Monitoring** - No metrics or alerting
- **Backup** - No certificate backup strategy
- **User management** - No authentication on services

## 🔄 **Cleanup**

```bash
# Remove Traefik (keep certificates)
./manage-svc.sh traefik remove

# Remove everything including certificates
TRAEFIK_DELETE_DATA=true ./manage-svc.sh traefik remove
```

## 🤝 **Integration**

Works with other roles in this collection:

- **Elasticsearch** → `https://elasticsearch.mydomain.com`
- **Mattermost** → `https://mattermost.mydomain.com`
- **MinIO** → `https://minio.mydomain.com`
- **Vault** → `https://vault.mydomain.com`

Each service automatically gets SSL when properly labeled.
