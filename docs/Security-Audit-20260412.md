# Security Audit Report - April 12, 2026

## Overview
This document summarizes the findings and recommendations from a security audit of the **solti-podman** collection. The audit focused on secrets management, container isolation, and system-level configuration within the Ansible-driven rootless Podman architecture.

## 1. High-Impact Findings

### Hardcoded Credentials in Inventory
- **Risk**: Multiple service configuration files in `inventory/group_vars/` contain hardcoded "test" passwords and tokens (e.g., `mattermost_svc.yml`, `conduit_svc.yml`).
- **Impact**: Potential for accidental deployment of insecure defaults in production environments.
- **Recommendation**: Replace hardcoded defaults with `assert` statements that require an environment variable or secret from a secure vault (e.g., HashiVault).

### Overly Permissive Directory Permissions
- **Risk**: Quadlet deployment directories (`~/.config/containers/systemd`) and some service config directories (e.g., `elasticsearch`) are created with `0755` or `0775` permissions.
- **Impact**: Sensitive service definitions and configurations are readable by other unprivileged users on the same host.
- **Recommendation**: Standardize on `0700` for all service data and configuration directories. Ensure sensitive files (e.g., Quadlets) are set to `0600`.

## 2. Medium-Impact Findings

### Insecure Temporary File Handling in Scripts
- **Risk**: `svc-exec.sh` (and likely `manage-svc.sh`) generates temporary playbooks in a world-readable `tmp/` directory.
- **Impact**: Sensitive configuration, Jinja2 lookups, or extra variables passed via the command line could be exposed to other users on the system. Playbooks are preserved on failure, increasing the window of exposure.
- **Recommendation**: Set `chmod 700` on the `tmp/` directory and ensure generated playbooks are created with `0600` permissions. Implement a `trap` for cleanup.

### Potential Command Injection in Wrappers
- **Risk**: Passthrough of `EXTRA_ARGS` to `ansible-playbook` without strict validation.
- **Impact**: While mitigated by Bash array handling, complex malicious arguments could potentially manipulate the Ansible execution flow.
- **Recommendation**: Sanitize or whitelist allowed flags in `EXTRA_ARGS`.

### Race Conditions in Service Deployment
- **Risk**: Reliance on fixed `wait_for: timeout: 10` after writing Quadlet files.
- **Impact**: Potential for non-deterministic behavior during high system load, leading to failed service starts or inconsistent state.
- **Recommendation**: Implement a more robust "wait for unit file" logic or use the `systemd` module's built-in handlers.

### Shell Module for Systemd Operations
- **Risk**: Using `ansible.builtin.shell` for `systemctl --user daemon-reload`.
- **Impact**: Minor security risk due to shell injection (though unlikely with current variables); primarily a maintainability and "Ansible-idiomatic" concern.
- **Recommendation**: Transition to `ansible.builtin.systemd` with `scope: user` where possible.

## 3. Security Strengths (Positives)
- **Rootless by Design**: Containers run under the user's systemd context, significantly limiting the impact of any container breakout.
- **Localhost Default Binding**: Services bind only to `127.0.0.1` by default, preventing accidental network exposure.
- **SELinux Hardening**: Comprehensive labeling (`container_file_t`) and volume flags (`:Z,U`) are applied correctly across all roles.
- **Input Whitelisting**: Scripts like `svc-exec.sh` whitelist supported services, preventing arbitrary role execution.

## 4. Remediation Status
1. [x] Tighten `tmp/` permissions and implement secure temporary file handling in `svc-exec.sh` and `manage-svc.sh`.
2. [x] Standardize directory permissions (`0750`/`0700`) across all roles (Elasticsearch, Mattermost, Gitea, etc.).
3. [x] Secure sensitive configuration files and tokens (e.g., InfluxDB admin token) with `0600` permissions.
4. [x] Implement `no_log: true` for sensitive notification tasks in scripts.
5. [ ] Scrub remaining dummy credentials from `inventory/group_vars/*.yml`.
6. [ ] Audit and tighten `mode` settings in all `ansible.builtin.file` and `ansible.builtin.template` tasks.
