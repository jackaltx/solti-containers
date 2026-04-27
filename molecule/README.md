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
  └─ converge:  deploy services (scripts are fine here — plumbing)
  └─ verify:    role verify tasks run directly on the VM (this is the data)
  └─ output:    verify_output/obsidian/runs/<timestamp>/
                  ├─ redis-service.md        (per-service result with frontmatter)
                  ├─ hashivault-service.md
                  └─ run-<timestamp>.md      (run summary)
```

Each run adds immutable event-sourced records to `verify_output/obsidian/`.
Over time these become a queryable dataset of service behavior.

## Working Scenario: proxmox

Targets the **podma** VM directly — no nested containers, no provisioning.

```bash
source ~/.secrets/LabProvision
./run-proxmox-tests.sh --services redis
./run-proxmox-tests.sh --services redis,influxdb3,mongodb
```

**Traefik is a required baseline.** The tests are E2E — they validate services
through the full stack including Traefik routing. If Traefik is not running on
podma, the converge phase will stop immediately before deploying anything.

To test Traefik itself (rare):

```bash
./run-proxmox-tests.sh --services traefik
```

### Test cycle

```text
prepare   → clean slate: remove existing services and data (DELETE_DATA)
converge  → DNS records + prepare state + deploy
verify    → role verify.yml tasks run directly on podma (the real test layer)
cleanup   → remove (preserve data) → verify stopped → remove (DELETE_DATA) → verify gone
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
provides the test lifecycle and Ansible provides both the execution engine and
the inventory model.

### Variable sources and precedence

Variables reach the verify playbook from three places, in increasing precedence:

| Source | Contains | Scope |
|--------|----------|-------|
| `inventory/group_vars/all.yml` | `domain`, `service_network`, `service_dns_*` | all hosts |
| `inventory/group_vars/<service>_svc.yml` | `test_key`, `test_value`, etc. | hosts in that group |
| `molecule/proxmox/molecule.yml group_vars` | `project_root`, `report_root`, `testing_services`, `secure_logging` | molecule-only |

### The inventory linking problem

Molecule builds an ephemeral inventory at `/tmp/molecule.*/inventory/`.
When `provisioner.inventory.links.group_vars` is set, molecule creates a
**symlink** replacing its own `group_vars/` directory with the real inventory's.
This means anything molecule wrote to `group_vars/` is lost.

**Current approach**: molecule-only vars (`project_root`, `report_root`,
`testing_services`) stay in `molecule.yml`'s `group_vars:` section — they are
written to the ephemeral `group_vars/` BEFORE any symlink. This works as long
as we do NOT also link `group_vars`.

The trade-off: service-specific test vars (`test_key`, `test_value`, etc.) are
duplicated inline in `molecule.yml` instead of flowing from `inventory/group_vars/`.
These should match the real inventory values. The clean solution (linking
`group_vars` + using `extra_vars` for molecule-only vars) is deferred until
tests are stable.

### Connection variable bootstrap

`inventory/podma.yml` defines `ansible_host: "podma.{{ domain }}"`. This
Jinja2 expression is resolved at inventory load time, when group_vars may not
yet be applied. To avoid a "domain is undefined" error at connection setup,
`molecule.yml` overrides `ansible_host` directly in `host_vars.podma`:

```yaml
host_vars:
  podma:
    ansible_host: "podma.${LAB_TLD}"   # shell expansion by molecule, no Jinja2
```

This bypasses the chicken-and-egg: Ansible connects to a static address,
and `domain` is only needed inside playbooks (where group_vars are available).

### Obsidian output

The verify phase writes structured markdown files to `verify_output/obsidian/`.
Each file has YAML frontmatter (type, service, distribution, status, timestamp)
that supports queries across runs. These are immutable event-sourced records —
never edited, only appended.

```text
verify_output/obsidian/runs/<distro>-<time>/
  ├── <service>-service.md    ← per-service result
  └── run-<timestamp>.md     ← overall run summary
```

### The verify layer

The critical design choice: `verify` uses `molecule/shared/verify/main.yml`
which calls `include_role: tasks_from: <task>` directly on podma — not via
`svc-manage.sh`. This is the **right testing layer**: the Ansible role logic
(templates, variable rendering, health checks) is exercised directly, not
through a shell script wrapper.

## Adding a New Service

1. Add entry to [vars/services.yml](vars/services.yml) with `verify_role_tasks`,
   `service_names`, and `service_ports`
2. Ensure `roles/<service>/tasks/verify.yml` exists
3. Test: `./run-proxmox-tests.sh --services <service>`
