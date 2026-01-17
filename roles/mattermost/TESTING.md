# Mattermost Role Testing Guide

## Quick Test Commands

### 1. Prepare (One-time Setup)

```bash
./manage-svc.sh mattermost prepare
```

**Expected Results:**
- Creates `~/mattermost-data/` directory structure
- Creates subdirectories: config, data, logs, postgres
- Creates container network `ct-net`
- Applies SELinux contexts (RHEL-based systems)

### 2. Deploy Service

```bash
./manage-svc.sh mattermost deploy
```

**Expected Results:**
- Creates Podman pod named `mattermost`
- Creates PostgreSQL container `mattermost-db`
- Creates Mattermost container `mattermost-svc`
- Generates systemd unit `mattermost-pod.service`
- PostgreSQL initializes database
- Mattermost performs initial setup (~30-60 seconds)
- Starts service automatically
- Runs verification checks

### 3. Verify Deployment

```bash
# Automated verification
./svc-exec.sh mattermost verify

# Manual checks
systemctl --user status mattermost-pod
podman ps --filter pod=mattermost
curl -I http://127.0.0.1:8065
```

**Expected Results:**
- Pod status: Running
- Two containers: mattermost-db (Up), mattermost-svc (Up)
- HTTP response: 200 or 307 (redirect to /login)
- PostgreSQL accepting connections on port 5432
- Service accessible via browser

### 4. Access Application

Open browser to:
- HTTP: <http://127.0.0.1:8065>
- With Traefik: <https://mattermost.a0a0.org:8080>

**Expected Results:**
- Mattermost login/setup page loads
- Can create initial admin account
- Can create team
- Can create channel
- Can send messages

### 5. Initial Setup Test

```bash
# Access Mattermost
# Browser: http://127.0.0.1:8065

# Create admin account (via browser):
# - Email: admin@example.com
# - Username: admin
# - Password: Admin123!

# Create team (via browser):
# - Team name: Test Team
# - Team URL: test-team
```

**Expected Results:**
- Admin account created successfully
- Email confirmation skipped (local deployment)
- Team created
- Default channels created (Town Square, Off-Topic)

### 6. Database Verification

```bash
# Check PostgreSQL status
podman exec mattermost-db pg_isready -U mmuser -d mattermost

# View database tables
podman exec mattermost-db psql -U mmuser -d mattermost -c "\dt"

# Check user count
podman exec mattermost-db psql -U mmuser -d mattermost -c "SELECT count(*) FROM users;"
```

**Expected Results:**
- PostgreSQL accepting connections
- Tables created (users, teams, channels, posts, etc.)
- User count > 0 (after creating admin account)

### 7. Check Logs

```bash
# Mattermost application logs
podman logs mattermost-svc

# PostgreSQL logs
podman logs mattermost-db

# Systemd logs
journalctl --user -u mattermost-pod -n 50

# Follow logs in real-time
podman logs -f mattermost-svc
```

**Expected Results:**
- No ERROR messages in steady state
- PostgreSQL shows successful connections
- Mattermost shows "Server is listening on :8065"

### 8. Remove Service

```bash
# Preserve data
./manage-svc.sh mattermost remove

# Verify removal
systemctl --user status mattermost-pod  # Should fail
podman ps -a | grep mattermost          # Should be empty

# Check data preserved
ls -la ~/mattermost-data/               # Should still exist
ls ~/mattermost-data/postgres/          # Database files preserved
```

**Expected Results:**
- Containers stopped and removed
- Pod removed
- Systemd unit removed
- Data directory intact
- Can redeploy without losing data

### 9. Complete Cleanup

```bash
# Remove data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh mattermost remove

# Verify complete removal
ls ~/mattermost-data/                   # Should not exist
podman images | grep mattermost         # Should be empty
podman images | grep postgres           # Should be empty (if not used elsewhere)
```

## Common Test Scenarios

### Scenario 1: Database Connection Issues

If Mattermost cannot connect to PostgreSQL:

```bash
# Check PostgreSQL is running
podman exec mattermost-db pg_isready

# Check environment variables
podman exec mattermost-svc env | grep -E 'MM_SQL|POSTGRES'

# Check PostgreSQL logs
podman logs mattermost-db | grep -i error

# Verify database exists
podman exec mattermost-db psql -U mmuser -d mattermost -c "SELECT version();"
```

**Fix**: Redeploy if database not initialized correctly
```bash
./manage-svc.sh mattermost remove
./manage-svc.sh mattermost deploy
```

### Scenario 2: Port Conflicts

If port 8065 is already in use:

```bash
# Check what's using the port
ss -tlnp | grep 8065

# Override in inventory
# Edit inventory/localhost.yml:
mattermost_port: 8066

# Redeploy
./manage-svc.sh mattermost remove
./manage-svc.sh mattermost deploy
```

### Scenario 3: Custom Database Password

```bash
# Edit inventory/localhost.yml:
mattermost_postgres_password: "MySecurePass123!"

# Deploy with custom password
./manage-svc.sh mattermost deploy

# Verify password works
podman exec mattermost-db psql -U mmuser -d mattermost -W
# Enter: MySecurePass123!
```

### Scenario 4: Remote Host Deployment

```bash
# Add to inventory/podma.yml
mattermost_svc:
  hosts:
    podma:
      mattermost_svc_name: "mattermost-podma"
  vars:
    mattermost_port: 8065
    mattermost_postgres_password: "SecureRemotePass"

# Deploy
./manage-svc.sh -h podma -i inventory/podma.yml mattermost prepare
./manage-svc.sh -h podma -i inventory/podma.yml mattermost deploy
```

### Scenario 5: Traefik Integration

```bash
# Enable Traefik (edit inventory)
mattermost_enable_traefik: true

# Update DNS
source ~/.secrets/LabProvision
./update-dns-auto.sh firefly

# Access via HTTPS
curl -I https://mattermost.a0a0.org:8080
```

### Scenario 6: Data Migration Test

```bash
# Deploy and create test data
./manage-svc.sh mattermost deploy
# Create team, channels, posts via browser

# Remove service (preserve data)
./manage-svc.sh mattermost remove

# Redeploy
./manage-svc.sh mattermost deploy

# Verify data persisted
# Check browser: team, channels, posts should still exist
```

## Verification Checklist

After deployment, verify:

- [ ] Pod running: `systemctl --user is-active mattermost-pod`
- [ ] PostgreSQL up: `podman ps --filter name=mattermost-db`
- [ ] Mattermost up: `podman ps --filter name=mattermost-svc`
- [ ] Port 8065 listening: `ss -tlnp | grep 8065`
- [ ] PostgreSQL accepting connections: `podman exec mattermost-db pg_isready`
- [ ] Database initialized: `podman exec mattermost-db psql -U mmuser -d mattermost -c "\dt"`
- [ ] Web interface loads in browser
- [ ] Can create admin account
- [ ] Can create team
- [ ] Can create channels
- [ ] Can send messages
- [ ] Data persists in `~/mattermost-data/`
- [ ] Logs accessible: `podman logs mattermost-svc`
- [ ] Traefik labels correct (if enabled)

## Troubleshooting Tests

### Test 1: PostgreSQL Health

```bash
# Check if PostgreSQL is ready
podman exec mattermost-db pg_isready -U mmuser -d mattermost

# Check database size
podman exec mattermost-db psql -U mmuser -d mattermost -c "SELECT pg_size_pretty(pg_database_size('mattermost'));"

# List all databases
podman exec mattermost-db psql -U mmuser -l
```

**Expected**: PostgreSQL ready, database exists, size > 0

### Test 2: Container Communication

```bash
# Test PostgreSQL network connectivity from Mattermost container
podman exec mattermost-svc ping -c 2 mattermost-db

# Check DNS resolution within ct-net
podman exec mattermost-svc nslookup mattermost-db
```

**Expected**: Successful ping, DNS resolves to container IP

### Test 3: Volume Mounts

```bash
# Check Mattermost data mount
podman inspect mattermost-svc | jq '.[0].Mounts[] | select(.Destination == "/mattermost/data")'

# Check PostgreSQL data mount
podman inspect mattermost-db | jq '.[0].Mounts[] | select(.Destination == "/var/lib/postgresql/data")'
```

**Expected**: Source paths match `~/mattermost-data/{data,postgres}`

### Test 4: Environment Variables

```bash
# Mattermost config
podman inspect mattermost-svc | jq '.[0].Config.Env' | grep MM_

# PostgreSQL config
podman inspect mattermost-db | jq '.[0].Config.Env' | grep POSTGRES
```

**Expected**: Database credentials match inventory settings

### Test 5: Database Schema

```bash
# Verify core tables exist
podman exec mattermost-db psql -U mmuser -d mattermost -c "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('users', 'teams', 'channels', 'posts')
ORDER BY table_name;
"
```

**Expected**: All core tables present

## Performance Testing

### Initial Startup Time

```bash
# Deploy and time until ready
time (./manage-svc.sh mattermost deploy && \
  until curl -sf http://127.0.0.1:8065 >/dev/null; do sleep 1; done)
```

**Expected**: < 90 seconds (first deployment), < 30 seconds (subsequent)

### Response Time

```bash
# Homepage load time
time curl -I http://127.0.0.1:8065

# API endpoint
time curl -s http://127.0.0.1:8065/api/v4/system/ping
```

**Expected**: < 1 second for both

### Container Memory Usage

```bash
podman stats --no-stream --format "{{.Name}}\t{{.MemUsage}}" \
  mattermost-svc mattermost-db
```

**Expected**:
- PostgreSQL: < 200MB idle, < 500MB under load
- Mattermost: < 300MB idle, < 1GB under load

### Database Query Performance

```bash
# User lookup query
time podman exec mattermost-db psql -U mmuser -d mattermost -c \
  "SELECT username FROM users LIMIT 10;"
```

**Expected**: < 100ms

## Functional Testing

### Test 1: User Management

```bash
# Create test user via API (after initial setup)
curl -i -X POST http://127.0.0.1:8065/api/v4/users \
  -H "Content-Type: application/json" \
  -d '{
    "email": "testuser@example.com",
    "username": "testuser",
    "password": "Test123!"
  }'
```

**Expected**: HTTP 201 Created, user returned in JSON

### Test 2: Team/Channel Creation

Via browser:
1. Create team "QA Team"
2. Create channel "testing"
3. Post message "Test message"

**Expected**: All operations succeed, data visible in database

### Test 3: Data Persistence

```bash
# Create data, restart service
# (create team/channel via browser)
systemctl --user restart mattermost-pod

# Wait for startup
sleep 30

# Check data persisted
curl -s http://127.0.0.1:8065 | grep -i "mattermost"
```

**Expected**: Service restarts, data intact

### Test 4: PostgreSQL Backup/Restore

```bash
# Backup database
podman exec mattermost-db pg_dump -U mmuser mattermost > \
  ~/mattermost-backup-$(date +%Y%m%d).sql

# Verify backup file
ls -lh ~/mattermost-backup-*.sql
head -20 ~/mattermost-backup-*.sql
```

**Expected**: Backup file created, contains SQL DDL/DML

## Regression Testing

Before releasing updates, run complete test suite:

```bash
# Full lifecycle test
./manage-svc.sh mattermost prepare
./manage-svc.sh mattermost deploy
sleep 60  # Wait for full initialization
./svc-exec.sh mattermost verify

# Create test data via browser
# - Create admin: admin@test.com / Admin123!
# - Create team: regression-test
# - Create channel: automated-tests
# - Post message: "Regression test $(date)"

# Verify data persists across restart
systemctl --user restart mattermost-pod
sleep 30
curl -s http://127.0.0.1:8065 | grep "Mattermost"

# Remove and verify data preservation
./manage-svc.sh mattermost remove
ls ~/mattermost-data/postgres/  # Database files should exist

# Redeploy and verify data intact
./manage-svc.sh mattermost deploy
sleep 60
# Browser: verify team/channel/posts still exist

# Complete cleanup
DELETE_DATA=true ./manage-svc.sh mattermost remove
ls ~/mattermost-data/  # Should not exist
```

## Integration Testing

### With Traefik (SSL Termination)

```bash
# Deploy both services
./manage-svc.sh traefik deploy
./manage-svc.sh mattermost deploy

# Verify Traefik routing
curl -I https://mattermost.a0a0.org:8080

# Check Traefik dashboard
curl -s http://localhost:8080/api/http/routers | jq '.[] | select(.name | contains("mattermost"))'
```

**Expected**: HTTPS access works, Traefik routes to Mattermost

### With HashiVault (Future - Credential Management)

```bash
# Deploy HashiVault
./manage-svc.sh hashivault deploy

# Store Mattermost credentials (future enhancement)
# podman exec hashivault-svc vault kv put secret/mattermost \
#   postgres_password="SecurePass123"

# Reference in deployment (not yet implemented)
```

## Expected Test Results Summary

| Test | Expected Result | Pass/Fail |
|------|-----------------|-----------|
| Prepare | Directories created, SELinux applied | |
| Deploy | Pod + 2 containers running, PostgreSQL initialized | |
| Verify | All checks pass, service accessible | |
| Access | Browser loads Mattermost interface | |
| Create Admin | Account created, can login | |
| Create Team | Team created, accessible | |
| Create Channel | Channel created, can post messages | |
| Data Persistence | Data survives service restart | |
| PostgreSQL Health | Database accepting connections, tables exist | |
| Traefik SSL | HTTPS access via domain name | |
| Remove | Service stopped, quadlets removed | |
| Cleanup | All data and images removed | |

## Notes

- **First startup takes 60-90 seconds**: PostgreSQL initialization + Mattermost schema setup
- **PostgreSQL port 5432 is internal**: Only accessible within ct-net, not from host
- **Database credentials**: Default password is "changeme", change in production
- **Email not configured**: Email notifications won't work in test deployment
- **Browser caching**: Use incognito mode or hard refresh for testing
- **SELinux issues**: Show as permission errors in PostgreSQL logs, re-run prepare
- **Port conflicts**: Show as "address already in use", change port in inventory
- **Database migration**: PostgreSQL version changes may require manual migration

## Common Errors

### "database system was interrupted"

PostgreSQL didn't shut down cleanly:

```bash
# Remove corrupted state
rm -f ~/mattermost-data/postgres/postmaster.pid
systemctl --user restart mattermost-pod
```

### "relation does not exist"

Database schema not initialized:

```bash
# Check Mattermost logs for migration errors
podman logs mattermost-svc | grep -i migration

# If needed, reinitialize
DELETE_DATA=true ./manage-svc.sh mattermost remove
./manage-svc.sh mattermost deploy
```

### "connection refused" from Mattermost to PostgreSQL

Containers can't communicate via ct-net:

```bash
# Check network
podman network inspect ct-net

# Verify both containers on network
podman inspect mattermost-svc | jq '.[0].NetworkSettings.Networks'
podman inspect mattermost-db | jq '.[0].NetworkSettings.Networks'

# Recreate if needed
./manage-svc.sh mattermost remove
./manage-svc.sh mattermost prepare
./manage-svc.sh mattermost deploy
```
