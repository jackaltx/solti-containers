# Clauge debug help

I'll create a list of useful Traefik debugging commands, focusing on the API endpoints that help diagnose routing and configuration issues.

## Traefik API Debugging Commands

### Router Information

```bash
# List all routers and their configurations
curl http://localhost:9000/api/http/routers | jq .

# Get specific router details
curl http://localhost:9000/api/http/routers/your-router-name@docker | jq .
```

### Service Information

```bash
# List all services
curl http://localhost:9000/api/http/services | jq .

# Get specific service details
curl http://localhost:9000/api/http/services/your-service-name@docker | jq .
```

### Middleware Information

```bash
# List all middlewares
curl http://localhost:9000/api/http/middlewares | jq .

# Get specific middleware details
curl http://localhost:9000/api/http/middlewares/your-middleware-name@docker | jq .
```

### Entry Points Status

```bash
# List all entrypoints
curl http://localhost:9000/api/entrypoints | jq .
```

### Provider Information

```bash
# Get Docker provider information
curl http://localhost:9000/api/providers/docker | jq .

# List all providers
curl http://localhost:9000/api/providers | jq .
```

### TLS Information

```bash
# Get TLS configurations
curl http://localhost:9000/api/http/routers?search=tls | jq .

# Check TLS certificates
curl http://localhost:9000/api/tls/certificates | jq .
```

### Health and Version

```bash
# Health check
curl http://localhost:9000/api/health | jq .

# Version information
curl http://localhost:9000/api/version | jq .

# Ping test
curl http://localhost:9000/api/ping
```

### Real-time Monitoring

```bash
# Get overview of all HTTP requests
curl http://localhost:9000/api/overview | jq .

# Get current configuration
curl http://localhost:9000/api/rawdata | jq .
```

### Debug Headers

```bash
# Test routing with specific headers
curl -H "Host: your-domain.com" http://localhost:8080 -v
```

Would you like me to expand on any of these categories or add more specific debugging scenarios?
