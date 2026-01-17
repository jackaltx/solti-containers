# Molecule Testing for SOLTI Containers

Quick start guide for testing container service roles.

## Quick Start

```bash
# Test redis and traefik on all platforms (default)
./run-podman-tests.sh

# Test specific services
./run-podman-tests.sh --services "redis,hashivault"

# Test on specific platform
./run-podman-tests.sh --platform uut-deb12 --services redis

# Test all available services
./run-podman-tests.sh --services "redis,traefik,hashivault,mattermost,minio,grafana,elasticsearch"
```

## What Gets Tested

Each test run validates:

1. **Service deployment** - Container and pod creation
2. **Service health** - Systemd status, container logs
3. **Network connectivity** - ct-net network, DNS resolution
4. **Service functionality** - Service-specific verification tasks
5. **Port availability** - Configured ports are listening
6. **Multi-platform compatibility** - Debian 12, Rocky 9, Ubuntu 24

## Testing Scenarios

### Local Testing (podman scenario)

Tests services in nested containers using your local Gitea registry.

```bash
./run-podman-tests.sh --services redis
```

**What happens**:
- Spins up test containers (Debian 12, Rocky 9, Ubuntu 24)
- Installs Podman inside test containers
- Deploys your service using rootless containers
- Runs service-specific verification tasks
- Generates detailed reports in `verify_output/`

### CI Testing (github scenario)

Runs in GitHub Actions using GitHub Container Registry.

```bash
MOLECULE_SERVICES=redis molecule test -s github
```

Triggered automatically on pull requests.

## Available Services

Services defined in [vars/services.yml](vars/services.yml):

| Service | Description | Ports |
|---------|-------------|-------|
| redis | Key-value store + Commander GUI | 6379, 8081 |
| traefik | Reverse proxy with SSL | 8080, 443 |
| hashivault | Secrets management | 8200 |
| mattermost | Team collaboration | 8065 |
| minio | S3-compatible object storage | 9000, 9001 |
| grafana | Metrics visualization | 3000 |
| elasticsearch | Search and analytics | 9200 |

## Test Output

### During Test Run

```text
=== Molecule Test Configuration ===
Date: 2026-01-17 12:34:56
Services: redis,traefik
Platform: all
Test name: podman
================================

PLAY [Create] ******************
PLAY [Prepare] *****************
PLAY [Converge] ****************
PLAY [Verify] ******************
```

### After Test Completes

```bash
verify_output/
├── latest_test.out -> podman-test-20260117-123456.out
├── podman-test-20260117-123456.out
├── debian/
│   ├── consolidated_test_report.md
│   ├── container-diagnostics-preverify-*.yml
│   └── container-diagnostics-postverify-*.yml
├── rocky/
│   └── (same structure)
└── ubuntu/
    └── (same structure)
```

**View results**:

```bash
# Latest test output
tail -f verify_output/latest_test.out

# Consolidated report
cat verify_output/debian/consolidated_test_report.md

# Pre/post diagnostics comparison
diff verify_output/debian/container-diagnostics-preverify-*.yml \
     verify_output/debian/container-diagnostics-postverify-*.yml
```

## Adding Tests for New Services

### 1. Define Service in vars/services.yml

```yaml
container_services:
  myservice:
    roles:
      - myservice
    required_packages:
      Debian: [podman, systemd]
      RedHat: [podman, systemd]
    verify_role_tasks:
      myservice:
        - verify.yml
    service_names:
      - myservice-pod
    service_ports:
      - 8080
```

### 2. Create Verification Tasks

```yaml
# roles/myservice/tasks/verify.yml
---
- name: Check myservice is responding
  uri:
    url: http://localhost:8080/health
    status_code: 200
  register: health_check
  retries: 3
  delay: 5

- name: Verify myservice data directory
  stat:
    path: "{{ myservice_data_dir }}"
  register: data_dir
  failed_when: not data_dir.stat.exists
```

### 3. Test It

```bash
./run-podman-tests.sh --services myservice --platform uut-deb12
```

### 4. Add to CI

Edit `.github/workflows/test.yml`:

```yaml
strategy:
  matrix:
    service: [redis, traefik, myservice]  # Add here
```

## Advanced Usage

### Test Specific Platform Only

```bash
# Debian 12
./run-podman-tests.sh --platform uut-deb12 --services redis

# Rocky 9
./run-podman-tests.sh --platform uut-rocky9 --services redis

# Ubuntu 24
./run-podman-tests.sh --platform uut-ct2 --services redis
```

### Debug Mode (Show Credentials)

```bash
MOLECULE_SECURE_LOGGING=false ./run-podman-tests.sh --services hashivault
```

### Manual Test Phases

```bash
# Run phases separately (don't destroy between)
molecule create -s podman
molecule prepare -s podman
molecule converge -s podman
molecule verify -s podman

# SSH into test container for debugging
ssh -p 2223 jackaltx@127.0.0.1  # Debian 12
ssh -p 2224 jackaltx@127.0.0.1  # Rocky 9
ssh -p 2225 jackaltx@127.0.0.1  # Ubuntu 24

# Check service status inside container
systemctl --user status redis-pod
podman ps
podman logs redis-svc

# Cleanup
molecule destroy -s podman
```

### Environment Variables

Override defaults via environment variables:

```bash
# Test different services
MOLECULE_SERVICES="mattermost,minio" ./run-podman-tests.sh

# Target specific platform
MOLECULE_PLATFORM_NAME=uut-rocky9 molecule test -s podman

# Custom test name
MOLECULE_TEST_NAME=hashivault_full ./run-podman-tests.sh --services hashivault

# Disable secure logging (debug)
MOLECULE_SECURE_LOGGING=false molecule verify -s podman
```

## Troubleshooting

### Test Failures

**View detailed logs**:

```bash
tail -f verify_output/latest_test.out
```

**Common issues**:

1. **Port conflicts**: Ports 2223-2225 must be available
   ```bash
   ss -tlnp | grep 222
   ```

2. **Registry authentication**: Ensure LAB_DOMAIN is set
   ```bash
   source ~/.secrets/LabProvision
   echo $LAB_DOMAIN
   ```

3. **Podman role missing**: Install solti-ensemble collection
   ```bash
   ansible-galaxy collection install jackaltx.solti_ensemble
   ```

### Container Issues

**Check test container status**:

```bash
podman ps -a | grep uut
```

**View test container logs**:

```bash
podman logs uut-deb12
```

**Restart test containers**:

```bash
molecule destroy -s podman
molecule create -s podman
```

### Service-Specific Failures

**Check service logs inside test container**:

```bash
# SSH into test container
ssh -p 2223 jackaltx@127.0.0.1

# Check service
systemctl --user status redis-pod
journalctl --user -u redis-pod -n 50
podman logs redis-svc
```

**Verify service port is listening**:

```bash
ss -tlnp | grep 6379  # Redis example
```

## How It Works

### Architecture

```text
Host System
  └─ Test Containers (uut-deb12, uut-rocky9, uut-ct2) [privileged]
      └─ Podman (installed by prepare phase)
          └─ Service Containers (redis, traefik, etc.) [rootless]
```

### Test Flow

1. **Create**: Spin up test containers (Debian 12, Rocky 9, Ubuntu 24)
2. **Prepare**: Install Podman and service dependencies
3. **Converge**: Deploy services using their roles
4. **Verify**: Run diagnostics and service-specific verification
5. **Destroy**: Clean up test containers

### What Gets Verified

**Pre-verification diagnostics**:
- Container health (podman ps, logs)
- Network health (ct-net, DNS)
- Service health (systemd status)

**Service verification**:
- Executes `roles/<service>/tasks/verify.yml`
- Service-specific functional tests
- Port availability checks

**Post-verification diagnostics**:
- Same as pre-verification
- Enables comparison to detect issues

**Results**:
- Pass/fail per service
- Consolidated reports per platform
- Complete audit trail

## Infrastructure Documentation

**For users** (this file):
- How to run tests
- What gets tested
- How to add new services

**For developers** ([shared/README.md](shared/README.md)):
- Shared infrastructure implementation
- Verification matrix collection
- How playbooks work together
- Advanced debugging techniques

**For Podman scenario** ([podman/README.md](podman/README.md)):
- Nested container architecture
- Platform-specific details
- Container registry configuration

## Related Documentation

- [Container Role Architecture](../docs/Container-Role-Architecture.md) - SOLTI pattern overview
- [Claude New Quadlet Guide](../docs/Claude-new-quadlet.md) - Creating new service roles
- [_base Role Pattern](../roles/_base/Readme.md) - Shared deployment infrastructure

## Examples

### Test Before Commit

```bash
# Test the service you modified
./run-podman-tests.sh --services redis

# Review results
cat verify_output/latest_test.out
```

### Test Multi-Platform Compatibility

```bash
# Test on all platforms
./run-podman-tests.sh --services redis

# Check platform-specific results
ls verify_output/*/consolidated_test_report.md
```

### Test Service Integration

```bash
# Test services that work together
./run-podman-tests.sh --services "traefik,redis,hashivault"

# Verify they can communicate
ssh -p 2223 jackaltx@127.0.0.1
podman exec redis-svc ping traefik-svc  # Via ct-net DNS
```

### Debug Test Failure

```bash
# Run test with debug output
MOLECULE_SECURE_LOGGING=false ./run-podman-tests.sh --services hashivault

# Keep test container alive
molecule converge -s podman  # Don't destroy

# SSH in and debug
ssh -p 2223 jackaltx@127.0.0.1
systemctl --user status hashivault-pod
podman logs hashivault-svc

# Cleanup when done
molecule destroy -s podman
```

## Tips

1. **Start small**: Test one service on one platform first
2. **Check logs**: `verify_output/latest_test.out` has complete details
3. **Use debug mode**: Set `MOLECULE_SECURE_LOGGING=false` to see credentials
4. **Keep containers**: Use `molecule converge` to debug without destroying
5. **SSH for debugging**: Ports 2223-2225 provide direct container access
6. **Compare reports**: Diff pre/post diagnostics to spot issues
7. **Test before PR**: CI runs same tests, catch issues locally first
