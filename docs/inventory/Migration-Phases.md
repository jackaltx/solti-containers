# Inventory System Migration Phases

## Overview

This document details the phased approach to evolving the inventory system from its current state to the target architecture. Each phase has clear objectives, risks, testing requirements, and breakpoints for user validation.

## Phase Summary

| Phase | Duration | Risk | Dependencies |
|-------|----------|------|--------------|
| **Phase 1**: Safety & Documentation | 1-2 weeks | Low | None |
| **Phase 2**: Consolidate to inventory/ | 1-2 weeks | Medium | Phase 1 |
| **Phase 3**: Extract group_vars | 2-3 weeks | Medium-High | Phase 2 |
| **Phase 4**: Capability Matrix | 1-2 weeks | Medium | Phase 3 or parallel |
| **Phase 5**: Secrets Separation | TBD | High | Phase 3, orchestrator requirements |

**Total Estimated Time**: 2-3 months (phases 1-4)

---

## Phase 1: Safety & Documentation

**Status**: Current sprint (IN PROGRESS)

### Objectives

1. ✓ Document current inventory system comprehensively
2. ✓ Document target architecture and migration path
3. → Implement safety prompts for non-localhost operations
4. → Add `--yes` flag for automation bypass
5. → Change default inventory to `inventory/localhost.yml`
6. → Add inventory validation checks

### Deliverables

**Documentation** (in `docs/inventory/`):

- [x] `Inventory-System-Overview.md` - Current state
- [x] `Inventory-Architecture-Goals.md` - Vision and goals
- [x] `Migration-Phases.md` - This document
- [ ] `Capability-Matrix.md` - Testing patterns

**Code Changes**:

- [ ] `manage-svc.sh` - Add `--yes` flag and safety prompts
- [ ] `svc-exec.sh` - Add `--yes` flag and safety prompts
- [ ] `ansible.cfg` - Change default to `inventory/localhost.yml`

### Safety Prompt Implementation

**Three-tier prompt system**:

1. **Silent** (no prompt):
   - Default localhost via `ansible.cfg`
   - Any command with `--yes` flag
   - Read-only operations (`verify`, status checks)

2. **Soft confirm** (default YES):
   - Explicit localhost: `-i inventory/localhost.yml` or `-h firefly`
   - Message: "Installing `<service>` locally on firefly. Continue? [Y/n]"

3. **Hard confirm** (default NO):
   - Remote targeting: `-i inventory/padma.yml` or `-h podma`
   - Message: "⚠ Target: podma.a0a0.org - Deploy `<service>`? [y/N]"

**Automation support**:

```bash
# Skip all prompts
./manage-svc.sh --yes redis deploy
./manage-svc.sh --yes -i inventory/padma.yml redis deploy
```

### Implementation Details

**manage-svc.sh changes**:

```bash
# Add flag parsing
YES_FLAG=false
while getopts "i:h:y" opt; do
    case $opt in
        y) YES_FLAG=true ;;
    esac
done

# Add prompt function
prompt_user() {
    local context=$1  # localhost or remote
    local service=$2
    local action=$3

    [[ "$YES_FLAG" == "true" ]] && return 0
    [[ "$action" == "verify" ]] && return 0

    case "$context" in
        localhost)
            if [[ "$EXPLICIT_TARGET" == "true" ]]; then
                read -p "Installing ${service} locally on firefly. Continue? [Y/n] " response
                [[ "$response" =~ ^[Nn] ]] && return 1
            fi
            ;;
        remote)
            echo "⚠ Target: ${HOST:-remote} - Deploy ${service}?"
            read -p "Proceed? [y/N] " response
            [[ ! "$response" =~ ^[Yy] ]] && return 1
            ;;
    esac
    return 0
}
```

### Testing Requirements

**Test scenarios**:

| Scenario | Command | Expected Behavior |
|----------|---------|-------------------|
| Default localhost | `./manage-svc.sh redis deploy` | No prompt, deploys |
| Explicit localhost | `./manage-svc.sh -i inventory/localhost.yml redis deploy` | Soft prompt (Y/n) |
| Explicit firefly | `./manage-svc.sh -h firefly redis deploy` | Soft prompt (Y/n) |
| Remote padma | `./manage-svc.sh -i inventory/padma.yml redis deploy` | Hard prompt (y/N) |
| With --yes | `./manage-svc.sh --yes -i inventory/padma.yml redis deploy` | No prompt, deploys |
| Verify operation | `./svc-exec.sh -i inventory/padma.yml redis verify` | No prompt (read-only) |

**Validation**:

- [ ] All test scenarios pass
- [ ] Prompts display correct service and host
- [ ] `--yes` flag bypasses all prompts
- [ ] Read-only operations never prompt
- [ ] Error handling for invalid responses

### Risks

**Low risk** - All changes are additive:

- Safety prompts are new functionality
- `--yes` flag is new, doesn't change existing behavior
- Default inventory change is isolated to `ansible.cfg`

**Potential issues**:

- Prompt logic might misidentify context (localhost vs remote)
- `--yes` flag might conflict with existing flags
- Changed default might surprise users expecting old behavior

**Mitigation**:

- Comprehensive test matrix
- Clear documentation of new behavior
- Preserve backward compatibility (root `inventory.yml` still works)

### Breakpoint

**User Validation Required**:

1. Review documentation for clarity and completeness
2. Test safety prompts in all scenarios
3. Confirm `--yes` flag works in automation contexts
4. Verify default inventory change doesn't break workflows

**Success Criteria**:

- ✓ Documentation approved
- ✓ Safety prompts work correctly
- ✓ No regression in existing workflows
- ✓ Automation use cases validated

**Decision**: Proceed to Phase 2 or iterate on Phase 1

---

## Phase 2: Consolidate to inventory/

**Estimated Duration**: 1-2 weeks
**Risk**: Medium

### Objectives

1. Make `inventory/localhost.yml` the authoritative localhost inventory
2. Make `inventory/padma.yml` the authoritative remote inventory
3. Deprecate root `inventory.yml` (keep as fallback)
4. Update scripts to prefer `inventory/` files
5. Document inventory selection strategy

### Deliverables

**Code Changes**:

- Update `manage-svc.sh` to prefer `inventory/localhost.yml` when `-i` not specified
- Update `svc-exec.sh` similarly
- Add deprecation warning when root `inventory.yml` used explicitly
- Update `ansible.cfg` if not done in Phase 1

**Documentation**:

- Update README with new inventory selection behavior
- Add deprecation notice to root `inventory.yml` header
- Update CLAUDE.md with new patterns

### Implementation Strategy

**Graceful deprecation**:

```bash
# In manage-svc.sh
DEFAULT_INVENTORY="${ANSIBLE_DIR}/inventory/localhost.yml"
INVENTORY="${SOLTI_INVENTORY:-$DEFAULT_INVENTORY}"

# Warn if using deprecated inventory
if [[ "$INVENTORY" == *"/inventory.yml" ]] && [[ ! "$INVENTORY" =~ inventory/ ]]; then
    echo "⚠ WARNING: Root inventory.yml is deprecated. Use inventory/localhost.yml or inventory/padma.yml"
    echo "Set SOLTI_INVENTORY=inventory/localhost.yml to suppress this warning"
fi
```

**Inventory file header**:

```yaml
# inventory.yml
# DEPRECATED: This file is maintained for backward compatibility only.
# Use inventory/localhost.yml or inventory/padma.yml instead.
#
# This file will be removed in a future release.
```

### Testing Requirements

**Backward compatibility tests**:

- [ ] Root `inventory.yml` still works when explicitly specified
- [ ] Environment variable `SOLTI_INVENTORY` still works
- [ ] `-i` flag takes precedence over defaults
- [ ] Deprecation warning displays appropriately

**New default behavior tests**:

- [ ] No `-i` flag uses `inventory/localhost.yml`
- [ ] Scripts find inventory files correctly
- [ ] Variable resolution works identically
- [ ] All services deploy successfully

**Regression testing**:

- [ ] Deploy all services with new default
- [ ] Verify all services with new default
- [ ] Remove all services with new default
- [ ] Repeat on remote host with `inventory/padma.yml`

### Risks

**Medium risk** - Changes default behavior:

- Users with automation might break if hardcoded to root inventory
- Environment variables might override defaults unexpectedly
- Script logic for inventory detection could have bugs

**Potential issues**:

- Deprecation warning might be too noisy
- Users might not notice the change
- Relative path handling differences

**Mitigation**:

- Clear documentation and announcement
- Deprecation warning is informative, not blocking
- Keep root inventory functional for entire phase
- Comprehensive testing before rollout

### Breakpoint

**User Validation Required**:

1. Test all workflows with new default
2. Verify automation scripts still work
3. Confirm deprecation warnings are helpful
4. Check for unexpected side effects

**Success Criteria**:

- ✓ New default works for all use cases
- ✓ Backward compatibility maintained
- ✓ No user-reported issues
- ✓ Documentation clear and complete

**Rollback Plan**: Revert `ansible.cfg` and script changes, keep documentation

**Decision**: Proceed to Phase 3 or iterate on Phase 2

---

## Phase 3: Extract group_vars

**Estimated Duration**: 2-3 weeks
**Risk**: Medium-High

### Objectives

1. Create `inventory/group_vars/` directory structure
2. Extract service-specific variables to `group_vars/<service>_svc.yml`
3. Extract global variables to `group_vars/all.yml`
4. Create `inventory/host_vars/` for host-specific overrides
5. Slim down inventory YAML files to host definitions only

### Deliverables

**Directory Structure**:

```
inventory/
├── localhost.yml              # Slim: just host definition
├── padma.yml                  # Slim: just host definition
├── group_vars/
│   ├── all.yml                # Global vars
│   ├── mylab.yml              # Lab vars
│   ├── redis_svc.yml          # Service defaults
│   ├── elasticsearch_svc.yml
│   ├── mattermost_svc.yml
│   └── ...
└── host_vars/
    ├── firefly.yml            # Host overrides
    └── podma.yml              # Host overrides
```

**Transformed Files**:

**Before** (`inventory/localhost.yml` - 382 lines):

```yaml
all:
  vars:
    domain: a0a0.org
    service_network: "ct-net"
    # ... 50+ lines of global vars
  children:
    mylab:
      vars:
        mylab_results: []
      children:
        redis_svc:
          hosts:
            firefly:
              redis_svc_name: "redis"
          vars:
            debug_level: warn
            redis_password: "..."
            # ... 20+ lines of redis config
        # ... 10+ more service groups
```

**After** (`inventory/localhost.yml` - ~30 lines):

```yaml
all:
  children:
    mylab:
      hosts:
        firefly:
          ansible_host: "localhost"
          ansible_connection: local
      children:
        redis_svc:
          hosts:
            firefly:
        elasticsearch_svc:
          hosts:
            firefly:
        # ... service groups (no vars)
```

**New Files**:

`inventory/group_vars/all.yml`:

```yaml
---
# Global configuration for all hosts and services
domain: a0a0.org
ansible_user: lavender
ansible_ssh_private_key_file: ~/.ssh/id_ed25519
service_network: "ct-net"
service_dns_servers: [1.1.1.1, 8.8.8.8]
service_dns_search: "{{ domain }}"
mylab_nolog: "{{ cluster_secure_log | bool | default(true) }}"
mylab_non_ssh: false
```

`inventory/group_vars/redis_svc.yml`:

```yaml
---
# Redis service defaults
debug_level: warn
redis_version: "7.2"
redis_port: 6379
redis_password: "{{ lookup('env', 'REDIS_PASSWORD') }}"
redis_delete_data: false
```

`inventory/host_vars/firefly.yml`:

```yaml
---
# Localhost-specific configuration
redis_svc_name: "redis"
redis_data_dir: "~/redis-data"

elasticsearch_svc_name: "elasticsearch"
elasticsearch_data_dir: "~/elasticsearch-data"

host_capabilities:
  - direct_port_access
  - container_exec
  - systemd_user
```

### Implementation Strategy

**Incremental extraction** (do NOT extract everything at once):

**Step 1**: Extract 2-3 simple services as proof-of-concept

- Choose: `redis`, `minio`, `traefik` (simple, well-tested)
- Create `group_vars/` files
- Create minimal `host_vars/` overrides
- Test thoroughly

**Step 2**: Validate variable precedence

- Deploy services
- Verify variables resolved correctly
- Check for unexpected precedence issues
- Document any gotchas

**Step 3**: Extract remaining services

- Batch of 3-4 services at a time
- Test each batch before proceeding
- Document any service-specific issues

**Step 4**: Extract global and lab vars

- Move `all:vars` to `group_vars/all.yml`
- Move `mylab:vars` to `group_vars/mylab.yml`
- Test all services still work

**Step 5**: Slim down inventory files

- Remove extracted vars from inventory YAML
- Keep only host definitions and group membership
- Final regression testing

### Variable Precedence Verification

**Ansible's precedence order** (relevant levels):

1. Extra vars (`-e` flag) - Highest
2. **host_vars/** files
3. Inventory host vars (inline under host)
4. **group_vars/** files
5. Inventory group vars (inline under group)
6. Inventory all vars (inline under all)
7. Role defaults - Lowest

**Critical**: Moving vars from inline to files changes precedence!

**Example issue**:

```yaml
# Before (inline): group_vars has higher precedence than host inline vars
elasticsearch_svc:
  vars:
    elasticsearch_port: 9200  # Inline group var
  hosts:
    firefly:
      elasticsearch_port: 9201  # Inline host var - WINS

# After (files): host_vars/ has higher precedence than group_vars/
# group_vars/elasticsearch_svc.yml
elasticsearch_port: 9200  # File group var

# host_vars/firefly.yml
elasticsearch_port: 9201  # File host var - WINS (same precedence as before)
```

**Testing**:

- Verify each variable resolves to expected value
- Use `ansible-inventory -i inventory/localhost.yml --host firefly --yaml` to inspect
- Check for variables that changed unexpectedly

### Testing Requirements

**Variable resolution tests**:

- [ ] All variables resolve correctly after extraction
- [ ] Host overrides still override group defaults
- [ ] Global variables accessible in all contexts
- [ ] No variable name collisions

**Functional tests** (per service):

- [ ] Prepare succeeds
- [ ] Deploy succeeds
- [ ] Verify succeeds
- [ ] Remove succeeds

**Regression testing** (all services):

- [ ] Deploy all services on localhost
- [ ] Verify all services
- [ ] Deploy all services on remote (padma)
- [ ] Verify all services on remote

**Precedence validation**:

```bash
# Inspect resolved variables
ansible-inventory -i inventory/localhost.yml --host firefly --yaml > /tmp/firefly-vars.yml

# Compare before/after extraction
diff /tmp/firefly-vars-before.yml /tmp/firefly-vars-after.yml
```

### Risks

**Medium-High risk** - Complex change with many variables:

- Variable precedence bugs could break deployments
- Easy to miss a variable during extraction
- Service interdependencies might break
- Jinja2 template context changes might cause failures

**Potential issues**:

- Variables not found (missing extraction)
- Variables resolve to wrong values (precedence issue)
- Circular dependencies in variable references
- Templates expecting variables in specific scopes

**Mitigation**:

- Extract in small batches (2-3 services at a time)
- Test thoroughly between batches
- Use `ansible-inventory` to verify resolution
- Keep inline vars until extraction proven working
- Document all variable moves

### Breakpoint

**User Validation Required**:

1. Deploy all services with new structure
2. Verify variable resolution is correct
3. Test on both localhost and remote
4. Confirm no regressions

**Success Criteria**:

- ✓ All services deploy successfully
- ✓ All variables resolve correctly
- ✓ Inventory files simplified (<50 lines each)
- ✓ `group_vars/` and `host_vars/` complete
- ✓ No functional regressions

**Rollback Plan**:

- Revert to Phase 2 state
- Delete `group_vars/` and `host_vars/` directories
- Restore inline variables in inventory files

**Decision**: Proceed to Phase 4 or iterate on Phase 3

---

## Phase 4: Capability Matrix

**Estimated Duration**: 1-2 weeks
**Risk**: Medium
**Dependencies**: Can start during Phase 3 or after

### Objectives

1. Define capability taxonomy
2. Add `host_capabilities` to host_vars
3. Update verification tasks to query capabilities
4. Implement capability-driven test selection
5. Document capability patterns

### Deliverables

**Capability Definitions** (`docs/inventory/Capability-Matrix.md`):

- Standard capability names
- Capability descriptions
- Required configuration per capability
- Test selection logic

**Host Configuration**:

```yaml
# inventory/host_vars/firefly.yml
host_capabilities:
  - direct_port_access      # Can curl localhost:PORT
  - container_exec          # Can podman exec
  - systemd_user            # Has systemctl --user
  - local_file_access       # Can access ~/data directly
```

**Role Updates** (example: elasticsearch):

```yaml
# roles/elasticsearch/tasks/verify.yml
---
- name: Determine test strategy
  set_fact:
    elasticsearch_test_strategy: >-
      {{ 'external' if 'traefik_routing' in host_capabilities | default([])
         else 'direct' if 'direct_port_access' in host_capabilities | default([])
         else 'container_exec' }}

- name: Run verification tests
  include_tasks: "verify_{{ elasticsearch_test_strategy }}.yml"
```

**New Verification Task Files**:

- `roles/<service>/tasks/verify_direct.yml` - Direct port access tests
- `roles/<service>/tasks/verify_external.yml` - Traefik proxy tests
- `roles/<service>/tasks/verify_container.yml` - Container exec tests

### Implementation Strategy

**Step 1**: Define capabilities and add to hosts

- Document capability taxonomy
- Add `host_capabilities` to `firefly` and `podma`
- Test that variables are accessible in roles

**Step 2**: Update 2-3 services as proof-of-concept

- Choose: `redis` (simple), `elasticsearch` (medium), `mattermost` (complex)
- Split verify tasks by capability
- Test on both localhost and remote

**Step 3**: Validate test selection logic

- Ensure correct test strategy selected
- Verify all test variants work
- Check for missing capability combinations

**Step 4**: Roll out to remaining services

- Update verify tasks for all services
- Test each service on both hosts
- Document service-specific requirements

### Capability Taxonomy

| Capability | Test Type | Verification Method |
|------------|-----------|---------------------|
| `direct_port_access` | API access | `curl localhost:PORT` |
| `traefik_routing` | HTTPS access | `curl https://service.domain.com` |
| `container_exec` | Internal | `podman exec service command` |
| `systemd_user` | Lifecycle | `systemctl --user status` |
| `external_dns` | DNS resolution | `nslookup service.domain.com` |
| `sudo_access` | Privileged ops | `sudo systemctl status` |
| `selinux_enforcing` | Security | `getenforce`, context checks |

### Testing Requirements

**Capability detection tests**:

- [ ] Capabilities defined in host_vars
- [ ] Roles can access `host_capabilities` variable
- [ ] Default to safe fallback if capabilities undefined

**Test strategy selection**:

- [ ] Correct strategy chosen based on capabilities
- [ ] All test variants execute successfully
- [ ] Missing capabilities handled gracefully

**Service-specific tests** (per service):

- [ ] Direct access tests work on firefly
- [ ] External access tests work on podma (if Traefik deployed)
- [ ] Container exec fallback works everywhere
- [ ] Verification passes on both hosts

### Risks

**Medium risk** - Adds complexity to verification:

- Test selection logic could have bugs
- Missing capability combinations might not be handled
- Some services might not fit capability model

**Potential issues**:

- Verification tasks might not have all capability variants
- Test strategy selection logic could be wrong
- Services with unique verification needs might not fit pattern

**Mitigation**:

- Start with simple services
- Test all capability combinations
- Document service-specific exceptions
- Fallback to safe defaults when uncertain

### Breakpoint

**User Validation Required**:

1. Verify capabilities defined correctly
2. Test all services on localhost (direct access)
3. Test all services on remote (external access if Traefik available)
4. Confirm test selection logic works

**Success Criteria**:

- ✓ All services verify successfully on localhost
- ✓ All services verify successfully on remote
- ✓ Test strategy selection works correctly
- ✓ Capability matrix documented

**Rollback Plan**:

- Remove capability-based test selection
- Revert to single verify.yml per service
- Keep capability definitions for future use

**Decision**: Proceed to Phase 5 or iterate on Phase 4

---

## Phase 5: Secrets Separation

**Estimated Duration**: TBD (depends on orchestrator requirements)
**Risk**: High
**Dependencies**: Phase 3 complete, orchestrator design finalized

### Objectives

1. Create external secrets repository structure
2. Extract all secrets from public repository
3. Implement multi-inventory merging
4. Document secrets management patterns
5. Test with ansible-vault encryption

### Deliverables

**External Repository** (`~/solti-secrets/` or separate git repo):

```
solti-secrets/
├── inventory/
│   ├── group_vars/
│   │   └── vault.yml          # Encrypted secrets
│   └── host_vars/
│       ├── firefly-vault.yml  # Host-specific secrets
│       └── podma-vault.yml
└── README.md                  # Secrets management docs
```

**Public Repository Changes**:

```yaml
# group_vars/redis_svc.yml (public repo)
redis_password: "{{ vault_redis_password }}"  # Reference only

# solti-secrets/inventory/group_vars/vault.yml (private repo, encrypted)
vault_redis_password: "actual_secret_here"
```

**Usage Pattern**:

```bash
# Ansible automatically merges group_vars from multiple inventory sources
ansible-playbook -i inventory/localhost.yml \
                 -i ~/solti-secrets/inventory \
                 playbook.yml

# Or via script enhancement
export SOLTI_SECRETS_INVENTORY=~/solti-secrets/inventory
./manage-svc.sh redis deploy  # Script merges both inventories
```

### Implementation Strategy

**Step 1**: Create secrets repository structure

- Set up directory layout
- Document secrets management policy
- Create example vault file

**Step 2**: Extract secrets from 2-3 services

- Move passwords to vault
- Update references in public repo
- Test multi-inventory merging

**Step 3**: Implement ansible-vault encryption

- Encrypt vault files
- Test vault password prompting
- Document vault key management

**Step 4**: Extract remaining secrets

- Batch extraction of all services
- Verify no secrets remain in public repo
- Audit git history for leaked secrets

**Step 5**: Update management scripts

- Add `SOLTI_SECRETS_INVENTORY` support
- Implement multi-inventory merging
- Update documentation

### Ansible Vault Integration

**Encrypt secrets**:

```bash
# Create vault password file (DO NOT COMMIT)
echo "your_vault_password" > ~/.ansible_vault_pass

# Encrypt vault file
ansible-vault encrypt solti-secrets/inventory/group_vars/vault.yml \
              --vault-password-file ~/.ansible_vault_pass
```

**Usage**:

```bash
# Ansible uses vault password automatically
export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible_vault_pass
./manage-svc.sh redis deploy

# Or prompt for password
ansible-playbook -i inventory/localhost.yml \
                 -i ~/solti-secrets/inventory \
                 --ask-vault-pass \
                 playbook.yml
```

### Testing Requirements

**Secrets extraction tests**:

- [ ] All secrets moved to external repository
- [ ] Public repository contains zero secrets
- [ ] Git history audited for leaked secrets
- [ ] References to vault variables work correctly

**Multi-inventory tests**:

- [ ] Ansible merges inventories correctly
- [ ] Variables from secrets repo override public repo
- [ ] No variable resolution issues
- [ ] All services deploy successfully

**Vault encryption tests**:

- [ ] Vault files encrypted properly
- [ ] Vault password prompting works
- [ ] Ansible decrypts vault files automatically
- [ ] Invalid vault password handled gracefully

**Security tests**:

- [ ] Secrets repository access controlled (private git repo or local only)
- [ ] Vault password not committed to git
- [ ] Decrypted secrets not written to logs
- [ ] `mylab_nolog` prevents secret exposure

### Risks

**High risk** - Security-critical change:

- Secrets might be leaked during transition
- Vault encryption might fail
- Multi-inventory merging could break
- Git history might contain secrets

**Potential issues**:

- Forgotten secrets still in public repo
- Vault password management complexity
- Inventory merging precedence issues
- Secrets logged during debugging

**Mitigation**:

- Careful audit of all secret locations
- Use `git-secrets` or similar tools
- Test vault encryption thoroughly
- Document secrets management clearly
- Implement `mylab_nolog` consistently

### Breakpoint

**User Validation Required**:

1. Audit public repository for secrets
2. Test multi-inventory merging
3. Verify vault encryption/decryption
4. Confirm all services work with external secrets

**Success Criteria**:

- ✓ Public repository contains zero secrets
- ✓ All secrets in external repository (encrypted)
- ✓ Multi-inventory merging works correctly
- ✓ All services deploy successfully
- ✓ Secrets management documented

**Rollback Plan**:

- Move secrets back to public repository
- Remove vault encryption
- Revert to single inventory structure
- Document rollback reason

**Decision**: Complete Phase 5 or rollback if issues found

---

## Cross-Phase Considerations

### Testing Strategy

**Per-phase testing**:

- Unit tests (variable resolution, script logic)
- Integration tests (deploy single service)
- Regression tests (deploy all services)
- User acceptance tests (validate with real workflows)

**Continuous testing**:

- Every commit should be deployable
- Checkpoint commits before major changes
- Keep test environment stable throughout

### Documentation Updates

**Per-phase documentation**:

- Update README.md with changes
- Update CLAUDE.md with new patterns
- Update relevant docs/ files
- Add migration notes to changelog

**User communication**:

- Announce phase start and objectives
- Document breaking changes clearly
- Provide migration examples
- Update troubleshooting guides

### Rollback Strategy

**Each phase boundary enables rollback**:

- Checkpoint commits before phase start
- Document rollback procedure
- Test rollback process
- Preserve old files during transition

**Rollback triggers**:

- Critical bugs discovered
- User workflows broken
- Performance degradation
- Security issues introduced

### Success Metrics

**Phase success indicators**:

- All tests pass
- No user-reported issues
- Documentation complete
- Performance acceptable
- Security maintained or improved

**Overall migration success**:

- Inventory files reduced to <50 lines
- Service configuration centralized
- Duplication eliminated
- Safety features working
- Users satisfied with changes

## Related Documentation

- [Inventory-System-Overview.md](Inventory-System-Overview.md) - Current state
- [Inventory-Architecture-Goals.md](Inventory-Architecture-Goals.md) - Target architecture
- [Capability-Matrix.md](Capability-Matrix.md) - Testing patterns
- [CLAUDE.md](../../CLAUDE.md) - Project context
