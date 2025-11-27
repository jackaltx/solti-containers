# Claude Code Commands for SOLTI Containers

This file defines the `/lint-fix` command for incremental lint remediation.

## /lint-fix [count]

**Purpose:** Fix a batch of lint errors incrementally to reduce technical debt.

**Process:**

1. **Analyze current lint state:**
   - Run `yamllint .` and capture warnings/errors
   - Run `ansible-lint --offline` and capture violations
   - Run `markdownlint "**/*.md"` and capture issues
   - Categorize errors by severity: CRITICAL → IMPORTANT → MINOR → TRIVIAL

2. **Prioritize fixes:**
   - **CRITICAL** (blocking): Syntax errors, load failures, conflicting statements
   - **IMPORTANT** (best practices): no-changed-when, command-instead-of-module, risky-file-permissions
   - **MINOR** (style): truthy values (yes/no vs true/false), task name casing
   - **TRIVIAL** (formatting): comment spacing, braces, trailing spaces, line length

3. **Fix batch of errors:**
   - Fix up to `count` errors (default: 10, max: 25 per invocation)
   - Start with highest priority category first
   - Apply fixes systematically (e.g., all truthy in one file, then move to next)
   - Prefer automated fixes when safe (spacing, formatting)
   - Use manual judgment for logic changes (changed_when, module selection)

4. **Verify fixes:**
   - Re-run linters to confirm errors are resolved
   - Ensure no new errors introduced
   - Check that changes are minimal and focused

5. **Create checkpoint commit:**
   - Stage all changes: `git add -A`
   - Commit with descriptive message: `git commit -m "chore: fix [count] lint errors ([categories])"`
   - Example: `"chore: fix 10 lint errors (yaml truthy, comment spacing)"`

6. **Report progress:**
   - Display: "Fixed [count] errors. [remaining] errors remaining."
   - Break down by category: "CRITICAL: 0, IMPORTANT: 5, MINOR: 20, TRIVIAL: 130"
   - Update `.lint-progress.yml` with new baseline

**Usage:**

```bash
# Fix 10 errors (default)
/lint-fix

# Fix 20 errors
/lint-fix 20

# Fix all remaining errors (use with caution on test branch before PR to main)
/lint-fix --all
```

**Arguments:**

- `count` (optional): Number of errors to fix (default: 10, max: 25). Use `--all` to fix all errors.

**Prerequisites:**

- Working directory is clean or changes are committed
- Linters installed: yamllint, ansible-lint, markdownlint-cli
- `.lint-progress.yml` exists (created automatically if missing)

**Expected behavior:**

- Focuses on one category at a time for consistency
- Creates atomic commits (one commit per batch)
- Updates progress tracker after each batch
- Warns if attempting to fix more than 25 errors at once (except --all)
- Fails gracefully if no errors found

**Configuration:**

The `.ansible-lint`, `.yamllint`, and `.markdownlintrc` files control what's considered an error vs warning.

**Integration with workflow:**

This command is designed to be used during development on the `test` branch:
1. Make feature changes
2. Run `/lint-fix 10` to clean up some lint errors
3. Push to test branch (CI allows warnings)
4. Repeat over time
5. Before PR to main: run `/lint-fix --all` to reach zero errors
6. PR to main passes strict lint checks

**Progress tracking:**

The `.lint-progress.yml` file tracks:
- Baseline error count (starting point)
- Current error count
- Last update date
- Target date for zero errors

Example `.lint-progress.yml`:
```yaml
---
baseline_errors: 1800
current_errors: 145
last_updated: "2025-11-27"
categories:
  critical: 0
  important: 12
  minor: 35
  trivial: 98
target_date: "2025-12-15"
```

**Notes:**

- CRITICAL errors should be fixed immediately (they break functionality)
- IMPORTANT errors affect idempotency, security, and best practices
- MINOR errors are style inconsistencies
- TRIVIAL errors are pure formatting (can often be auto-fixed)
- The `warn_list` in `.ansible-lint` prevents trivial errors from blocking CI
- Main branch PRs require zero errors (strict mode)
- Test branch allows warnings (incremental improvement mode)
