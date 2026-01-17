# Molecule Shared Infrastructure

**Purpose**: Common testing infrastructure shared across `podman` and `github` molecule scenarios to eliminate duplication.

**This is developer documentation.** For user-facing testing guide, see [molecule/README.md](../README.md).

## Why This Exists

Similar to the `_base` role pattern for service deployment, this directory provides **shared testing infrastructure** used by multiple molecule scenarios. Instead of duplicating prepare/converge/verify logic in `molecule/podman/` and `molecule/github/`, the scenarios reference shared playbooks with scenario-specific `molecule.yml` configurations.

**Key Benefit**: Write test infrastructure once, use across all scenarios. Update diagnostics or verification logic in one place, applies to all testing scenarios.

## Pattern: Services Definition + Generic Playbooks

Service testing requirements are defined in `molecule/vars/services.yml`, and shared playbooks consume this data generically to install, deploy, and verify services.

**Example** (from molecule/vars/services.yml):

```yaml
container_services:
  redis:
    roles:
      - redis
    required_packages:
      Debian: [podman, systemd, ...]
    verify_role_tasks:
      redis:
        - verify.yml
    service_names:
      - redis-pod
    service_ports:
      - 6379
```

**Usage** (in molecule/podman/molecule.yml):

```yaml
provisioner:
  playbooks:
    prepare: ../shared/podman/prepare.yml
    converge: ../shared/podman/converge.yml
    verify: ../shared/verify/main.yml
```

The shared playbooks load `services.yml` and dynamically execute the appropriate roles and verification tasks.

## Directory Structure

```text
molecule/
├── shared/                    # Shared infrastructure (this directory)
│   ├── README.md             # This file
│   ├── podman/               # Podman-specific test playbooks
│   │   ├── prepare.yml       # Install podman, service deps
│   │   ├── converge.yml      # Deploy services dynamically
│   │   ├── create.yml        # (legacy/unused)
│   │   ├── destroy.yml       # (legacy/unused)
│   │   ├── systemd-Debian.yml  # Systemd setup for Debian-based
│   │   └── systemd-RedHat.yml  # Systemd setup for RHEL-based
│   ├── verify/               # Verification playbooks
│   │   ├── main.yml          # Orchestrates all verification
│   │   ├── verify-capability.yml   # Service capability checks
│   │   ├── verify-role-capability.yml  # Per-role verification
│   │   ├── verify-service.yml      # Per-service health checks
│   │   ├── verify-logs.yml         # Log analysis
│   │   ├── verify-metrics.yml      # Metrics validation
│   │   ├── verify-github.yml       # GitHub-specific checks
│   │   └── report.yml              # Generate test reports
│   └── diagnostics/          # Health check tasks
│       ├── main.yml          # Orchestrates diagnostics
│       ├── container-health.yml    # Container status checks
│       ├── network-health.yml      # Network connectivity
│       ├── service-health.yml      # Systemd service checks
│       └── report.yml              # Diagnostic reports
├── vars/
│   └── services.yml          # Service definitions (data)
├── podman/
│   ├── molecule.yml          # Podman scenario config
│   └── README.md             # Podman scenario docs
└── github/
    ├── molecule.yml          # GitHub CI scenario config
    └── converge.yml          # (minimal override)
```

## How Shared Playbooks Work

### 1. molecule/vars/services.yml - Data Definition

Central registry of all testable services with their requirements:

```yaml
container_services:
  <service_name>:
    roles: []                  # Ansible roles to include
    required_packages:         # OS-specific dependencies
      Debian: []
      RedHat: []
    verify_role_tasks:         # Verification tasks to run
      <role_name>:
        - verify.yml
    service_names: []          # Systemd service names
    service_ports: []          # Ports to verify
```

**Key fields**:
- `roles`: Which roles to execute during converge
- `required_packages`: OS-specific packages (podman, systemd, etc.)
- `verify_role_tasks`: Maps role name to verification task files
- `service_names`: Systemd units to check (e.g., "redis-pod")
- `service_ports`: Ports to verify are listening

### 2. shared/podman/prepare.yml - Environment Setup

Prepares test container environment:

**What it does**:
- Loads `services.yml` to get required packages
- Maps `MOLECULE_SERVICES` env var to package list
- Installs podman via `solti_ensemble.podman` collection role
- Installs service-specific dependencies
- Configures systemd inside test container (systemd-Debian.yml or systemd-RedHat.yml)
- Enables loginctl linger for rootless containers

**Environment variables**:
- `MOLECULE_SERVICES`: Comma-separated service names (e.g., "redis,traefik")
- `MOLECULE_PLATFORM_NAME`: Target platform (uut-deb12, uut-rocky9, etc.)

### 3. shared/podman/converge.yml - Service Deployment

Deploys services inside test container:

**What it does**:
- Loads `services.yml`
- Parses `MOLECULE_SERVICES` env var
- For each service, includes roles dynamically (`roles/<service>`)
- Sets up test-specific variables
- Executes service deployment (prepare → deploy)

**Dynamic role inclusion**:
```yaml
- name: Include roles for selected services
  include_role:
    name: "{{ item }}"
  loop: "{{ selected_services }}"
```

### 4. shared/verify/main.yml - Test Verification

Orchestrates all verification tasks:

**What it does**:
- Loads `services.yml`
- Runs diagnostics (`shared/diagnostics/main.yml`)
- Executes service capability checks (`verify-capability.yml`)
- Runs per-service verification (`verify-service.yml`)
- Validates logs (`verify-logs.yml`)
- Checks metrics if enabled (`verify-metrics.yml`)
- Generates test report (`report.yml`)

### 5. shared/verify/verify-service.yml - Per-Service Tests

Executes service-specific verification tasks:

**What it does**:
- For each service in `MOLECULE_SERVICES`
- Reads `verify_role_tasks` from `services.yml`
- Includes `roles/<service>/tasks/verify.yml`
- Validates systemd service status
- Checks port availability
- Runs service-specific tests (e.g., HashiVault unseal/seal)

**Example** (HashiVault verification):
```yaml
# From services.yml
verify_role_tasks:
  hashivault:
    - verify.yml

# Becomes:
- include_tasks: "{{ playbook_dir }}/../../roles/hashivault/tasks/verify.yml"
```

### 6. shared/diagnostics/ - Health Checks

Reusable health check tasks executed before verification:

**Modules**:
- `container-health.yml`: Checks podman ps, container logs
- `network-health.yml`: Validates ct-net, DNS resolution
- `service-health.yml`: Systemd service status
- `main.yml`: Orchestrates all diagnostics
- `report.yml`: Outputs diagnostic summary

## Environment Variables

Scenarios communicate with shared playbooks via environment variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `MOLECULE_SERVICES` | Services to test | `"redis,traefik,hashivault"` |
| `MOLECULE_PLATFORM_NAME` | Target platform | `uut-deb12`, `uut-rocky9` |
| `MOLECULE_SERIAL` | Parallel execution | `0` (all hosts), `1` (sequential) |
| `MOLECULE_SECURE_LOGGING` | Hide credentials | `true` (default), `false` (debug) |
| `IN_GITHUB_CI` | GitHub Actions mode | `true` in CI, `false` locally |

Set in scenario's `molecule.yml`:

```yaml
provisioner:
  env:
    MOLECULE_SERVICES: "redis,traefik"
```

Or override at runtime:

```bash
MOLECULE_SERVICES="hashivault" molecule test -s podman
```

## Benefits of Shared Infrastructure

1. **DRY**: Write prepare/converge/verify once, use in multiple scenarios
2. **Consistency**: All scenarios test the same way
3. **Maintainability**: Fix verification bug once, applies everywhere
4. **Extensibility**: Add new diagnostic → all scenarios get it
5. **Service Registry**: `services.yml` is single source of truth

## Adding a New Service

To add molecule testing for a new service:

**1. Define in services.yml**:

```yaml
container_services:
  myservice:
    roles:
      - myservice
    required_packages:
      Debian: [podman, systemd, package-for-myservice]
      RedHat: [podman, systemd, package-for-myservice]
    verify_role_tasks:
      myservice:
        - verify.yml
    service_names:
      - myservice-pod
    service_ports:
      - 8080
```

**2. Create verification tasks**:

```yaml
# roles/myservice/tasks/verify.yml
---
- name: Check myservice is responding
  uri:
    url: http://localhost:8080/health
    status_code: 200
```

**3. Test it**:

```bash
./run-podman-tests.sh --services myservice
```

No changes to shared playbooks needed!

## Scenario-Specific vs Shared

**Use shared/ when**:
- Logic applies to multiple scenarios
- Service definitions (services.yml)
- Generic prepare/converge/verify flows
- Reusable diagnostics

**Use scenario/ (podman/ or github/) when**:
- Scenario-specific configuration (molecule.yml)
- Platform-specific overrides
- Scenario documentation (README.md)

## Comparison to _base Role Pattern

| Aspect | _base Role | molecule/shared/ |
|--------|------------|------------------|
| **Purpose** | Service deployment | Service testing |
| **Data source** | `service_properties` | `services.yml` |
| **Inclusion** | `include_tasks` | `playbooks:` in molecule.yml |
| **Scope** | Production deployment | Test scenarios |
| **Variables** | Role defaults | Env vars + scenario config |

Both use the same pattern: **define what you need (data), shared code does how (logic)**.

## Verification Matrix Collection

**The Non-Trivial Part**: Test results are collected into a multi-dimensional matrix across services, platforms, and diagnostic stages.

### How It Works

**1. Initialize result dictionary** (verify/main.yml:80-83):

```yaml
- name: Initialize result for capability
  set_fact:
    all_verify_results: {}    # Stores all test outputs
    all_verify_failed: {}      # Tracks pass/fail status
```

**2. Collect pre-verification diagnostics** (verify/main.yml:86-90):

```yaml
- name: Run pre-verify container diagnostics
  include_tasks: "{{ project_root }}/molecule/shared/diagnostics/main.yml"
  vars:
    report_suffix: "preverify"
```

This runs:
- `container-health.yml` → Podman ps, logs, resource usage
- `service-health.yml` → Systemd status for each service
- `network-health.yml` → ct-net connectivity, DNS resolution
- `report.yml` → **Adds to `all_verify_results['preverify']`**

**3. Run per-service verification** (verify/main.yml:98-103):

```yaml
- name: Run service-specific verifications
  loop: "{{ testing_services }}"
  include_tasks: verify-service.yml
  loop_control:
    loop_var: service
```

For each service (redis, traefik, etc.):

- Includes `roles/<service>/tasks/verify.yml`
- Records result: `set_fact: "{{ service }}_verify_failed"`
- Continues even on failure (`ignore_errors: yes`)

**4. Collect post-verification diagnostics** (verify/main.yml:106-110):

Same as pre-verification but with `report_suffix: "postverify"` → **Adds to `all_verify_results['postverify']`**

**5. Create verification status map** (verify/main.yml:119-135):

```yaml
- name: Create verification status map
  set_fact:
    verification_status: "{{ verification_status | combine({
      service: hostvars[inventory_hostname][service + '_verify_failed']
    }) }}"
  loop: "{{ testing_services }}"

- name: Final verification check
  fail:
    msg: "Verifications failed: {{ failed_services }}"
  when: any service failed
```

**Result Matrix Structure**:

```yaml
all_verify_results:
  preverify: |
    === Container Diagnostic Report ===
    Container Health:
      redis-svc: { state: running, ... }
    Network Health:
      ct-net: { status: up, ... }
    Service Health:
      redis-pod: { state: active, status: running }

  postverify: |
    === Container Diagnostic Report ===
    (same structure)

verification_status:
  redis: false      # passed
  traefik: false    # passed
  hashivault: true  # FAILED

service_verify_result:
  redis: { failed: false, ... }
  traefik: { failed: false, ... }
```

### Matrix Dimensions

| Dimension | Values | Where Set |
|-----------|--------|-----------|
| **Services** | redis, traefik, hashivault, ... | `MOLECULE_SERVICES` env var |
| **Platforms** | uut-deb12, uut-rocky9, uut-ct2 | `MOLECULE_PLATFORM_NAME` env var |
| **Diagnostic Stages** | preverify, postverify | `report_suffix` variable |
| **Health Checks** | container, network, service | `diagnostics/` tasks |
| **Pass/Fail Status** | true/false per service | `verification_status` map |

### Example: Testing 3 Services on 3 Platforms

```bash
# Run redis, traefik, hashivault on all platforms
MOLECULE_SERVICES="redis,traefik,hashivault" molecule test -s podman
```

**Generates 3×3 = 9 test combinations**:

- redis on Debian 12
- redis on Rocky 9
- redis on Ubuntu 24
- traefik on Debian 12
- traefik on Rocky 9
- traefik on Ubuntu 24
- hashivault on Debian 12
- hashivault on Rocky 9
- hashivault on Ubuntu 24

**Collected data per combination**:

- Pre-verify diagnostics (container + network + service health)
- Service verification results (from `verify.yml`)
- Post-verify diagnostics
- Overall pass/fail status

### Report Generation (verify/report.yml)

**1. Consolidates all results**:

```yaml
- name: Create consolidated report
  set_fact:
    final_report: |
      === Monitoring Stack Test Report ===
      Timestamp: {{ ansible_facts.date_time.iso8601 }}

      Pre-verify Diagnostics:
      {{ all_verify_results.preverify }}

      (per-service results)

      Post-verify Diagnostics:
      {{ all_verify_results.postverify }}

      Overall Status: {{ 'FAILED' if any failed else 'PASSED' }}
```

**2. Saves per-platform reports**:

```bash
verify_output/
├── debian/
│   ├── consolidated_test_report.md
│   ├── container-diagnostics-preverify-<epoch>.yml
│   └── container-diagnostics-postverify-<epoch>.yml
├── rocky/
│   └── (same structure)
└── ubuntu/
    └── (same structure)
```

### Key Pattern: Accumulate, Don't Overwrite

Each diagnostic/verification adds to `all_verify_results` via `combine()`:

```yaml
# diagnostics/report.yml:31
- name: Add diagnostics results to dictionary
  set_fact:
    all_verify_results: "{{ all_verify_results | combine({
      report_suffix: container_diagnostics
    }) }}"
```

This ensures:

- `preverify` diagnostics preserved
- Service-specific results added
- `postverify` diagnostics added
- Nothing lost, complete audit trail

### Why This Is Non-Trivial

**Challenges solved**:

1. **Multi-stage collection**: Pre/post diagnostics + per-service verification
2. **Cross-playbook state**: `all_verify_results` accumulates across multiple included tasks
3. **Dynamic services**: Works with any services defined in `services.yml`
4. **Continue on failure**: `ignore_errors: yes` collects all results even if some fail
5. **Platform-specific reports**: Separate output per distribution
6. **Comprehensive audit trail**: Every check recorded, timestamped, saved

**Alternative approach** (naive):

- Run each service verification independently
- Lose context between services
- Can't compare pre/post diagnostics
- No consolidated matrix view

**This approach** (sophisticated):
- Single test run collects everything
- Matrix view across services × platforms
- Pre/post comparison shows impact
- Consolidated report shows full picture

### Debugging the Matrix

**View collected results during test**:

```yaml
# Add to verify/main.yml after diagnostics
- debug:
    var: all_verify_results.keys()
    verbosity: 0
```

**Check specific service failure**:

```yaml
- debug:
    msg: "{{ verification_status }}"
```

**Inspect diagnostic data**:

```bash
# After test completes
cat verify_output/debian/container-diagnostics-preverify-*.yml
```

## Usage Examples

### Run Tests with Shared Infrastructure

```bash
# Uses shared/podman/prepare.yml, converge.yml, verify/main.yml
molecule test -s podman

# Override services
MOLECULE_SERVICES="traefik,hashivault" molecule converge -s podman

# Debug mode (see credentials)
MOLECULE_SECURE_LOGGING=false molecule verify -s podman

# Specific platform
MOLECULE_PLATFORM_NAME=uut-rocky9 molecule test -s podman
```

### Modify Verification Logic

Edit shared playbooks, applies to all scenarios:

```bash
# Add new diagnostic
vim molecule/shared/diagnostics/storage-health.yml

# Include in main.yml
vim molecule/shared/diagnostics/main.yml

# Test change across all platforms
./run-podman-tests.sh --services redis
```

### Add Service-Specific Verification

Service-specific verification stays in service role:

```bash
# Edit service verification
vim roles/mattermost/tasks/verify.yml

# Test it
MOLECULE_SERVICES=mattermost molecule verify -s podman
```

## Troubleshooting Shared Infrastructure

### Debug which playbooks are running

```bash
# molecule.yml shows playbook paths
cat molecule/podman/molecule.yml | grep -A 5 playbooks
```

**Output**:
```yaml
playbooks:
  prepare: ../shared/podman/prepare.yml
  converge: ../shared/podman/converge.yml
  verify: ../shared/verify/main.yml
```

### Check services.yml loading

```bash
# Add debug task in converge.yml
- debug:
    var: container_services
```

### Verify environment variables

```bash
# In test playbook
- debug:
    msg: "Testing {{ lookup('env', 'MOLECULE_SERVICES') }}"
```

## Related Documentation

- [molecule/podman/README.md](../podman/README.md) - Podman scenario docs
- [roles/_base/Readme.md](../../roles/_base/Readme.md) - Similar pattern for deployment
- [docs/Container-Role-Architecture.md](../../docs/Container-Role-Architecture.md) - Architecture overview

## Conventions

1. **Shared playbooks are generic**: Use `services.yml` data, don't hardcode service names
2. **Scenarios are specific**: Configure via `molecule.yml` and env vars
3. **Verification lives in roles**: `roles/<service>/tasks/verify.yml` is canonical
4. **Services registry is authoritative**: Add to `services.yml` to enable testing
