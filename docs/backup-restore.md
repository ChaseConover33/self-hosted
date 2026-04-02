# Backup and Restore

## Current Model

Backups are daily tar.gz snapshots stored in three locations for redundancy:

| Location | Drive | Purpose |
|---|---|---|
| `/mnt/disk1/homelab/backups/` | External HDD | Primary — fastest to restore from |
| `/srv/self-hosted/backups/` | SD card | Survives HDD failure |
| `/mnt/disk2/backups/` | Secondary HDD | Survives SD card failure (only if disk2 is mounted) |

Backups are created by:

- `/usr/local/bin/self-hosted-backup`
- `self-hosted-backup.service`
- `self-hosted-backup.timer` (runs daily at 3:15 AM)

Snapshots older than 7 days are automatically purged from all three locations.

## What Gets Backed Up

The backup job archives:

- `/srv/self-hosted/config` — service configs (Caddy, Pi-hole, Synapse, etc.)
- `/srv/self-hosted/compose` — Docker Compose files and .env
- `/mnt/disk1/homelab/data` — service databases (Synapse, Vikunja, Firefly, Gitea, etc.)

## What Is NOT Backed Up

- **Media** (`/mnt/disk1/media/`) — movies, shows, music. Too large; re-acquire if lost.
- **Archive** (`/mnt/disk1/archive/`) — Kiwix ZIM files. Re-downloadable via `scripts/update-archive.sh`.
- **Docker images** — re-pulled automatically on deploy.
- **Secrets** (`/etc/self-hosted/`) — not included in the tar. Back these up manually or add to backup paths if desired.

## Typical Backup Size

- Each daily snapshot: 630 MB - 1.7 GB (compressed)
- 7 days of retention: ~5-6 GB total per location

## Restore Drill

Use a stateful service like Vaultwarden for the first restore test.

1. Stop the affected container.
2. List available backups:
   ```bash
   ls -lh /mnt/disk1/homelab/backups/
   # Or if disk1 is unavailable:
   ls -lh /srv/self-hosted/backups/
   ```
3. Extract the chosen archive into a temporary restore path:
   ```bash
   mkdir /tmp/restore
   tar -xzf /mnt/disk1/homelab/backups/self-hosted-YYYYMMDD-HHMMSS.tar.gz -C /tmp/restore
   ```
4. Copy the restored service data back into the appropriate location:
   ```bash
   # For config (on SD card):
   sudo cp -a /tmp/restore/srv/self-hosted/config/<service> /srv/self-hosted/config/<service>
   # For data (on HDD):
   sudo cp -a /tmp/restore/mnt/disk1/homelab/data/<service> /mnt/disk1/homelab/data/<service>
   ```
5. Restart the stack: `./scripts/deploy deploy`
6. Confirm the application is healthy.

## Checking Backup Health

```bash
./scripts/backup-check chase-raspberrypi.local
```

Or manually:

```bash
ssh chaseconover@192.168.1.167
# Check timer is active
systemctl status self-hosted-backup.timer
# Check recent backups exist in all locations
ls -lh /mnt/disk1/homelab/backups/
ls -lh /srv/self-hosted/backups/
ls -lh /mnt/disk2/backups/
```
