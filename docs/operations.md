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

## Media Uploads

Use the writable upload landing path:

- `/srv/self-hosted/uploads/incoming`

That directory is owned by your SSH user, so you can copy files there with `scp` or
`rsync` without writing directly into the root-owned Jellyfin library folders under
`/srv/self-hosted/media`.

Recommended flow:

1. Upload into `/srv/self-hosted/uploads/incoming/movies`,
   `/srv/self-hosted/uploads/incoming/shows`, or
   `/srv/self-hosted/uploads/incoming/music`.
2. Run `sudo /usr/local/bin/self-hosted-ingest-media` on the VM, or use
   [upload-media](/Users/chaseconover/Documents/Code/self-hosted/scripts/upload-media)
   from your Mac to upload and ingest in one step.
3. Let Jellyfin scan the organized library folders under `/srv/self-hosted/media`.

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
