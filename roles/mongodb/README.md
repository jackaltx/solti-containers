# MongoDB Role

Deploys MongoDB as a rootless Podman container with systemd integration using the quadlet pattern.

## Overview

This role deploys:

- **MongoDB Server** (`mongo:7.0`) - Document database
- **Mongo Express** (optional) - Web-based admin interface

## Quick Start

### 1. Prepare (one-time setup)

```bash
./manage-svc.sh mongodb prepare
```

Creates directories and configures the system.

### 2. Deploy

```bash
export MONGODB_ROOT_USERNAME=admin
export MONGODB_ROOT_PASSWORD=your-secure-password
./manage-svc.sh mongodb deploy
```

Deploys and starts MongoDB with Mongo Express GUI.

### 3. Verify

```bash
./svc-exec.sh mongodb verify
```

Runs health checks and functional tests.

### 4. Access

- **MongoDB**: `mongodb://localhost:27017`
- **Mongo Express**: `http://localhost:8081`
- **With Traefik SSL**: `https://mongodb.a0a0.org:8080`

## Configuration

### Environment Variables

```bash
export MONGODB_ROOT_USERNAME=admin              # MongoDB root user (default: admin)
export MONGODB_ROOT_PASSWORD=mysecretpass       # MongoDB root password (required)
export MONGODB_DATABASE=admin                   # Initial database (default: admin)
```

### Inventory Variables

```yaml
mongodb_data_dir: "{{ lookup('env', 'HOME') }}/mongodb-data"
mongodb_port: 27017
mongodb_gui_port: 8081
mongodb_enable_gui: true
mongodb_enable_traefik: false
```

## Directory Structure

```text
~/mongodb-data/
├── config/
│   └── mongod.conf          # MongoDB configuration
├── data/                    # Database data (persistent)
├── logs/                    # MongoDB logs
└── .env                     # Credentials (mode 0600)
```

## Service Management

### Start/Stop

```bash
systemctl --user start mongodb-pod
systemctl --user stop mongodb-pod
systemctl --user status mongodb-pod
```

### Logs

```bash
journalctl --user -u mongodb-pod -f
podman logs mongodb-svc
```

### Remove

```bash
# Preserve data
./manage-svc.sh mongodb remove

# Delete all data and images
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh mongodb remove
```

## Testing

### Connect with mongosh

```bash
podman exec -it mongodb-svc mongosh -u admin -p your-password
```

### Basic operations

```javascript
// Show databases
show dbs

// Create collection and insert document
use testdb
db.users.insertOne({name: "test", email: "test@example.com"})

// Find documents
db.users.find()
```

## Traefik Integration

### Enable SSL

1. Update inventory:

   ```yaml
   mongodb_enable_traefik: true
   ```

2. Create DNS record:

   ```bash
   source ~/.secrets/LabProvision
   ./update-dns-auto.sh firefly
   ```

3. Access: `https://mongodb.a0a0.org:8080`

## Troubleshooting

### Container not starting

```bash
# Check logs
podman logs mongodb-svc

# Check systemd status
systemctl --user status mongodb-pod
```

### Permission issues

```bash
# Verify directory ownership
ls -la ~/mongodb-data/

# Should be owned by your user, not root
```

### Connection refused

```bash
# Verify MongoDB is listening
podman exec mongodb-svc ss -tlnp | grep 27017

# Check firewall
sudo firewall-cmd --list-ports
```

### Reset to clean state

```bash
DELETE_DATA=true DELETE_IMAGES=true ./manage-svc.sh mongodb remove
./manage-svc.sh mongodb prepare
MONGODB_ROOT_PASSWORD=newpass ./manage-svc.sh mongodb deploy
```

## Security Notes

- MongoDB runs with authentication enabled (`security.authorization: enabled`)
- Credentials stored in `~/.config/containers/systemd/env/mongodb.env` (mode 0600)
- Default binding: `localhost` only (not exposed externally)
- For external access, use Traefik with SSL termination

## Performance Tuning

### Increase connection pool

Edit `~/mongodb-data/config/mongod.conf`:

```yaml
net:
  maxIncomingConnections: 1000
```

Then restart:

```bash
systemctl --user restart mongodb-pod
```

## Backup and Restore

### Backup

```bash
podman exec mongodb-svc mongodump --username admin --password yourpass --out /data/backup
cp -r ~/mongodb-data/data/backup ~/backups/mongodb-$(date +%Y%m%d)
```

### Restore

```bash
podman exec mongodb-svc mongorestore --username admin --password yourpass /data/backup
```

## References

- MongoDB Documentation: <https://docs.mongodb.com/>
- Mongo Express: <https://github.com/mongo-express/mongo-express>
- Podman Quadlets: <https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html>
