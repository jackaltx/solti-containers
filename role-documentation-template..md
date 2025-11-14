# [SERVICE_NAME] Role - [Brief Description]

## Purpose

[Explain why this service exists in your testing workflow - what problem it solves, how it fits into development cycles]

## Quick Start

```bash
# Set required environment variables (if any)
export SERVICE_PASSWORD="your_secure_password"

# Prepare system directories and configuration
./manage-svc.sh [service] prepare

# Deploy [service] with [additional components]
./manage-svc.sh [service] deploy

# [Any initial setup tasks]
./svc-exec.sh [service] initialize

# Verify deployment and functionality
./svc-exec.sh [service] verify

# Clean up (preserves data by default)
./manage-svc.sh [service] remove
```

> **Note**: `manage-svc.sh` will prompt for your sudo password. This is required because containers create files with elevated ownership that your user cannot modify without privileges.

## Features

- **[Primary Feature]**: [Description]
- **[Secondary Feature]**: [Description]
- **[Integration Feature]**: [Description]
- **SSL Integration**: Automatic HTTPS via Traefik
- **[Security Feature]**: [Description]
- **[Management Feature]**: [Description]

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Your Apps     │───▶│   [SERVICE]      │◀───│   [GUI/ADMIN]       │
│   ([Protocol])  │    │   ([Main Port])  │    │   ([GUI Port])      │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                              │                           │
                              └───────────────────────────┘
                                           │
                              ┌──────────────────────┐
                              │       Traefik        │
                              │   (SSL Termination)  │
                              └──────────────────────┘
                                           │
                              https://[service].yourdomain.com
```

## Access Points

| Interface | URL | Purpose |
|-----------|-----|---------|
| [Service] API | `http://localhost:[PORT]` | [Purpose] |
| [GUI/Admin] | `http://localhost:[GUI_PORT]` | [Purpose] |
| SSL Endpoint | `https://[service].{{ domain }}` | Traefik-proxied HTTPS access |

## Configuration

### Required Environment Variables

```bash
# [Service] requires [description]
export [SERVICE]_PASSWORD="your_secure_password_here"
```

### Key Configuration Options

```yaml
# Container settings
[service]_image: "docker.io/[image]:[tag]"
[service]_port: [PORT]                        # [Purpose]
[service]_gui_port: [GUI_PORT]               # [Purpose]

# Security settings
[service]_password: "{{ lookup('env', '[SERVICE]_PASSWORD') | default('changeme') }}"

# Data persistence
[service]_data_dir: "{{ ansible_facts.user_dir }}/[service]-data"

# [Category] settings
[service]_[setting]: "[value]"               # [Description]
```

### Optional [Feature] Configuration

```yaml
# Enable [feature] for [purpose]
[service]_enable_[feature]: true
[service]_[feature]_cert_file: "/path/to/cert.pem"
[service]_[feature]_key_file: "/path/to/key.pem"
```

## Using with Traefik SSL

[Service] automatically integrates with Traefik for SSL termination:

```yaml
# Traefik labels automatically applied
- "Label=traefik.http.routers.[service].rule=Host(`[service].{{ domain }}`)"
- "Label=traefik.http.services.[service].loadbalancer.server.port=[PORT]"
```

**Result**: Access [Service] securely at `https://[service].yourdomain.com`

## [Initial Setup/Configuration Section]

### [Setup Task Name]

```bash
# [Description of what this does]
./svc-exec.sh [service] [task-name]
```

This process:

1. [Step 1]
2. [Step 2]
3. [Step 3]
4. [Final result]

## Common Operations

### Verification and Testing

```bash
# Basic health and functionality check
./svc-exec.sh [service] verify

# [Specific test description]
./svc-exec.sh [service] [test-task]

# [Another test description]
./svc-exec.sh [service] [another-task]
```

### [Service] Operations

```bash
# [Common operation description]
[command example]

# [Another operation description]
[command example]

# [Third operation description]
[command example]
```

### [Management Category] Operations

```bash
# [Management task description]
podman exec [service]-svc [command]

# [Another management task]
podman exec [service]-svc [command]
```

## Integration Examples

### [Integration Type 1]

```python
import [library]

# [Description of integration]
client = [library].[Client](
    host='localhost',
    port=[PORT],
    password='your_password'
)

# [Example operation]
result = client.[operation]([parameters])

# [Example usage]
[usage_example]
```

### [Integration Type 2]

```bash
# [Description of integration]
curl -X POST https://[service].yourdomain.com/api/[endpoint] \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "[field]": "[value]",
    "[field2]": "[value2]"
  }'
```

### [Integration Type 3]

```yaml
# [Configuration file example]
[service]:
  host: "[service].yourdomain.com"
  port: [PORT]
  credentials:
    username: "[username]"
    password: "[password]"
```

## [Advanced Feature Section]

### [Advanced Feature 1]

```bash
# [Description]
[command examples]
```

### [Advanced Feature 2]

```yaml
# [Configuration example]
[service]_[feature]:
  - [option1]: [value1]
  - [option2]: [value2]
```

## Monitoring and Maintenance

### Health Monitoring

```bash
# Container status
systemctl --user status [service]-pod

# Resource usage
podman stats [service]-svc

# [Service] specific health check
curl http://localhost:[PORT]/[health-endpoint]
```

### Log Analysis

```bash
# [Service] application logs
podman logs [service]-svc | grep -i error

# [Additional log source]
podman logs [service]-[component]

# Real-time monitoring
podman logs -f [service]-svc
```

### Performance Monitoring

```bash
# [Performance metric 1]
[command]

# [Performance metric 2]
[command]

# [Performance analysis]
[command]
```

## Development Workflows

### Development [Use Case]

```bash
# Deploy for [purpose]
export [SERVICE]_PASSWORD="dev_secure_password"
./manage-svc.sh [service] deploy
./svc-exec.sh [service] initialize

# [Development task]
[task commands]

# [Testing task]
[test commands]

# Clean up when done
./manage-svc.sh [service] remove
```

### Testing [Workflow]

```bash
# Quick test deployment
./manage-svc.sh [service] deploy

# [Test operations]
[test commands]

# [Verification]
./svc-exec.sh [service] verify

# Clean up
./manage-svc.sh [service] remove
```

## Troubleshooting

### Common Issues

**[Issue Type 1]**

```bash
# [Diagnostic command]
[command]

# [Solution command]
[command]
```

**[Issue Type 2]**

```bash
# [Check command]
[command]

# [Fix command]
[command]
```

**[Issue Type 3]**

```bash
# [Verification command]
[command]

# [Resolution steps]
[commands]
```

### [Troubleshooting Category]

```bash
# [Diagnostic description]
[diagnostic commands]

# [Resolution description]
[resolution commands]
```

## Security Best Practices

1. **[Security Point 1]**: [Description and recommendation]
2. **[Security Point 2]**: [Description and recommendation]
3. **[Security Point 3]**: [Description and recommendation]
4. **HTTPS Only**: Use Traefik SSL termination for production access
5. **[Service-Specific Security]**: [Description and recommendation]

## Related Services

- **[Service 1]**: [How it relates and integrates]
- **[Service 2]**: [How it relates and integrates]
- **Traefik**: Provides SSL termination and routing
- **HashiVault**: Can store [service] passwords and configuration

## License

MIT

## Maintained By

Jackaltx - Part of the SOLTI containers collection for development testing workflows.

---

## Template Usage Notes

### Customization Guidelines

1. **Replace all [PLACEHOLDERS]** with service-specific information
2. **Remove sections** that don't apply to your service
3. **Add sections** for service-specific features
4. **Update architecture diagram** to reflect actual service topology
5. **Customize integration examples** to show realistic usage

### Common Sections to Customize

- **Purpose**: Explain the specific problem this service solves
- **Architecture**: Update ports, components, and data flow
- **Configuration**: Add service-specific environment variables and settings
- **Integration Examples**: Show real code for your service's API/protocols
- **Troubleshooting**: Include actual issues you've encountered
- **Security**: Address service-specific security considerations

### Optional Sections

Add these if relevant to your service:

- **Backup and Restore** (for data services)
- **Clustering/High Availability** (for distributed services)
- **Plugin Management** (for extensible services)
- **Import/Export** (for configuration management)
- **Monitoring Integration** (for services with metrics)

### Testing Your README

1. Follow the Quick Start section exactly as written
2. Verify all commands work as documented
3. Test integration examples with real code
4. Validate troubleshooting steps solve actual problems
5. Ensure security recommendations are implementable
