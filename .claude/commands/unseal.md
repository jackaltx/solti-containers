# Claude Code Commands for SOLTI Containers

This file defines custom commands that Claude Code can execute for this project.

## /unseal

**Purpose:** Unseal HashiVault and verify it's operational.

**Process:**

1. Load `labenv` environment
2. Execute `./svc-exec.sh hashivault unseal` to unseal the vault
3. Execute `./svc-exec.sh hashivault verify` to confirm unsealing worked
4. Display final vault status (initialized, sealed/unsealed)

**Usage:**

```
/unseal
```

**Prerequisites:**

- HashiVault must be deployed and running (`vault-pod.service` active)
- Vault must be initialized with keys stored at `~/.secrets/vault-secrets/vault-keys.json`
- `labenv` alias must be configured and available
- Environment variables from labenv must be loaded before running svc-exec.sh

**Example execution:**

```bash
# Load environment and run unseal + verify in single shell session
source $HOME/.secrets/LabProvision && \
  ./svc-exec.sh hashivault unseal && \
  ./svc-exec.sh hashivault verify
```

**Expected behavior:**

- Checks if vault is currently sealed
- If sealed, loads unseal keys from `~/.secrets/vault-secrets/vault-keys.json`
- Applies threshold number of unseal keys (default: 3 of 5)
- Verifies vault status shows unsealed
- Runs full verification to confirm API access and health

**Common scenarios:**

- **Vault already unsealed**: Unseal task will detect and skip, verification will proceed
- **Keys file missing**: Task will fail with clear error message
- **Vault not initialized**: Task will fail - run initialization first
- **Pod not running**: Task will fail - deploy vault first with `./manage-svc.sh hashivault deploy`

**Related commands:**

- `/verify-all` - Verify all running services including vault
- `./svc-exec.sh hashivault initialize` - Initialize vault for first time
