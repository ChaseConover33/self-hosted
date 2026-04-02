# Troubleshooting

Common issues and how to resolve them using the project's scripts.

## Quick Reference

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Services unreachable after reboot | Drives not mounted, containers not started | `./scripts/deploy recover` |
| Services unreachable, Pi is up | Caddy or Pi-hole needs restart | `./scripts/deploy recover` |
| Pi unreachable overnight, SSH hangs | WiFi degraded by Docker veth churn | See [WiFi Degradation](#wifi-degradation-services-unreachable-overnight) |
| DNS not resolving `*.lab.chaseconover.com` | Pi-hole hasn't loaded new config | `./scripts/deploy recover` |
| HTTPS cert errors | Certs expired or not yet provisioned | Wait — Caddy auto-retries. Check logs. |
| Container in restart loop | Bad config or missing volume | `./scripts/deploy status`, then check logs |
| `.local` hostname not resolving | Avahi confused by Docker interfaces | `sudo systemctl restart avahi-daemon` |
| Deploy is slow | Caddy image rebuild or new image pull | Normal for first deploy; subsequent are cached |

## Services Unreachable After Reboot or Crash

This is the most common issue. The Pi has external USB drives that may be slow to initialize, and Docker containers depend on those mounts.

**Fix:**

```bash
./scripts/deploy recover
```

This command:
1. Mounts all external drives from fstab
2. Verifies each drive is mounted (fails if a drive is missing — check USB cables)
3. Restarts the Docker Compose stack via systemd
4. Waits 15 seconds for containers to stabilize
5. Shows container status and count

If `recover` reports a drive is NOT MOUNTED, check:
- Is the USB cable firmly connected?
- Is the drive enclosure powered on?
- Run `dmesg | tail -20` on the Pi to see USB device errors

## DNS Not Resolving

If `*.lab.chaseconover.com` doesn't resolve on your devices:

1. **Check your device's DNS is set to Pi-hole** (`192.168.1.167`)
2. **Run recovery**: `./scripts/deploy recover` (restarts Pi-hole which reloads DNS config)
3. **Flush your device's DNS cache**:
   - Mac: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
   - iPhone: Toggle airplane mode on/off

Pi-hole uses `local=/lab.chaseconover.com/` to answer all homelab queries from local records without forwarding upstream. If this isn't working, the dnsmasq config may not have loaded — a Pi-hole container restart (via `recover`) fixes it.

## HTTPS Certificate Issues

Caddy provisions Let's Encrypt certificates automatically via Route 53 DNS challenge. If you see TLS errors:

### Certs not yet provisioned (new setup or after cert wipe)

Caddy needs 60+ seconds per service to provision each cert (DNS propagation delay). With 10+ services, initial provisioning takes ~10 minutes. Check progress:

```bash
ssh chaseconover@chase-raspberrypi.local
sudo docker logs homelab-caddy-1 2>&1 | grep 'certificate obtained'
```

### Rate limited by Let's Encrypt

If you see `HTTP 429 rateLimited` in Caddy logs, you've hit Let's Encrypt's rate limit from too many failed attempts. The limit resets after 1 hour. Caddy will automatically retry. Just wait.

To avoid this in the future:
- Don't repeatedly restart Caddy while it's provisioning certs
- Don't wipe cert storage unless necessary
- Certs are stored in the `caddy_data` Docker volume and persist across container restarts

### Checking cert status

```bash
ssh chaseconover@chase-raspberrypi.local
sudo docker exec homelab-caddy-1 ls /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/
```

Each service should have a directory. If a service is missing, Caddy is still provisioning it.

### AWS credentials issue

If Caddy logs show `IncompleteSignature` or `AccessDenied`, check `/etc/self-hosted/caddy.env`:
- No trailing whitespace on any line
- No quotes around values
- `AWS_HOSTED_ZONE_ID` matches your Route 53 hosted zone
- IAM user has `route53:ListHostedZones`, `route53:ListHostedZonesByName`, `route53:GetChange`, `route53:ChangeResourceRecordSets`, and `route53:ListResourceRecordSets` permissions

After fixing, the Caddy container must be **recreated** (not just restarted) to pick up env file changes. Run `./scripts/deploy compose`.

## Container in Restart Loop

Check which container is failing:

```bash
./scripts/deploy status
```

Then check its logs on the Pi:

```bash
ssh chaseconover@chase-raspberrypi.local
sudo docker logs <container-name> --tail 30
```

Common causes:
- **Kiwix**: Invalid ZIM files. Uses `--skipInvalid` flag but may still fail if no valid ZIM files exist.
- **Services with databases**: Database container not healthy yet. Usually resolves on its own after a few seconds (healthcheck-gated startup).
- **Missing env file**: Check `ls -la /etc/self-hosted/` for required secret files.

## SSH Connection Issues

### Can't connect at all

```bash
ping 192.168.1.167
```

If no response:
- Is the Pi powered on? Check the LED.
- The Pi runs on WiFi only (no Ethernet cable) — check that the router is up
- Try connecting by IP if mDNS isn't working: `ssh chaseconover@192.168.1.167`

### SSH to IP works but commands hang

If `ssh chaseconover@192.168.1.167` opens an interactive session but
`ssh chaseconover@192.168.1.167 "echo test"` hangs, this is WiFi degradation caused by
NetworkManager managing Docker interfaces. See [WiFi Degradation](#wifi-degradation-services-unreachable-overnight).

**Emergency workaround** (forces PTY allocation for the command):

```bash
ssh -tt chaseconover@192.168.1.167 "echo test"
```

## Services Unreachable, Pi Responds to Ping but Not HTTP/DNS

If the Pi is up (SSH works by IP) but `*.lab.chaseconover.com` doesn't load in your browser:

**Root cause:** After a crash, Pi-hole's config files on the external drive may have I/O errors.
You can verify this by running on the Pi:

```bash
sudo docker exec homelab-pihole-1 cat /etc/pihole/custom.list
```

If you see `I/O error`, the drive had transient issues and the container needs a full restart.

**Fix — restart all containers:**

```bash
sudo systemctl restart homelab-compose
```

If that doesn't resolve it, do a full reboot and recover:

```bash
sudo reboot
# Wait 1-2 minutes, then from your Mac:
./scripts/deploy recover
# Or if deploy can't connect, from the Pi after reconnecting:
sudo mount -a
sudo systemctl restart homelab-compose
```

**Why `deploy recover` alone may not be enough:** The recover playbook mounts drives and
restarts the compose stack via systemd, but if containers were already running with stale
file handles from before the drive remount, they need a full restart to pick up the
now-accessible files.

## WiFi Degradation (Services Unreachable Overnight)

If the Pi becomes unreachable overnight — mDNS stops resolving, HTTPS services are down,
non-interactive SSH (`ssh user@host "command"`) hangs but interactive SSH still works:

**Root cause:** NetworkManager managing Docker's virtual network interfaces (`veth*`,
`br-*`, `docker0`). As containers churn, NetworkManager processes each veth
create/destroy event, flooding the network stack with "carrier lost / carrier acquired"
events. Over hours, this degrades WiFi to the point where only interactive SSH (with PTY)
works. WiFi power management compounds the problem — the chip sleeps during low-traffic
periods and the degraded driver fails to wake it cleanly.

**Prevention (applied by Ansible `base` role):**
- NetworkManager ignores Docker interfaces via `/etc/NetworkManager/conf.d/docker-unmanaged.conf`
- WiFi power save disabled via `/etc/NetworkManager/conf.d/wifi-powersave-off.conf`

**If it happens anyway:**

```bash
# From the Pi (interactive SSH to 192.168.1.167):
sudo systemctl restart NetworkManager
# Wait a few seconds for WiFi to reconnect, then verify:
ssh chaseconover@192.168.1.167 "echo test"
```

**Diagnosis commands:**

```bash
# Check if NetworkManager is managing Docker interfaces (bad — should be empty):
nmcli con show --active | grep -E 'veth|br-|docker'

# Check WiFi power management (should be "off"):
sudo /sbin/iwconfig wlan0 | grep Power

# Check for WiFi driver errors:
dmesg | grep -i brcmf | tail -10
```

## mDNS (`.local` Hostname) Not Working

If `chase-raspberrypi.local` doesn't resolve but `192.168.1.167` works:

**Root cause:** Docker's virtual network interfaces (`veth*`) churning during container
restarts confuses Avahi (mDNS daemon). Avahi logs will show repeated
"New relevant interface / Interface no longer relevant" messages. The NetworkManager
Docker interface fix (above) also helps prevent this.

**Fix:** Restart Avahi after containers have stabilized:

```bash
sudo systemctl restart avahi-daemon
```

Or just connect by IP instead:

```bash
ssh chaseconover@192.168.1.167
```

The Ansible inventory already uses the IP address, so `./scripts/deploy recover` is
unaffected by mDNS issues.

## Full Recovery Sequence After a Crash

If the Pi has crashed and you need to bring everything back, run these steps in order:

1. **Wait for the Pi to boot** (1-2 minutes after power restore)
2. **Connect by IP** (mDNS may not work): `ssh chaseconover@192.168.1.167`
3. **Mount drives**: `sudo mount -a`
4. **Restart all containers**: `sudo systemctl restart homelab-compose`
5. **Verify**: `sudo docker ps --format '{{.Names}}\t{{.Status}}' | sort`
6. **Fix mDNS if needed**: `sudo systemctl restart avahi-daemon`

Or from your Mac (if SSH via IP works for Ansible):

```bash
./scripts/deploy recover
```

**Note:** Some containers (Synapse, Vikunja) may restart-loop for 30-60 seconds after
recovery while waiting for their database containers to become healthy. This is normal
and resolves on its own.

## Icy Box Dock (IB-1232CL-U3) and Drive Mount Issues

The external drives are in an Icy Box IB-1232CL-U3 dual-bay docking station connected
via USB 3.0.

**Known behavior:** When both drives are inserted and the dock powers on (e.g. during a
Pi reboot), the dock may fail to present both drives to the Pi properly. This appears to
be a USB enumeration issue — the dock's ASMedia ASM1153E SATA bridge and the Pi's USB 3.0
controller can conflict when initializing two drives simultaneously.

**Symptoms:**
- One or both drives don't appear in `lsblk` after boot
- `dmesg` shows USB errors or missing SCSI devices
- fstab mount times out and drives are never mounted
- The dock may also enter a cloning standby state when both drives are inserted at
  power-on (the dock has a cloning feature that requires a 5-second button press to
  activate, but the standby state alone may affect drive presentation)

**Workaround:** Unplug drive 2 (disk2) from the dock and reinsert it after boot. This
forces the dock to re-enumerate and present the drive to the Pi. Then mount it:

```bash
sudo mount -a
```

**Potential permanent fixes (not yet implemented):**
- Add a USB quirks parameter to force BOT instead of UAS: identify the dock with `lsusb`,
  then add `usb-storage.quirks=VVVV:PPPP:u` to `/boot/firmware/cmdline.txt`
- Replace the dual-bay dock with two separate USB-to-SATA adapters (eliminates the
  shared controller as a single point of failure)
- Only keep one drive in the dock; insert disk2 only when needed

**Auto-mount retry (not yet implemented):** A systemd timer that periodically retries
`mount -a` would catch late-appearing drives automatically. This should be paired with
a oneshot service triggered by the mount unit (not a `PathExists` watcher — that was
tried and caused continuous restart loops). For now, late-mount recovery is manual via
`./scripts/deploy recover`.

## Drive I/O Errors

If `dmesg | grep -i error` shows `Buffer I/O error on dev sdb` or similar:

- The external USB drive temporarily went offline
- This can cascade and crash the Pi
- Check the USB cable and enclosure power supply
- After reboot: `./scripts/deploy recover`

Persistent journal is enabled (`/var/log/journal/`) so crash logs survive reboots. Check previous boot logs:

```bash
ssh chaseconover@chase-raspberrypi.local
journalctl -b -1 --priority=err --no-pager | tail -30
```

## Diagnostic Commands

All available from your Mac:

| Command | Purpose |
|---------|---------|
| `./scripts/deploy status` | Check all container health |
| `./scripts/deploy recover` | Mount drives, restart stack, verify health |
| `./scripts/deploy validate` | Pre-flight check on Ansible config |
| `./scripts/backup-check chase-raspberrypi.local` | Check backup timer and recent backups |
