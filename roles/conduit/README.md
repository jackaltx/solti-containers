# Conduit Role

Deploys Conduit Matrix homeserver as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **Conduit** (`matrixconduit/matrix-conduit:latest`) - Lightweight Matrix homeserver written in Rust

## Features

- **Lightweight**: Minimal resource usage compared to Synapse
- **Fast**: Rust-based implementation for high performance
- **Federation**: Connect with other Matrix servers
- **Matrix Protocol**: Full Matrix client-server API support
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management
- **Traefik Support**: Optional SSL termination and reverse proxy
- **RocksDB Backend**: Efficient embedded database

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role
- Domain name for Matrix federation (optional but recommended)

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh conduit prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
./manage-svc.sh conduit deploy
```

Deploys and starts the Conduit homeserver.

### 3. Verify

```bash
./svc-exec.sh conduit verify
```

Runs health checks and functional tests.

### 4. Access

- **Matrix Client**: Configure client to connect to `http://localhost:6167`
- **Server Name**: Your domain (e.g., `a0a0.org`)
- **With Traefik SSL**: `https://matrix.a0a0.org:8080`

## Configuration

### Inventory Variables

```yaml
# Server configuration
conduit_server_name: "{{ domain }}"  # Your Matrix domain
conduit_data_dir: "{{ lookup('env', 'HOME') }}/conduit-data"
conduit_port: 6167

# Registration settings
conduit_allow_registration: false  # Disable public registration
conduit_registration_token: ""     # Optional: require token for registration

# Federation
conduit_allow_federation: true     # Enable federation with other Matrix servers

# Database
conduit_database_backend: "rocksdb"  # Embedded database
conduit_max_request_size: 20000000   # 20MB max upload

# Traefik integration
conduit_enable_traefik: true
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/conduit-data/
├── config/          # Conduit configuration files
│   └── conduit.toml
└── data/            # RocksDB database files (persistent)
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status conduit-pod

# Start service
systemctl --user start conduit-pod

# Stop service
systemctl --user stop conduit-pod

# Restart service
systemctl --user restart conduit-pod

# Enable on boot
systemctl --user enable conduit-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u conduit-pod -f

# View container logs
podman logs conduit-svc

# View last 50 lines
podman logs --tail 50 conduit-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh conduit remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh conduit remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status conduit-pod

# Check container logs
podman logs conduit-svc

# Test Matrix client API
curl http://localhost:6167/_matrix/client/versions

# Test federation API (if enabled)
curl http://localhost:6167/_matrix/federation/v1/version

# Run verification tasks
./svc-exec.sh conduit verify
```

## User Registration

Conduit does not have a built-in registration tool. Users must be created via the Matrix client-server API or by enabling open registration.

### Option 1: Enable Registration with Token

```yaml
conduit_allow_registration: true
conduit_registration_token: "your_secure_token_here"
```

Users will need to provide the registration token when signing up.

### Option 2: Use Matrix Client

Use Element or another Matrix client:

1. Point client to `http://localhost:6167` (or your Traefik URL)
2. Create account (if registration enabled)
3. Start messaging

### Option 3: Admin API

After at least one user exists, you can make them an admin by modifying the database. See [Conduit documentation](https://docs.conduit.rs/) for details.

## Traefik Integration

When Traefik is deployed with `conduit_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

```bash
# Wildcard DNS: *.domain → your_host
# Example: *.a0a0.org → firefly.a0a0.org
```

2. Access via HTTPS:
   - Client endpoint: `https://matrix.a0a0.org:8080`
   - Server name: `a0a0.org`

### Well-Known Delegation

For federation to work properly, you may need to set up `.well-known` delegation:

```yaml
conduit_well_known_client: "https://matrix.{{ domain }}"
conduit_well_known_server: "matrix.{{ domain }}:443"
```

This allows clients to discover your homeserver at `matrix.yourdomain.com` when users use `@user:yourdomain.com` as their Matrix ID.

## Federation

To enable federation with other Matrix servers:

1. Ensure `conduit_allow_federation: true` in inventory
2. Configure trusted servers (default includes matrix.org):

```yaml
conduit_trusted_servers:
  - "matrix.org"
  - "other-server.com"
```

3. Ensure port 8448 is reachable (if required by your federation setup)
4. Configure proper DNS/TLS for your domain

## TURN Server Configuration

For voice/video calls, configure a TURN server:

```yaml
conduit_turn_uris:
  - "turn:turn.example.com?transport=udp"
  - "turn:turn.example.com?transport=tcp"
conduit_turn_secret: "your_turn_secret"
```

## Advanced Usage

### Custom Configuration

Edit the configuration template at [templates/conduit.toml.j2](templates/conduit.toml.j2) for advanced settings.

### Database Maintenance

Conduit uses RocksDB which generally requires minimal maintenance:

```bash
# Check database size
du -sh ~/conduit-data/data/

# Database is automatically compacted by RocksDB
```

### Resource Monitoring

```bash
# Monitor container resources
podman stats conduit-svc

# Check memory usage
podman exec conduit-svc ps aux
```

## Troubleshooting

### Issue: Cannot Connect to Homeserver

**Problem**: Client cannot reach Conduit

**Detection:**

```bash
# Check if Conduit is running
podman ps | grep conduit

# Check port binding
ss -tlnp | grep 6167

# Test endpoint
curl http://localhost:6167/_matrix/client/versions
```

**Resolution**: Ensure Conduit container is running and port is correctly bound

```bash
systemctl --user status conduit-pod
podman logs conduit-svc
```

### Issue: Federation Not Working

**Problem**: Cannot federate with other Matrix servers

**Detection:**

```bash
# Check federation endpoint
curl http://localhost:6167/_matrix/federation/v1/version

# Check logs for federation errors
podman logs conduit-svc | grep -i federation
```

**Resolution**:
- Verify `conduit_allow_federation: true`
- Check DNS configuration for your domain
- Ensure proper SSL/TLS setup via Traefik
- Verify firewall allows federation traffic

### Issue: Registration Disabled

**Problem**: Cannot create new accounts

**Resolution**: Enable registration in inventory:

```yaml
conduit_allow_registration: true
# Optionally require token:
conduit_registration_token: "secure_token_here"
```

Then redeploy:

```bash
./manage-svc.sh conduit deploy
```

### Issue: Database Corruption

**Problem**: Conduit fails to start with database errors

**Detection:**

```bash
podman logs conduit-svc
```

**Resolution**:
- Stop the service
- Backup `~/conduit-data/data/`
- Remove corrupted database: `rm -rf ~/conduit-data/data/*`
- Restart service (starts with fresh database)

**Note**: This removes all users, rooms, and messages!

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml
conduit_svc:
  hosts:
    podma:
      conduit_svc_name: "matrix-podma"
  vars:
    conduit_port: 6167
    conduit_server_name: "podma.example.com"

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml conduit prepare
./manage-svc.sh -h podma -i inventory/podma.yml conduit deploy
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

**Component Architecture:**

```text
┌─────────────────┐    ┌──────────────────┐
│  Matrix Client  │───▶│     Conduit      │
│  (Element, etc) │    │   (Port 6167)    │
└─────────────────┘    └──────────────────┘
                              │
                       ┌──────────────────┐
                       │     Traefik      │
                       │  (SSL Termination)│
                       └──────────────────┘
                              │
                  https://matrix.a0a0.org:8080
```

See [docs/Claude-new-quadlet.md](../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- Ports bind to `127.0.0.1` by default (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- Disable public registration (`conduit_allow_registration: false`) in production
- Use registration tokens when registration is enabled
- Federation requires proper TLS configuration

## Performance Characteristics

Conduit is designed to be lightweight:

- **Memory**: ~50-100MB typical usage
- **CPU**: Minimal when idle, scales with user activity
- **Storage**: RocksDB database grows with message history

Compared to Synapse:
- ~10x less memory usage
- Faster startup time
- More efficient resource utilization

## Links

- [Conduit Official Documentation](https://docs.conduit.rs/)
- [Conduit GitHub Repository](https://github.com/timokoesters/conduit)
- [Matrix Protocol Specification](https://spec.matrix.org/)
- [Docker Hub Image](https://hub.docker.com/r/matrixconduit/matrix-conduit)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs conduit-svc`
2. Systemd logs: `journalctl --user -u conduit-pod`
3. Verification output: `./svc-exec.sh conduit verify`

For Conduit application issues, consult the [official documentation](https://docs.conduit.rs/).

## Related Services

- **Traefik**: Provides SSL termination and routing for Conduit
- **HashiVault**: Can store Conduit credentials and registration tokens
- **Coturn**: TURN server for voice/video calls (deploy separately)

## Migration Notes

### From Synapse

Conduit is not directly compatible with Synapse databases. Migration requires:

1. Export users/rooms from Synapse
2. Set up fresh Conduit installation
3. Re-invite users to rooms
4. Rooms will need to be re-federated

### Database Persistence

The RocksDB database is stored in `~/conduit-data/data/` and persists across:
- Container restarts
- Role redeployments
- System reboots

Only deleted when using `DELETE_DATA=true` during removal.
