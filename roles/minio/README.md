# MinIO Role

Deploys MinIO S3-compatible object storage as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **MinIO Server** (`minio/minio:latest`) - S3-compatible object storage
- **MinIO Console** (built-in web UI) - Browser-based management interface

## Features

- **S3 API Compatibility**: Drop-in replacement for Amazon S3
- **Web Console**: Built-in browser interface for bucket management
- **MinIO Client (mc)**: Command-line tool for bucket operations
- **Rootless Containers**: Enhanced security with user-level Podman
- **Systemd Integration**: Native service management
- **Traefik Support**: SSL termination and reverse proxy
- **Upgrade Detection**: Built-in check for image updates
- **Development Focused**: Perfect for testing S3 integrations
- **HashiVault Integration**: Optional credential storage

## Requirements

- Podman installed and configured for rootless operation
- User systemd services enabled (`loginctl enable-linger`)
- Container network (`ct-net`) created by `_base` role

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh minio prepare
```

Creates directories, applies SELinux contexts, and configures the system.

### 2. Deploy

```bash
# Set MinIO credentials (recommended)
export MINIO_ROOT_USER="admin"
export MINIO_ROOT_PASSWORD="your_secure_password"

./manage-svc.sh minio deploy
```

Deploys and starts the service with MinIO server and console.

### 3. Verify

```bash
./svc-exec.sh minio verify
```

Runs health checks and functional tests.

### 4. Access

- **MinIO API**: `http://localhost:9000` (S3-compatible endpoint)
- **MinIO Console**: `http://localhost:9001` (web interface)
- **With Traefik SSL**:
  - API: `https://minio-svc.example.com:8080`
  - Console: `https://minio-ui.example.com:8080`

## Configuration

### Environment Variables

```bash
export MINIO_ROOT_USER="admin"                  # MinIO admin username (default: minioadmin)
export MINIO_ROOT_PASSWORD="your_secure_pass"   # MinIO admin password (default: changeme)
export USE_VAULT=true                           # Enable HashiVault integration (optional)
```

### Inventory Variables

```yaml
# Data and ports
minio_data_dir: "{{ lookup('env', 'HOME') }}/minio-data"
minio_api_port: 9000
minio_console_port: 9001

# Service configuration
minio_image: "docker.io/minio/minio:latest"
minio_root_user: "{{ lookup('env', 'MINIO_ROOT_USER') | default('minioadmin') }}"
minio_root_password: "{{ lookup('env', 'MINIO_ROOT_PASSWORD') | default('changeme') }}"
minio_browser: "on"

# TLS configuration
minio_enable_tls: false
minio_tls_cert_file: ""  # Path relative to config dir
minio_tls_key_file: ""   # Path relative to config dir

# Traefik integration
minio_enable_traefik: true
minio_api_domain: "{{ minio_api_svc_name }}.{{ domain }}"
minio_console_domain: "{{ minio_console_svc_name }}.{{ domain }}"
```

See [defaults/main.yml](defaults/main.yml) for complete options.

## Directory Structure

After deployment:

```text
~/minio-data/
├── config/          # MinIO configuration files
├── data/            # Object storage data (persistent)
├── tls/             # TLS certificates (if enabled)
└── logs/            # MinIO server logs
```

## Service Management

### Start/Stop/Status

```bash
# Check service status
systemctl --user status minio-pod

# Start service
systemctl --user start minio-pod

# Stop service
systemctl --user stop minio-pod

# Restart service
systemctl --user restart minio-pod

# Enable on boot
systemctl --user enable minio-pod
```

### Logs

```bash
# View pod logs
journalctl --user -u minio-pod -f

# View container logs
podman logs minio-svc

# View last 50 lines
podman logs --tail 50 minio-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh minio remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh minio remove
```

## Verification

Manual verification:

```bash
# Check service status
systemctl --user status minio-pod

# Check container logs
podman logs minio-svc

# Test MinIO health endpoint
curl http://localhost:9000/minio/health/live

# Run verification tasks
./svc-exec.sh minio verify
```

### MinIO Client Operations

```bash
# Configure MinIO client and create test bucket
./svc-exec.sh minio configure

# Manual mc operations (after configure)
podman exec minio-svc mc alias list
podman exec minio-svc mc ls local
podman exec minio-svc mc mb local/test-bucket
podman exec minio-svc mc cp /etc/hosts local/test-bucket/
```

## Upgrade Management

### Check for Updates

```bash
# Check if new container image version is available
./svc-exec.sh minio check_upgrade
```

**Output when updates available:**

```text
TASK [minio : Display container status]
ok: [firefly] => {
    "msg": "minio-svc:UPDATE AVAILABLE - Current: abc123 | Latest: def456"
}

TASK [minio : Summary of upgrade status]
ok: [firefly] => {
    "msg": "UPDATES AVAILABLE for: minio-svc"
}
```

**Output when up-to-date:**

```text
TASK [minio : Display container status]
ok: [firefly] => {
    "msg": "minio-svc:Up to date (abc123)"
}

TASK [minio : Summary of upgrade status]
ok: [firefly] => {
    "msg": "All containers up to date"
}
```

### Perform Upgrade

When updates are available:

```bash
# 1. Remove current deployment
./manage-svc.sh minio remove

# 2. Redeploy with latest image
./manage-svc.sh minio deploy

# 3. Verify new version
./svc-exec.sh minio verify
```

**Note**: Data in `~/minio-data/` persists across upgrades.

## Traefik Integration

When Traefik is deployed with `minio_enable_traefik: true`, the service automatically gets SSL termination.

### DNS Configuration

1. Update DNS to point to your host:

   ```bash
   source ~/.secrets/LabProvision
   ./update-dns-auto.sh firefly
   ```

   This creates:
   - `minio-svc.example.com` → `firefly.example.com` (API endpoint)
   - `minio-ui.example.com` → `firefly.example.com` (Console)

2. Access via HTTPS:
   - API: `https://minio-svc.example.com:8080`
   - Console: `https://minio-ui.example.com:8080`

## Advanced Usage

### S3 API Integration Examples

**Python (boto3):**

```python
import boto3

# Configure S3 client for MinIO
s3 = boto3.client('s3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id='admin',
    aws_secret_access_key='your_secure_password',
    region_name='us-east-1'
)

# Create bucket
s3.create_bucket(Bucket='test-data')

# Upload file
s3.upload_file('/path/to/file.txt', 'test-data', 'file.txt')

# List objects
response = s3.list_objects_v2(Bucket='test-data')
for obj in response.get('Contents', []):
    print(f"  {obj['Key']} - {obj['Size']} bytes")

# Download file
s3.download_file('test-data', 'file.txt', '/tmp/downloaded.txt')
```

**AWS CLI:**

```bash
# Configure AWS CLI for MinIO
aws configure set aws_access_key_id admin
aws configure set aws_secret_access_key your_secure_password
aws configure set default.region us-east-1

# Use with --endpoint-url flag
aws --endpoint-url http://localhost:9000 s3 ls
aws --endpoint-url http://localhost:9000 s3 mb s3://my-bucket
aws --endpoint-url http://localhost:9000 s3 cp file.txt s3://my-bucket/
```

### Bucket Management with mc Client

**After running `./svc-exec.sh minio configure`:**

```bash
# List buckets
podman exec minio-svc mc ls local

# Create bucket with versioning
podman exec minio-svc mc mb local/versioned-bucket
podman exec minio-svc mc version enable local/versioned-bucket

# Set bucket quota
podman exec minio-svc mc admin quota local/test-bucket --hard 10GB

# Mirror directory to bucket
podman exec minio-svc mc mirror /data/source local/backup-bucket

# Get bucket statistics
podman exec minio-svc mc stat local/test-bucket

# Set bucket policy (public read)
podman exec minio-svc mc policy set download local/public-bucket
```

### Development Workflows

**Test Data Storage:**

```bash
# Start MinIO for testing
./manage-svc.sh minio deploy
./svc-exec.sh minio configure

# Run tests that use S3 API
python test_s3_integration.py

# Inspect data via console
open http://localhost:9001

# Clean up when done
./manage-svc.sh minio remove
```

**Loki Log Storage Backend:**

```yaml
# Configure Loki to use MinIO for storage
storage_config:
  aws:
    endpoint: http://minio-svc:9000
    bucketnames: loki-chunks
    access_key_id: admin
    secret_access_key: your_secure_password
    s3forcepathstyle: true
```

### Performance Tuning

**Resource Limits:**

Add to quadlet configuration:

```yaml
quadlet_options:
  - |
    [Container]
    Memory=1G
    CPUQuota=200%
```

**Erasure Coding (Production):**

For production deployments with multiple drives:

```bash
# Set MINIO_VOLUMES to multiple paths
minio_volumes: "/data1 /data2 /data3 /data4"
```

## Troubleshooting

### Issue: Connection Refused

**Problem**: Cannot connect to MinIO on ports 9000/9001

**Detection:**

```bash
# Check if MinIO is running
podman ps | grep minio

# Check port binding
ss -tlnp | grep 9000
ss -tlnp | grep 9001
```

**Resolution**: Ensure MinIO container is running and ports are correctly bound

```bash
systemctl --user status minio-pod
podman logs minio-svc
```

### Issue: Authentication Errors

**Problem**: Access denied or invalid credentials

**Detection:**

```bash
# Verify credentials are set
echo $MINIO_ROOT_USER
echo $MINIO_ROOT_PASSWORD

# Test API endpoint
curl -I http://localhost:9000/minio/health/live
```

**Resolution**: Set credentials before deployment

```bash
export MINIO_ROOT_USER="admin"
export MINIO_ROOT_PASSWORD="your_secure_password"
./manage-svc.sh minio deploy
```

### Issue: Bucket Access Errors

**Problem**: Cannot access buckets or objects

**Detection:**

```bash
# Check MinIO server logs
podman logs minio-svc | grep -i error

# Test with mc client
podman exec minio-svc mc ls local
```

**Resolution**: Verify bucket policies and credentials

```bash
# List buckets and permissions
podman exec minio-svc mc admin policy list local

# Set appropriate policy
podman exec minio-svc mc policy set public local/my-bucket
```

### Issue: Console Not Loading

**Problem**: MinIO console returns errors or won't load

**Detection:**

```bash
# Check console redirect URL
curl -I http://localhost:9001

# Check browser redirect configuration
podman exec minio-svc printenv | grep BROWSER
```

**Resolution**: Verify `minio_browser_redirect_url` is correct

```yaml
minio_browser_redirect_url: "https://{{ minio_console_domain }}:{{ traefik_http_port }}"
```

## Remote Host Deployment

Deploy to remote hosts using specific inventory:

```bash
# Add to inventory/podma.yml with unique service name
minio_svc:
  hosts:
    podma:
      minio_svc_name: "minio-podma"
  vars:
    minio_api_port: 9000
    minio_console_port: 9001

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml minio prepare
./manage-svc.sh -h podma -i inventory/podma.yml minio deploy
```

## Architecture

This role follows the SOLTI container pattern:

1. **_base role inheritance**: Common functionality (directories, network, cleanup)
2. **Podman quadlets**: Declarative container-to-systemd integration
3. **State-based flow**: prepare → present → absent
4. **Dynamic playbook generation**: Single script handles all operations

**Component Architecture:**

```text
┌─────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│   S3 Clients    │───▶│   MinIO Server   │◀───│  MinIO Console   │
│  (boto3, AWS)   │    │   (Port 9000)    │    │   (Port 9001)    │
└─────────────────┘    └──────────────────┘    └──────────────────┘
                              │                         │
                              └─────────────────────────┘
                                       │
                              ┌──────────────────┐
                              │     Traefik      │
                              │  (SSL Termination)│
                              └──────────────────┘
                                       │
                      https://minio-svc.example.com:8080 (API)
                      https://minio-ui.example.com:8080 (Console)
```

See [docs/Claude-new-quadlet.md](../docs/Claude-new-quadlet.md) for complete pattern documentation.

## Security Considerations

- Containers run rootless under your user account
- API and Console ports bind to `127.0.0.1` only (not publicly accessible)
- SELinux contexts applied automatically on RHEL-based systems
- Traefik provides SSL termination for external access
- Strong credentials required (deployment fails with default password)
- HashiVault integration available for credential management
- TLS can be enabled for direct connections (`minio_enable_tls: true`)
- Bucket policies control object access permissions

## Links

- [MinIO Official Documentation](https://min.io/docs/minio/linux/index.html)
- [MinIO Docker Hub Image](https://hub.docker.com/r/minio/minio)
- [MinIO Client (mc) Documentation](https://min.io/docs/minio/linux/reference/minio-mc.html)
- [AWS S3 API Compatibility](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
- [Podman Documentation](https://docs.podman.io/)
- [Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

## Support

For issues specific to this role, check:

1. Container logs: `podman logs minio-svc`
2. Systemd logs: `journalctl --user -u minio-pod`
3. Verification output: `./svc-exec.sh minio verify`
4. Health endpoint: `curl http://localhost:9000/minio/health/live`

For MinIO application issues, consult the [official documentation](https://min.io/docs/).

## Related Services

- **Loki**: Can use MinIO as log storage backend
- **InfluxDB**: Can use MinIO for data persistence
- **Traefik**: Provides SSL termination and routing for API/Console
- **HashiVault**: Can store MinIO credentials and access keys
- **Elasticsearch**: Alternative object storage for snapshots
