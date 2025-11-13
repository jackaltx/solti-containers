# Claude Code Commands for SOLTI Containers

This file defines custom commands that Claude Code can execute for this project.

## /verify-all

**Purpose:** Discover all supported services and run verification for each one.

**Process:**

1. Discover which services have `verify.yml` files by checking `roles/*/tasks/verify.yml`
2. Exclude services that require sudo (wazuh) or are not currently running
3. Load `labenv` environment once
4. Execute `./svc-exec.sh <service> verify` for each service with verify.yml
5. Report summary of passed/failed/skipped verifications

**Usage:**

```
/verify-all
```

**Prerequisites:**

- `labenv` alias must be configured and available
- Environment variables from labenv must be loaded before running svc-exec.sh

**Example execution:**

```bash
# Check for services with verify.yml
ls roles/*/tasks/verify.yml

# Load environment and run all verifications in single shell session
labenv; ./svc-exec.sh elasticsearch verify; ./svc-exec.sh redis verify; ./svc-exec.sh mattermost verify; ...
```

**Expected behavior:**

- Claude discovers services with verify.yml files dynamically from roles/*/tasks/verify.yml
- Loads labenv environment using the alias directly
- Runs verification for all services with verify tasks sequentially in same shell
- Provides summary with pass/fail status for each service
- Reports which services were skipped (no verify.yml)
