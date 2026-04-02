# Boot Process

How the Raspberry Pi starts up, what runs in what order, and how the homelab
services come online — with or without external drives.

## What is systemd?

systemd is the init system on Debian (and most modern Linux). It manages everything
that runs after the kernel loads: mounting filesystems, starting services, running
scheduled tasks. It uses "unit files" — small config files that describe what to start,
when, and in what order.

The homelab uses three types of systemd units:

| Type | Purpose | Example |
|---|---|---|
| `.service` | Runs a process (one-shot or long-running) | `homelab-compose.service` starts Docker containers |
| `.timer` | Runs a service on a schedule (like cron) | `self-hosted-backup.timer` runs backups daily at 3:15 AM |
| `.path` | Watches for a file/directory to appear, then triggers a service | (not currently used — see note below) |

## Boot Sequence

Here's what happens when the Pi powers on, step by step:

```
1. Hardware init → kernel loads from SD card
       ↓
2. systemd starts
       ↓
3. local-fs.target — mount all filesystems from /etc/fstab
   ├── SD card (/) — always mounts instantly
   ├── /mnt/disk1 (HDD) — may take 5-30 seconds to spin up
   │   └── nofail flag: if the drive isn't detected within 30 seconds,
   │       systemd marks the mount as "skipped" and moves on
   └── /mnt/disk2 (HDD) — same behavior
       ↓
4. network-online.target — wait for network connectivity
       ↓
5. docker.service — start the Docker daemon
       ↓
6. homelab-compose.service — start all containers
   ├── Reads compose files from /srv/self-hosted/compose/ (SD card — always available)
   ├── Reads .env from /srv/self-hosted/compose/.env (SD card — always available)
   ├── Runs: docker compose up -d --remove-orphans
   └── Containers start and bind-mount their data directories
       ↓
```

## Scenario 1: Normal Boot (drives mount before containers start)

This is the happy path — the HDD spins up fast enough.

1. fstab mounts `/mnt/disk1` successfully
2. `homelab-compose.service` starts containers
3. Containers bind-mount directories like `/mnt/disk1/homelab/data/` — data is there
4. All services come up healthy

**Result:** Everything works.

## Scenario 2: Boot Without Drives (drives mount late)

The HDD is slow to spin up or wasn't plugged in at boot.

1. fstab tries to mount `/mnt/disk1` — times out after 30 seconds, skipped (`nofail`)
2. `homelab-compose.service` starts containers
3. Compose files and configs are on the SD card — Docker can read them fine
4. Containers start but their data bind-mounts point at empty directories:
   - `/mnt/disk1/homelab/data/` → empty (drive not mounted)
   - `/mnt/disk1/media/` → empty
5. **What works:** Caddy (reverse proxy), Pi-hole (DNS), Homepage (dashboard), demo services
6. **What doesn't work:** Database-backed services (Vikunja, Firefly, Gitea) — no database
   files. Jellyfin — no media. Kiwix — no ZIM files. These containers start but are
   unhealthy or show empty content.

**To recover once the drive is available:**

7. Mount the drive: `sudo mount -a`
8. Restart containers: `./scripts/deploy recover`
9. Containers restart with the now-mounted data directories
10. All services come up healthy

**Result:** DNS and basic services work immediately. Data-heavy services require a manual
`./scripts/deploy recover` after the drive mounts.

## Scenario 3: Boot Without Drives (drives never mount)

The HDD is disconnected or dead.

1-6. Same as Scenario 2 — containers start, basic services work
7. Data-heavy services stay unhealthy indefinitely

**Result:** You still have DNS, Caddy, and the dashboard. You can SSH in and diagnose.
Nothing is corrupted — once the drive is reconnected and mounted, run
`./scripts/deploy recover` to bring everything back.

## Do I Need to Clean Up Anything?

**No.** In all scenarios, there's nothing to clean up:

- **Empty bind-mounts:** When containers start without the HDD, they see empty directories.
  They don't create new databases or overwrite anything because the directories are just
  empty mountpoints. When the drive mounts later and containers restart, they see the
  real data — no conflicts.
- **Docker state:** Docker Compose tracks container state separately from data volumes.
  Restarting containers doesn't lose their configuration.
- **The remount restart:** `docker compose restart` gracefully stops and restarts containers.
  It doesn't recreate them or change their configuration — just stops the processes and
  starts them again with the same bind-mounts, which now point to real data.
- **Backups:** The backup timer only runs once daily. If it runs before the drive mounts,
  it backs up the SD card config (which is fine) but can't reach HDD data. The next
  day's backup will include everything.

The only edge case: if a service with a database (like Synapse or Gitea) starts with an
empty data directory, it might initialize a fresh empty database. When the drive mounts
and the container restarts, it picks up the real database from the drive — the empty
one was in memory only and is discarded. Your real data is untouched.

## systemd Units Reference

All unit files are installed to `/etc/systemd/system/` by Ansible during deploy.

### homelab-compose.service

**Type:** OneShot (runs once, stays "active" after completion)
**Triggered by:** Boot (multi-user.target)
**What it does:** Runs `docker compose up -d` to start all containers
**Depends on:** docker.service, local-fs.target, network-online.target
**Waits for:** External drive mount units (but doesn't fail if they're skipped)
**Template:** `ansible/roles/compose/templates/homelab-compose.service.j2`

### homelab-compose-remount.path (DISABLED)

A path watcher was created to auto-restart containers when the HDD mounts. It used
`PathExists=/mnt/disk1/homelab/data` to detect the mount, then triggered a `docker
compose restart`. **This caused continuous restart loops** because `PathExists` fires
repeatedly whenever the condition is true, not just once. It has been stopped and
disabled.

**Lesson learned:** `PathExists` is not suitable for one-time triggers. A better
approach would be to tie a oneshot service to the mount unit itself (e.g.
`BindsTo=mnt-disk1.mount` + `After=mnt-disk1.mount`), or use a systemd timer that
checks mount status and stops itself after success.

For now, late-mount recovery is manual: `./scripts/deploy recover`.

### self-hosted-backup.timer / self-hosted-backup.service

**Type:** Timer + OneShot service
**Schedule:** Daily at 3:15 AM
**What it does:** Creates a tar.gz of config, data, and compose directories. Copies to
SD card and disk2. Purges backups older than 7 days.
**Template:** `ansible/roles/backup/templates/backup.sh.j2`

### self-hosted-healthcheck.timer / self-hosted-healthcheck.service

**Type:** Timer + OneShot service
**Schedule:** Every hour
**What it does:** Captures lightweight host health data (disk usage, etc.)
**Template:** `ansible/roles/monitoring/templates/host-healthcheck.sh.j2`

## Known Issue: Icy Box Dock (IB-1232CL-U3)

The external drives are connected through an Icy Box IB-1232CL-U3 dual-bay USB 3.0
docking station. When the Pi reboots, the dock also loses power and reinitializes.
With both drives inserted, the dock sometimes fails to enumerate both drives to the
Pi's USB controller — one or both drives may not appear.

This means Scenario 2 (drives mount late) or Scenario 3 (drives never mount) can be
triggered not by the Pi, but by the dock's behavior. The workaround is to unplug drive 2
from the dock and reinsert it after the Pi has booted, then run `sudo mount -a`.

See [Troubleshooting > Icy Box Dock](troubleshooting.md#icy-box-dock-ib-1232cl-u3-and-drive-mount-issues)
for details and potential permanent fixes.

## Useful systemd Commands

Run these on the Pi to inspect the boot process:

```bash
# Check if a service is running
sudo systemctl status homelab-compose.service

# Check if the drive watcher is active (currently disabled)
# sudo systemctl status homelab-compose-remount.path

# See the full boot log for the current boot
journalctl -b

# See errors from the previous boot (useful after a crash)
journalctl -b -1 --priority=err --no-pager

# See what order units started in
systemd-analyze critical-chain homelab-compose.service

# See how long each unit took to start
systemd-analyze blame | head -20

# Manually restart the compose stack
sudo systemctl restart homelab-compose

# Manually trigger the remount service (same as drive appearing)
sudo systemctl start homelab-compose-remount.service
```
