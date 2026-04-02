# Architecture

## Layers

The platform is split into three active layers:

1. `Ansible`
   - bootstraps and configures the Debian host
   - manages firewall, directories, systemd timers, Caddy config, and Compose deployment
2. `Docker Compose`
   - defines the running container stack
   - keeps services portable across any Debian host with Docker
3. `Caddy`
   - serves HTTPS with Let's Encrypt certificates (via Route 53 DNS challenge)
   - routes browser traffic to enabled services by hostname
   - custom image with `caddy-dns/route53` module
4. `Tailscale`
   - provides secure remote access via encrypted mesh network
   - ACLs restrict friends to web-only access (ports 80, 443, 53, 2222)
5. `Pi-hole`
   - split horizon DNS: returns LAN IP for local queries, Tailscale IP for remote queries
   - runs with host networking to distinguish query source interfaces
   - `local=/lab.chaseconover.com/` prevents upstream forwarding, ensuring offline resilience

`Terraform` is intentionally deferred. The current host already exists, so machine configuration matters more than cloud resource provisioning.

## Domain

All services are accessible at `https://<name>.lab.chaseconover.com`. DNS is handled by:

- **Pi-hole** (local) — answers `*.lab.chaseconover.com` queries from local records, never forwards upstream
- **Route 53** (remote fallback) — `*.lab.chaseconover.com` CNAME points to the Pi's Tailscale hostname, only reachable on the tailnet

The homelab works with or without internet connectivity because Pi-hole answers locally.

## Networks

- `public`
  - attached only to the reverse proxy
  - exists so browser-facing entrypoints stay conceptually separate
- `internal`
  - used for service-to-service communication
  - used by Caddy to reach the proxied apps
- `host` (Pi-hole only)
  - Pi-hole uses host networking for split horizon DNS

No router port forwards or public DNS exposure. Remote access is via Tailscale only.

## Storage Layout

Boot-critical files (compose definitions, service configs, secrets) live on the SD card
so the platform starts even if external drives aren't mounted. Large data stays on the
external HDD.

```
SD card (/srv/self-hosted/)          ← always available at boot
├── compose/                         ← Docker Compose files and .env
├── config/                          ← Caddy, Pi-hole, Synapse, Homepage configs
└── backups/                         ← backup copy (survives HDD failure)

/etc/self-hosted/                    ← secrets (SD card)

External HDD (/mnt/disk1/)          ← may mount late after boot
├── homelab/data/                    ← service databases (Synapse, Vikunja, etc.)
├── homelab/backups/                 ← primary backup location
├── homelab/uploads/                 ← media ingest staging
├── media/                           ← Jellyfin library (movies, shows, music)
└── archive/kiwix/                   ← offline archive ZIM files

Secondary HDD (/mnt/disk2/)         ← backup redundancy
└── backups/                         ← backup copy (survives SD card failure)
```

If the HDD mounts late (after containers have already started), run
`./scripts/deploy recover` to restart containers so they pick up the data directories.

**Note:** An automatic remount watcher (`homelab-compose-remount.path`) was attempted
but caused continuous restart loops — `PathExists` fires repeatedly, not once. It has
been disabled. A mount-unit-triggered approach is needed for true auto-recovery.

## Resource Budget

This repository is tuned for a single Debian VM with:

- 4 vCPU
- 16 GB RAM
- 117 GB SD card + 28 TB external HDD + 28 TB secondary HDD

Practical steady-state target:

- keep the always-on baseline under roughly `2-3 GB RAM`
- preserve `2+ GB` of headroom for the OS, Docker overhead, filesystem cache, and spikes
- treat storage as a first-order constraint once backups or media are introduced

## Service Tiers

### Baseline

- Caddy
- Uptime Kuma
- optional Homepage
- sample public/internal validation services

### Tier 1

- Vaultwarden
- Syncthing
- Navidrome

### Tier 2

- Jellyfin

### Deferred

- full mail
- heavy photo management
- always-on local AI
- large observability stacks
