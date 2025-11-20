# Molecule Podman Testing for solti-containers

## Overview

This molecule scenario enables **nested container testing** - deploying container services inside test containers. This allows comprehensive integration testing of the solti-containers roles in isolated environments.

## Architecture

```
Host System (your workstation)
  └─ Molecule Test Container (Debian12/Rocky9/Ubuntu24) [privileged]
      └─ Podman (installed via solti-ensemble.podman role)
          └─ Service Containers (traefik, hashivault, redis, etc.) [rootless]
```

### Key Components

1. **Test Containers**: Privileged systemd containers with SSH
   - `uut-ct0`: Debian 12 (port 2223)
   - `uut-ct1`: Rocky 9 (port 2224)
   - `uut-ct2`: Ubuntu 24 (port 2225)

2. **Podman Installation**: Uses `jackaltx.solti_ensemble.podman` role in prepare phase

3. **Service Deployment**: Converge phase deploys selected services using existing roles

4. **Verification**: Each service's `verify.yml` tasks are executed

## Usage

### Basic Testing

```bash
# Test redis and traefik on all platforms (default)
./run-podman-tests.sh

# Test specific services
./run-podman-tests.sh --services "traefik,hashivault"

# Test on specific platform
./run-podman-tests.sh --platform uut-ct0 --services redis

# Test hashivault with full workflow (unseal, write, read, seal)
./run-podman-tests.sh --services hashivault --platform uut-ct0
```

### Advanced Options

```bash
# Debug mode (show credentials in logs)
MOLECULE_SECURE_LOGGING=false ./run-podman-tests.sh --services hashivault

# Test specific platform only
MOLECULE_PLATFORM_NAME=uut-ct1 molecule test -s podman

# Skip destroy (keep containers for debugging)
molecule converge -s podman
molecule verify -s podman
# ... debug ...
molecule destroy -s podman
```

## Service Configuration

Services are defined in [molecule/vars/services.yml](../vars/services.yml):

```yaml
container_services:
  hashivault:
    roles:
      - hashivault
    required_packages:
      Debian: [podman, systemd, ...]
    verify_role_tasks:
      hashivault:
        - verify.yml
    service_names:
      - hashivault-pod
    service_ports:
      - 8200
```

## How It Works

### 1. Prepare Phase
- Creates test directories
- Installs podman via `jackaltx.solti_ensemble.podman`
- Installs service-specific packages
- Sets up systemd in test container

### 2. Converge Phase
- Loads service definitions from `services.yml`
- Maps `MOLECULE_SERVICES` env var to roles
- Includes roles dynamically (e.g., `redis` → `roles/redis`)
- Enables loginctl linger for user persistence

### 3. Verify Phase
- Runs `roles/<service>/tasks/verify.yml` for each service
- Checks service ports, systemd status
- Executes service-specific tests (e.g., vault unseal/seal)
- Generates report

## Example: Testing HashiVault

```bash
./run-podman-tests.sh --services hashivault --platform uut-ct0
```

This will:
1. Spin up Debian 12 test container
2. Install podman inside it
3. Deploy HashiVault using `roles/hashivault`
4. Run verification tasks:
   - Unseal vault
   - Write test keys
   - Read test keys
   - Seal vault
   - Verify seal status

## Troubleshooting

### View test logs
```bash
tail -f verify_output/latest_test.out
```

### Debug specific service
```bash
# Deploy and keep running
molecule converge -s podman

# SSH into test container
ssh -p 2223 jackaltx@127.0.0.1

# Check service status
systemctl --user status hashivault-pod
podman ps
podman logs hashivault-svc
```

### Common Issues

1. **Podman not found**: Ensure `solti-ensemble` collection is installed
   ```bash
   ansible-galaxy collection list | grep solti_ensemble
   ```

2. **Port conflicts**: Check if ports 2223-2225 are available
   ```bash
   ss -tlnp | grep 222
   ```

3. **Container registry auth**: Ensure `LAB_DOMAIN` is set
   ```bash
   source ~/.secrets/LabProvision
   echo $LAB_DOMAIN
   ```

## Integration with CI/CD

The `molecule/github` scenario uses GitHub container registry. The `molecule/podman` scenario uses your local gitea registry (configured via `LAB_DOMAIN`).

## Files Structure

```
molecule/
├── podman/
│   ├── molecule.yml          # Scenario definition
│   └── README.md             # This file
├── shared/
│   ├── podman/
│   │   ├── prepare.yml       # Install podman + deps
│   │   ├── converge.yml      # Deploy services
│   │   ├── create.yml
│   │   └── destroy.yml
│   └── verify/
│       ├── main.yml          # Verification orchestration
│       └── verify-service.yml # Per-service verification
├── vars/
│   └── services.yml          # Service definitions
└── github/                   # GitHub CI scenario
```

## Related Documentation

- [Container Role Architecture](../../docs/Container-Role-Architecture.md)
- [SOLTI Pattern](../../docs/Solti-Container-Pattern.md)
- [solti-monitoring molecule setup](../../../solti-monitoring/molecule/podman/)
