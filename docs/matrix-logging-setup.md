# Matrix Development Logging System

Automated logging system for solti-containers deployments, tasks, and tests to Matrix room.

## Overview

This system sends structured log messages to a Matrix room for tracking:
- Service deployments (deploy/remove)
- Task executions (verify/configure)
- Test results (molecule runs)
- Ad-hoc development messages

**Message Format**: Dual format with emoji-rich human-readable text AND JSON structured data

## Setup (One-time)

### Prerequisites

- Matrix homeserver running at matrix-web.jackaltx.com
- Admin access token in `~/.secrets/matrix-admin-passwd`
- solti-matrix-mgr collection installed

### Step 1: Create Bot User

```bash
cd /home/lavender/sandbox/ansible/jackaltx/mylab
ansible-playbook playbooks/setup-matrix-logger-bot.yml \
  --extra-vars "admin_token=$(cat ~/.secrets/matrix-admin-passwd)"
```

**Creates**:
- Bot user: `@solti-logger:jackaltx.com`
- Credentials: `mylab/data/matrix-logger-bot.yml` (mode 0600)

### Step 2: Get Bot Access Token

```bash
cd /home/lavender/sandbox/ansible/jackaltx/mylab
./bin/get-matrix-token.sh
```

**Creates**:
- Access token: `mylab/data/matrix-logger-token.txt` (mode 0600)

**Verify**:
```bash
TOKEN=$(cat mylab/data/matrix-logger-token.txt)
curl -s "https://matrix-web.jackaltx.com/_matrix/client/v3/account/whoami" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
# Should return: {"user_id": "@solti-logger:jackaltx.com"}
```

### Step 3: Create Matrix Room

```bash
cd /home/lavender/sandbox/ansible/jackaltx/mylab
ansible-playbook playbooks/create-matrix-logger-room.yml
```

**Creates**:
- Room: "SOLTI Containers - Development Logs"
- Alias: `#solti-containers-dev:jackaltx.com`
- Room ID: `mylab/data/matrix-logger-room.txt` (mode 0600)

**Alternative (Manual)**:
1. Login to https://matrix.jackaltx.com via Element
2. Create room "SOLTI Containers - Development Logs"
3. Invite `@solti-logger:jackaltx.com`
4. Copy room ID from Room Settings → Advanced
5. Save to `mylab/data/matrix-logger-room.txt`

### Step 4: Generate Config

```bash
cd /home/lavender/sandbox/ansible/jackaltx/mylab
./bin/setup-logger-config.sh
```

**Creates**:
- Config: `solti-containers/data/matrix-logger.conf` (mode 0600)

---

## Usage

### Manual Logging

```bash
cd /home/lavender/sandbox/ansible/jackaltx/solti-containers

# Simple message
./bin/matrix-log.py message "Test deployment started"

# Deployment event
./bin/matrix-log.py deployment redis monitor11 success \
  --duration 45 --details containers=2 ports=6379

# Task execution
./bin/matrix-log.py task redis monitor11 verify success --duration 5.2

# Test result
./bin/matrix-log.py test redis debian12 success --duration 180 --tests "5/5"

# Warning message
./bin/matrix-log.py message "Deployment slow" --level warning

# Dry run (test without sending)
./bin/matrix-log.py --dry-run message "Testing"
```

### Automatic Logging

Logging is automatically integrated into:

1. **manage-svc.sh** - Logs deployment start and completion
   ```bash
   ./manage-svc.sh redis deploy
   # Sends: "Starting deploy: redis on all"
   # Sends: "Deploy: redis@all ✅ SUCCESS ⏱️ 45s"
   ```

2. **svc-exec.sh** - Logs task execution
   ```bash
   ./svc-exec.sh redis verify
   # Sends: "Starting task: redis/verify on all"
   # Sends: "Task: redis/verify@all ✅ SUCCESS ⏱️ 5s"
   ```

---

## Message Format

### Human-Readable (Emoji)

```
🚀 Deploy: redis@monitor11
✅ Status: SUCCESS
⏱️ Duration: 45.0s
  containers: 2
  ports: 6379
```

### Structured JSON (Machine-Parsable)

Attached in custom field `dev.solti.log_data`:
```json
{
  "event_type": "deployment",
  "service": "redis",
  "host": "monitor11",
  "status": "success",
  "timestamp": "2026-02-09T12:34:56+00:00",
  "user": "lavender",
  "duration_seconds": 45,
  "details": {
    "containers": "2",
    "ports": "6379"
  }
}
```

**Note**: Duration values are automatically converted to integers (whole seconds) or strings (fractional seconds like "5.2") for Matrix JSON compatibility.

---

## Viewing Logs

### Via Element Web Client

1. Open https://matrix.jackaltx.com
2. Login
3. Find room: `#solti-containers-dev:jackaltx.com`
4. View messages and JSON data

### Via API (Future)

Query structured data for dashboards, reports, or automation.

---

## Configuration

### Config File

Location: `solti-containers/data/matrix-logger.conf`

```json
{
  "homeserver_url": "http://matrix-web.jackaltx.com:8008",
  "access_token": "YOUR_TOKEN",
  "room_id": "!abc123:jackaltx.com"
}
```

### Environment Variables

Override config file:
```bash
export MATRIX_HOMESERVER="http://matrix-web.jackaltx.com:8008"
export MATRIX_TOKEN="your_token"
export MATRIX_ROOM_ID="!abc123:jackaltx.com"
```

### CLI Overrides

```bash
./bin/matrix-log.py --token TOKEN --room ROOM_ID --homeserver URL message "Test"
```

---

## Troubleshooting

### Matrix logging not working

**Check prerequisites**:
```bash
# Check bot token exists
ls -l mylab/data/matrix-logger-token.txt

# Check room ID exists
ls -l mylab/data/matrix-logger-room.txt

# Check config exists
ls -l solti-containers/data/matrix-logger.conf

# Check script is executable
ls -l solti-containers/bin/matrix-log.py
```

**Test manually**:
```bash
cd /home/lavender/sandbox/ansible/jackaltx/solti-containers
./bin/matrix-log.py --dry-run message "Test"
# Should print message without errors

./bin/matrix-log.py message "Real test"
# Should send to Matrix room
```

**Check script is found**:
```bash
cd /home/lavender/sandbox/ansible/jackaltx/solti-containers
[[ -x "./bin/matrix-log.py" ]] && echo "Found and executable" || echo "NOT FOUND or NOT EXECUTABLE"
```

### Messages not appearing in room

**Verify bot can send**:
```bash
TOKEN=$(cat /home/lavender/sandbox/ansible/jackaltx/mylab/data/matrix-logger-token.txt)
ROOM_ID=$(cat /home/lavender/sandbox/ansible/jackaltx/mylab/data/matrix-logger-room.txt)

curl -X POST "https://matrix-web.jackaltx.com/_matrix/client/v3/rooms/${ROOM_ID}/send/m.room.message" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"msgtype":"m.text","body":"Test from curl"}'
```

**Check bot is in room**:
- Open Element
- Go to room
- Check members list includes `@solti-logger:jackaltx.com`

### Deployments failing after adding logging

Logging is designed to NEVER break deployments:
- All logging calls use `|| true` (ignore failures)
- Script checked for executability before calling
- Errors redirected to `/dev/null`

**If deployments break**:
```bash
# Disable logging temporarily
chmod -x /home/lavender/sandbox/ansible/jackaltx/solti-containers/bin/matrix-log.py

# Scripts will skip logging (checks -x flag)
```

**Re-enable**:
```bash
chmod +x /home/lavender/sandbox/ansible/jackaltx/solti-containers/bin/matrix-log.py
```

---

## Disabling Logging

### Temporary (per-execution)

Remove execute permission:
```bash
chmod -x solti-containers/bin/matrix-log.py
```

Scripts check `-x` flag and skip logging automatically.

### Permanent

Remove integration from scripts:
```bash
cd solti-containers
git checkout manage-svc.sh svc-exec.sh
```

---

## Security

- **Bot credentials**: Mode 0600, stored in `mylab/data/` (git-ignored)
- **Access token**: Never logged or displayed
- **Room**: Private, invite-only
- **Encryption**: Disabled (easier parsing, acceptable for dev logs)
- **Bot permissions**: Non-admin, minimal privileges
- **No sensitive data**: Don't log passwords, tokens, or secrets

---

## Future Enhancements (Phase 2)

1. **Webhook Integration**: Hookshot endpoints for CI/CD
2. **GitHub Actions**: Automatic molecule test result posting
3. **Thread Replies**: Multi-step deployment tracking
4. **Reactions**: Status updates (✅, ❌, ⚠️)
5. **File Uploads**: Test reports, diagnostics
6. **Dashboards**: Query structured data for metrics

---

## Files Reference

### Created Files

**mylab/** (infrastructure):
- `playbooks/setup-matrix-logger-bot.yml` - Bot creation
- `playbooks/create-matrix-logger-room.yml` - Room creation
- `bin/get-matrix-token.sh` - Token acquisition
- `bin/setup-logger-config.sh` - Config generation
- `data/matrix-logger-bot.yml` - Bot credentials (auto-generated)
- `data/matrix-logger-token.txt` - Access token (auto-generated)
- `data/matrix-logger-room.txt` - Room ID (auto-generated)

**solti-containers/** (logging):
- `bin/matrix-log.py` - Core logging script
- `data/matrix-logger.conf` - Config file (auto-generated)

### Modified Files

**solti-containers/**:
- `manage-svc.sh` - Added deployment logging hooks
- `svc-exec.sh` - Added task execution logging hooks

---

## Support

Issues or questions:
- Check this document first
- Review plan file: `/home/lavender/.claude/plans/reactive-humming-nygaard.md`
- Test with `--dry-run` flag
- Check Matrix room for bot activity
