# Operations

## Deployment Commands

- `./scripts/deploy bootstrap`
  - full first-time host bootstrap and initial deployment
- `./scripts/deploy deploy`
  - re-render all configs (Caddy, Pi-hole DNS, secrets, etc.) and re-apply the container stack — runs every Ansible role
- `./scripts/deploy compose`
  - fast path — only copies compose files and runs `docker compose up`. Use this when you've only changed Docker Compose service definitions (e.g. image versions, environment variables, volume mounts) and don't need to re-render Caddy, Pi-hole DNS, firewall rules, or secrets
- `./scripts/deploy recover`
  - use after a crash or reboot when services are unreachable — mounts external drives, restarts the compose stack, and verifies all containers are running
- `./scripts/deploy status`
  - check health of all running containers without changing anything — shows each container's state and a summary count
- `./scripts/deploy validate`
  - validate inventory assumptions on the remote target (pre-flight checks only, does not deploy)

**When to use `deploy` vs `compose`:**

| What changed | Command |
|---|---|
| Added/removed a service in `all.yml` | `deploy` (needs Caddy, Pi-hole DNS, directories) |
| Changed a service's image, env vars, or volumes | `compose` |
| Changed firewall ports | `deploy` |
| Changed secrets or Ansible role templates | `deploy` |
| Only editing existing compose YAML files | `compose` |

## Enabling a New Service

1. Set `enabled: true` for the service in `ansible/group_vars/all.yml`.
2. If the service needs a Caddy hostname, add or review the `proxy_hosts` entry.
3. If the service needs direct LAN ports, add those ports to the firewall variables. The firewall will use `platform_effective_lan_cidr`, which defaults to the VM's current connected subnet when `platform_lan_cidr: auto`.
4. If the service needs secrets, create them under `/etc/self-hosted`.
5. Run `./scripts/deploy deploy`.

Most service directories are created automatically by Ansible from
[all.yml](/Users/chaseconover/Documents/Code/self-hosted/ansible/inventory/production/group_vars/all.yml)
using `platform_managed_directories`, so enabling a service should not require manual
folder creation.

## Synapse Chat

1. Copy [synapse.env.example](/Users/chaseconover/Documents/Code/self-hosted/platform/env/synapse.env.example)
   to `/etc/self-hosted/synapse.env` on the VM and replace the placeholder values, or let
   Ansible generate that file automatically on first deploy.
2. Set `synapse.enabled: true` in
   [all.yml](/Users/chaseconover/Documents/Code/self-hosted/ansible/inventory/production/group_vars/all.yml).
3. Add `chat.lab.chaseconover.com` to client DNS or `/etc/hosts`.
4. Run `./scripts/deploy deploy`.
5. Open `https://chat.lab.chaseconover.com` from a Matrix client such as Element using the homeserver URL.

If Ansible generates the secret file, it writes a random password once and does not
overwrite the file on later deploys.

Synapse is also bound to `127.0.0.1:8008` on the VM so Tailscale Serve can expose it
privately to your tailnet without making it public.

If Tailscale is installed on the VM, use:

```bash
sudo /usr/local/bin/self-hosted-share-chat-tailnet enable
```

Create the first Matrix user with:

```bash
sudo /usr/local/bin/self-hosted-register-synapse-user <username> --admin
```

## Media Ingest

New media lands in `/mnt/disk1/homelab/uploads/incoming/{movies,shows,music}` —
Transmission writes directly into those directories (the path is mounted as
`/downloads` inside the container). Once downloaded, an ingest script cleans up
torrent-style names and moves the files into the Jellyfin library at
`/mnt/disk1/media/{movies,shows,music}`.

### Flow

1. **Add the torrent** in Transmission at `https://torrents.lab.chaseconover.com`.
   When the "Open Torrent" dialog appears, set the **Destination folder** to
   `/downloads/movies`, `/downloads/shows`, or `/downloads/music` depending on the
   content — this is what tells the ingest script which category to process it as.
2. **Wait for download to finish**, then SSH to the Pi and run:
   ```bash
   ssh chaseconover@chase-raspberrypi.local 'sudo /usr/local/bin/self-hosted-ingest-media'
   ```
3. **Jellyfin** scans the library on its next interval and picks up the new titles.

> Transmission runs inside gluetun's network namespace so all its traffic is forced
> through the VPN — if the tunnel drops, gluetun's kill switch blocks traffic rather
> than leaking it. See [architecture-decisions.md Decision 4](architecture-decisions.md).

### What the ingest script does

The script lives on the Pi at `/usr/local/bin/self-hosted-ingest-media`. Source of
truth is the Ansible template at
[`ansible/roles/media/templates/self-hosted-ingest-media.sh.j2`](/Users/chaseconover/Documents/Code/self-hosted/ansible/roles/media/templates/self-hosted-ingest-media.sh.j2)
— edit there and redeploy with `./scripts/deploy deploy`; do not edit the deployed
copy on the Pi.

For each of `movies`, `shows`, and `music` under `incoming/`:

- **Movies** — strips site prefixes (`www.Torrenting.com - ...`) and release tags
  (`1080p.BluRay.x265-GalaxyRG`), normalizes to `Title (Year)`, removes `sample/`
  and `extras/` dirs, picks the largest video file as the main feature, and renames
  it to match the folder.
- **Shows** — strips the same release-tag junk, normalizes show folder names, and
  pads season folders (`Season 1` → `Season 01`) so Jellyfin matches them cleanly.
- **Music** — moved as-is without renaming.

After cleanup, files are `mv`'d into `/mnt/disk1/media/{category}/`. Because the
upload and media roots live on the same filesystem, `mv` is instant (directory
entry update only — no byte copy).

### Troubleshooting ingest

- **"No new … media to ingest"** — the `incoming/` subdirectory is empty. Check that
  the torrent finished and that its destination in Transmission was set to
  `/downloads/movies`, `/downloads/shows`, or `/downloads/music` (files saved to the
  default `/downloads/` root are not picked up).
- **Show/movie doesn't appear in Jellyfin** — trigger a library scan manually in the
  Jellyfin UI, or check that the cleaned folder name in `/mnt/disk1/media/...`
  matches Jellyfin's expected `Title (Year)` format. If the name was mangled, fix
  the cleanup regex in the `.sh.j2` template and redeploy.
- **Permission errors** — the ingest script must run with `sudo` because Jellyfin's
  library directories are root-owned.

## Safe Expansion Order

1. `vaultwarden`
2. `syncthing`
3. `navidrome`
4. `jellyfin`

Add them one at a time and observe memory and disk behavior after each deployment.

## Connecting to the Pi

The Raspberry Pi is accessible via SSH on the LAN:

```bash
ssh chaseconover@chase-raspberrypi.local
```

Key details:

| Setting | Value |
|---------|-------|
| Hostname | `chase-raspberrypi.local` (mDNS) |
| IP (static) | `192.168.1.167` |
| User | `chaseconover` |
| SSH key | `~/.ssh/id_rsa` |
| Ansible inventory | `ansible/inventory/production/hosts.yml` |

If mDNS is not resolving, connect by IP directly:

```bash
ssh chaseconover@192.168.1.167
```

### Ansible connectivity

Ansible uses the same SSH credentials defined in the inventory file. All playbooks run with `become: true` (sudo). To test connectivity:

```bash
cd ansible && ansible homelab -m ping
```

### Troubleshooting

- **Services unreachable after crash/reboot**: Run `./scripts/deploy recover`. This mounts external drives, restarts the compose stack, and verifies containers are healthy.
- **SSH connects but commands hang**: Check that `eth0` has carrier (`ip addr show eth0`). The Pi uses Ethernet as its primary interface — if the cable is disconnected, WiFi (`wlan0`) may receive traffic but fail to send replies. A reboot with the cable plugged in is the fastest fix.
- **Pi-hole DNS not picking up new entries**: This happens when dnsmasq config files change but Pi-hole hasn't reloaded. The Ansible Pi-hole handler restarts the container automatically during deploys. If needed manually, run `./scripts/deploy recover`.
- **Drive I/O errors in dmesg**: External USB drives can temporarily go offline, causing cascading failures. Check `dmesg | grep -i error` after a crash. If a drive is flaky, check the USB cable and enclosure power.

## External Drives

Two external USB drives are configured in `all.yml` under `platform_external_drives`:

| Label | Mount Point | Size | Purpose |
|-------|-------------|------|---------|
| MEDIA-01 | `/mnt/disk1` | 27.3 TB | Service data, media, archive, backups, uploads |
| MEDIA-02 | `/mnt/disk2` | 27.3 TB | Backup redundancy (future: additional storage) |

Drives are connected via an Icy Box IB-1232CL-U3 dual-bay USB 3.0 docking station and
mounted via fstab with `nofail,x-systemd.device-timeout=30s` so the Pi boots even if a
drive is missing. See [Troubleshooting > Icy Box Dock](troubleshooting.md#icy-box-dock-ib-1232cl-u3-and-drive-mount-issues)
for known issues with drive enumeration after reboot.

**Boot-critical files (compose, configs) are on the SD card** at `/srv/self-hosted/`, not
on the external drives. This means the platform starts and DNS/Caddy work even if the
HDD isn't mounted.

If the HDD mounts after containers have already started, run `./scripts/deploy recover`
to restart containers so they pick up the data directories.

**Note:** An automatic remount watcher (`homelab-compose-remount.path`) was attempted
but caused continuous restart loops and has been disabled. For now, late-mount recovery
is manual via `./scripts/deploy recover`.

## Networking

- All services are available at `https://<name>.lab.chaseconover.com`
- Pi-hole admin UI: `http://192.168.1.167:8080`
- Remote access via Tailscale — see [Tailscale](tailscale.md)
- HTTPS certificates via Let's Encrypt DNS challenge — see [TLS](tls.md)
- Split horizon DNS: Pi-hole returns LAN IP locally, Tailscale IP remotely — see [DNS Routing](dns-routing.md)
