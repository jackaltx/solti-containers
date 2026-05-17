# Sprint: Unify manage-svc.sh and svc-exec.sh

**Date**: 2026-04-22  
**Status**: Proposed

## Problem

`manage-svc.sh` and `svc-exec.sh` share ~60% identical code that must be kept in sync manually. The most painful duplication is `SUPPORTED_SERVICES[]` — adding a service requires touching both scripts.

## What's Duplicated

- `SUPPORTED_SERVICES[]` — must be kept in sync manually
- `get_target_context()` — byte-for-byte identical between scripts
- `prompt_user()` — near-identical (svc-exec adds `verify` skip)
- sudo capability test (`sudo -n true`)
- playbook display/execute/cleanup pattern

## What's Genuinely Different

| | `manage-svc.sh` | `svc-exec.sh` |
|---|---|---|
| Ansible call | full role + `<svc>_state` var | `include_role: tasks_from: <entry>` |
| Sudo | auto-detected by action | explicit `-K` flag |
| Actions | fixed set → STATE_MAP | open-ended entry names |
| Matrix logging | external `bin/matrix-log.py` | Ansible `matrix_event` pre/post tasks |

## Proposed Interface

Unified `svc.sh` dispatches on whether the action is a lifecycle state:

```bash
./svc.sh redis prepare       # state → full role call
./svc.sh redis deploy
./svc.sh redis remove
./svc.sh redis verify        # task → include_role tasks_from
./svc.sh -K redis configure  # task with explicit sudo
```

Decision rule: if ACTION is in `(prepare, deploy, remove)` → lifecycle mode (STATE_MAP + auto-sudo). Otherwise → exec mode (`include_role tasks_from`, `-K` flag).

## Implementation Notes

- Keep two internal `generate_playbook` functions (lifecycle vs exec) — they're structurally different enough
- Sudo handling: lifecycle path keeps auto-detection logic from `manage-svc.sh` lines 341–387; exec path keeps explicit `-K` flag from `svc-exec.sh`
- Matrix logging: pick one approach (external py script vs Ansible module) during this sprint — carrying both is the messiest part
- `prompt_user()` merge: combine the `verify`-skip logic from svc-exec with the base from manage-svc

## Selected Code Reference

The sudo auto-detection block in `manage-svc.sh` (lines 341–387) is the key lifecycle-specific logic to preserve:

```bash
NEED_SUDO=false

if [[ "$ACTION" == "prepare" ]] || [[ "$ACTION" == "deploy" ]]; then
    NEED_SUDO=true
elif [[ "$ACTION" == "remove" ]]; then
    # Check if service has delete_data=true (container subuid ownership)
    if [[ "${DELETE_DATA}" == "true" ]] || ansible-inventory ... | grep -q "delete_data.*true"; then
        NEED_SUDO=true
    fi
fi
```

This block does not belong in the exec path (where sudo is user-explicit via `-K`).

## Decision

Worth doing to eliminate `SUPPORTED_SERVICES` sync burden. Not urgent if services are rarely added.
