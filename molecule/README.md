# SOLTI Containers — Molecule Testing

## Purpose

These are **end-to-end system tests**, not unit tests. The goal is not just
pass/fail — it is to produce a structured **Obsidian output directory** that
accumulates across runs and can be mined for trends, regressions, and service
health history.

Molecule is the collection mechanism. The Ansible roles are the probes.
Obsidian is the data store.

```text
molecule run
  └─ prepare:   clean slate via direct role invocation (_state=absent)
  └─ converge:  prepare state → deploy state via direct role invocation
  └─ verify:    role verify tasks run directly on the VM (this is the data)
  └─ cleanup:   remove (preserve) → verify stopped → remove data → verify gone
  └─ output:    verify_output/obsidian/runs/<timestamp>/
                  ├─ redis-service.md        (per-service result with frontmatter)
                  ├─ hashivault-service.md
                  └─ run-<timestamp>.md      (run summary)
```

Each run adds immutable event-sourced records to `verify_output/obsidian/`.
Over time these become a queryable dataset of service behavior.

## Working Scenario: proxmox

Targets the **podma** VM directly — no nested containers, no provisioning.
All phases call Ansible roles directly. No `svc-manage.sh` wrapper in the test path.

```bash
source ~/.secrets/LabProvision
./run-proxmox-tests.sh --services redis
./run-proxmox-tests.sh --services redis,influxdb3,mongodb
```

**Traefik is a required baseline.** The tests are E2E — they validate the full
stack. If Traefik is not running on podma, converge will stop immediately.

To test Traefik itself (rare):

```bash
./run-proxmox-tests.sh --services traefik
```

### Test cycle

```text
prepare   → include_role _state=absent (DELETE_DATA) — clean slate
converge  → include_role _state=prepare, then _state=present
verify    → role verify tasks run directly on podma via shared/verify/main.yml
cleanup   → include_role _state=absent (preserve) → verify stopped
          → file deletion of data dirs → verify gone
```

### Running individual phases

```bash
source ~/.secrets/LabProvision

MOLECULE_SERVICES=redis molecule prepare  -s proxmox
MOLECULE_SERVICES=redis molecule converge -s proxmox
MOLECULE_SERVICES=redis molecule verify   -s proxmox
MOLECULE_SERVICES=redis molecule cleanup  -s proxmox
```

## Service Registry: vars/services.yml

All services are defined in [vars/services.yml](vars/services.yml).
`verify_role_tasks` is an **ordered list** — sequence is the semantics.
Initialization, unsealing, and health checks all go in the right order.

```yaml
hashivault:
  verify_role_tasks:
    - initialize.yml   # ensure initialized (idempotent)
    - unseal.yml       # ensure unsealed
    - verify.yml       # health check
  service_names: [vault-pod, vault-svc]
  service_ports: [8200]
```

Services without initialization just have `[verify.yml]`.

## Not Working: podman scenario

`run-podman-tests.sh` targets the `podman` scenario which runs rootless Podman
inside privileged test containers. This hits a kernel limitation:

```text
newuidmap: write to uid_map failed: Operation not permitted
```

Nested rootless Podman cannot map user namespaces inside a container.
This scenario is preserved for GitHub CI (which uses VMs, not containers)
but is not usable locally.

## Output

```text
verify_output/
├── latest_proxmox_test.out          ← symlink to latest run log
├── proxmox-test-<timestamp>.out     ← full molecule output
└── obsidian/
    └── runs/
        └── <timestamp>/
            ├── redis-service.md     ← per-service result (YAML frontmatter)
            ├── <service>-service.md
            └── run-<timestamp>.md  ← overall run summary
```

Mine the obsidian directory with any Obsidian-compatible tool or script.
The YAML frontmatter in each file supports structured queries across runs.

## Hybrid Architecture: Molecule + Ansible Inventory

This is not a standard molecule setup. It is a **hybrid system** where molecule
provides the test lifecycle and Ansible provides the execution engine and
inventory model.

### Variable sources

Variables flow to playbooks from these sources, in increasing precedence:

| Source | Contains | How |
|--------|----------|-----|
| `inventory/group_vars/all.yml` | `domain`, `service_network`, `test_*`, `project_root`, `report_root`, `testing_services` | `links.group_vars` |
| `inventory/group_vars/<svc>_svc.yml` | `test_key`, `test_value`, `*_svc_name` per service | `links.group_vars` + group membership via `links.hosts` |
| `molecule.yml extra_vars` | `domain` (at inventory load time), `secure_logging` | `-e @extra_vars.yml` |
| `molecule.yml host_vars.podma` | `ansible_host`, `ansible_user`, SSH key | host_vars file |

`project_root`, `report_root`, `testing_services`, and `domain` all live in
`inventory/group_vars/all.yml` as `lookup('env', ...)` expressions evaluated
by Ansible at playbook time — not by molecule at file-write time.

### The inventory linking problem (solved)

Molecule builds an ephemeral inventory at `/tmp/molecule.*/inventory/`.
When `provisioner.inventory.links.group_vars` is set, molecule creates a
**symlink** replacing its own `group_vars/` directory. Any vars molecule had
written there are lost.

**Solution**: all vars that molecule needs live in the **real inventory's
`group_vars/`** — molecule's own `group_vars:` section is intentionally empty.
The symlink works in our favour: it brings in the full real inventory vars
without duplication.

### Connection variable bootstrap

`inventory/podma.yml` defines `ansible_host: "podma.{{ domain }}"`. Ansible
evaluates connection variables at inventory load time, before group_vars are
applied — so `{{ domain }}` would be undefined. Molecule's `extra_vars` provides
`domain: "${LAB_TLD}"` via shell expansion, making it available at inventory
load time before any playbook runs.

`host_vars.podma.ansible_host: "podma.${LAB_TLD}"` also overrides the
connection address directly, ensuring no Jinja2 evaluation is needed at connect
time.

### The testing layer

All phases — prepare, converge, cleanup — use `include_role` directly on podma.
No `svc-manage.sh` in the test path. A failing test means exactly one thing:
**the role does not work on this host**. `svc-manage.sh` can evolve freely
without touching the test infrastructure.

The verify phase uses `molecule/shared/verify/main.yml` which calls
`include_role: tasks_from: <task>` for each entry in `verify_role_tasks`.
This exercises the actual Ansible role logic — templates, variable rendering,
health checks — not a shell wrapper around it.

### Data directory deletion

The role's `service_properties.delete_data` reads `lookup('env', 'DELETE_DATA')`
on the Ansible controller. This env var cannot be set from within a playbook's
`environment:` (which only affects remote tasks). Cleanup stage 2 therefore
uses `ansible.builtin.file: state=absent` directly rather than routing through
the role. This is simpler and correct.

## Adding a New Service

1. Add entry to [vars/services.yml](vars/services.yml) with `verify_role_tasks`,
   `service_names`, and `service_ports`
2. Ensure `roles/<service>/tasks/verify.yml` exists
3. Test: `./run-proxmox-tests.sh --services <service>`
