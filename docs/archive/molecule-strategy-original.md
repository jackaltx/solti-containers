# Molecule Testing Strategy for Container Roles (ARCHIVED)

**Status**: This document represents the original testing strategy from the early planning phase. The actual implementation evolved significantly.

**See current documentation**:

- [molecule/README.md](../molecule/README.md) - User guide for running tests
- [molecule/shared/README.md](../molecule/shared/README.md) - Developer guide for testing infrastructure
- [molecule/podman/README.md](../molecule/podman/README.md) - Podman scenario details

## What Changed

### Original Plan

- **Per-role testing**: Each role would have its own `molecule/` directory
- **Individual scenarios**: Separate test setup per role
- **Platform matrix**: Test across distributions but one role at a time

### Actual Implementation

- **Collection-level testing**: Single `molecule/` at collection root
- **Shared infrastructure**: Common playbooks in `molecule/shared/`
- **Dynamic service selection**: Test any combination via `MOLECULE_SERVICES` env var
- **Verification matrix**: Multi-dimensional results (services × platforms × stages)
- **Nested containers**: Test container → Podman → service containers
- **Services registry**: Central `molecule/vars/services.yml` for all services

### Why It Evolved

The actual implementation mirrors the `_base` role pattern:

- **DRY principle**: Shared playbooks eliminate duplication across 10+ services
- **Flexibility**: Test any combination of services dynamically
- **Comprehensive**: Matrix view across all test dimensions
- **Maintainable**: Fix verification logic once, applies everywhere
- **Scalable**: Adding new service only requires updating `services.yml`

See [molecule/shared/README.md](../molecule/shared/README.md) for detailed explanation of the shared infrastructure pattern and verification matrix collection.

---

## Original Plan (Historical Reference)

This section preserves the original planning for historical context.

## Current Setup Analysis

### Common Elements in Both Roles

- Both roles use Podman for container management
- Both implement systemd integration via Quadlets
- Both have similar directory structures and configuration patterns
- Both support multiple Linux distributions

### Role-Specific Considerations

#### Mattermost Role

- Multiple container dependencies (PostgreSQL + Mattermost)
- Requires network communication between containers
- Has database initialization requirements
- Manages configuration files and TLS certificates

#### Elasticsearch Role

- Single primary container with optional GUI container
- Has specific system requirements (vm.max_map_count)
- Memory management considerations
- TLS and security configuration options

## Proposed Molecule Testing Strategy

### 1. Basic Structure

```yaml
roles/
  mattermost/
    molecule/
      default/
        molecule.yml      # Main test configuration
        prepare.yml       # System preparation
        converge.yml      # Role execution
        verify.yml        # Test assertions
        cleanup.yml       # Optional cleanup
      podman/            # Podman-specific scenario
        molecule.yml
  elasticsearch/
    molecule/
      [similar structure]
```

### 2. Platform Configuration

```yaml
# molecule.yml example
platforms:
  - name: rhel9
    image: registry.access.redhat.com/ubi9/ubi-init
    privileged: true
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    command: "/usr/sbin/init"
    
  - name: debian12
    image: debian:bookworm
    privileged: true
    command: "/lib/systemd/systemd"
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
```

### 3. Test Phases

#### Prepare Phase (prepare.yml)

```yaml
- name: Prepare test environment
  hosts: all
  tasks:
    - name: Install common dependencies
      package:
        name:
          - podman
          - python3-pip
        state: present
      
    - name: Configure system requirements
      sysctl:
        name: vm.max_map_count
        value: "262144"
      when: "'elasticsearch' in ansible_role_names"
```

#### Converge Phase (converge.yml)

```yaml
---
- name: Converge
  hosts: all
  tasks:
    # For Mattermost role
    - name: Include mattermost role
      ansible.builtin.include_role:
        name: mattermost
      vars:
        mattermost_postgres_password: "molecule_test_password"
        mattermost_port: 8065
      when: "'mattermost' in ansible_role_names"

    # For Elasticsearch role
    - name: Include elasticsearch role
      ansible.builtin.include_role:
        name: elasticsearch
      vars:
        elasticsearch_password: "molecule_test_password"
        elasticsearch_memory: "1g"
      when: "'elasticsearch' in ansible_role_names"
```

#### Verify Phase (verify.yml)

```yaml
- name: Verify deployment
  hosts: all
  tasks:
    # Mattermost Tests
    - name: Check Mattermost service
      uri:
        url: "http://localhost:{{ mattermost_port }}"
        status_code: 200
      when: "'mattermost' in ansible_role_names"
      
    # Elasticsearch Tests
    - name: Check Elasticsearch health
      uri:
        url: "http://localhost:{{ elasticsearch_port }}/_cluster/health"
        status_code: 200
      when: "'elasticsearch' in ansible_role_names"
```

### 4. Test Scenarios

#### Basic Functionality

- Role syntax checking
- Basic installation
- Service startup
- Port accessibility
- Basic functionality verification

#### Security Testing

- TLS configuration
- Password handling
- SELinux contexts (RHEL)
- File permissions

#### Performance Testing

- Memory limits
- Container resource allocation
- Multi-container communication (Mattermost)

#### Failure Testing

- Network interruption handling
- Container restart behavior
- Data persistence verification

### 5. Implementation Strategy

1. **Phase 1: Basic Testing**
   - Set up basic Molecule structure
   - Implement syntax and installation tests
   - Basic service verification

2. **Phase 2: Platform Coverage**
   - Add support for all target distributions
   - Validate platform-specific configurations
   - Test systemd integration

3. **Phase 3: Advanced Testing**
   - Security configurations
   - Performance testing
   - Failure scenarios

4. **Phase 4: CI Integration**
   - GitHub Actions integration
   - Automated test runs
   - Test result reporting

## Recommendations

1. **Testing Environment**
   - Use GitHub Actions instead of Travis CI (more modern, better integrated)
   - Implement matrix testing for different distributions
   - Use container caching to speed up tests

2. **Test Organization**
   - Separate scenarios for different test types
   - Use tagging for selective test execution
   - Implement shared test dependencies

3. **Quality Assurance**
   - Add linting with ansible-lint
   - Implement idempotence testing
   - Add documentation testing

4. **Monitoring & Reporting**
   - Configure test result collection
   - Set up test coverage reporting
   - Implement test timing metrics

## Next Steps

1. Create basic Molecule test structure for both roles
2. Implement basic scenario tests
3. Add platform-specific configurations
4. Set up GitHub Actions workflow
5. Add advanced test scenarios
6. Document testing procedures

## Example GitHub Actions Workflow

```yaml
name: Molecule Test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        distro:
          - rhel9
          - debian12
        role:
          - mattermost
          - elasticsearch
    
    steps:
      - uses: actions/checkout@v2
      
      - name: Set up Python
        uses: actions/setup-python@v2
        
      - name: Install dependencies
        run: pip install molecule[docker] ansible-lint
        
      - name: Run Molecule tests
        run: molecule test
        env:
          MOLECULE_DISTRO: ${{ matrix.distro }}
```
