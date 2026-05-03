# Services

Most services are accessible at `https://<name>.lab.chaseconover.com` via Caddy reverse proxy with Let's Encrypt TLS certificates (provisioned via Cloudflare DNS challenge). See [tls.md](tls.md) for details.

A small subset are also exposed publicly via Cloudflare Tunnel at non-`*.lab.*` hostnames. Convention: `*.lab.chaseconover.com` = tailnet-only, other domains = public. See [cloudflare-tunnel.md](cloudflare-tunnel.md).

## Baseline (Infrastructure)

### caddy

- purpose: HTTPS reverse proxy with automatic Let's Encrypt certificates
- exposure: published on LAN ports `80` (redirects to HTTPS) and `443`
- custom image: built with `caddy-dns/cloudflare` module for DNS challenge
- RAM profile: low
- backup: config only

### pihole

- hostname: `pihole.lab.chaseconover.com`
- purpose: DNS ad blocker, local DNS resolver, split horizon DNS for Tailscale
- exposure: host networking (ports 53, 8080)
- RAM profile: low
- backup: yes
- notes: runs with `network_mode: host` for split horizon DNS. Uses `localise-queries` to return LAN IP or Tailscale IP based on query source.

### uptime_kuma

- hostname: `status.lab.chaseconover.com`
- purpose: availability dashboard
- RAM profile: low
- backup: yes

### homepage

- hostname: `home.lab.chaseconover.com`
- purpose: homelab service dashboard
- RAM profile: low
- backup: yes

### demo_public

- hostname: `demo.lab.chaseconover.com`
- purpose: prove hostname routing works
- RAM profile: very low
- backup: no

### demo_internal

- purpose: prove internal-only networking works
- exposure: internal only
- RAM profile: very low
- backup: no

## Tier 1 (Enabled)

### synapse

- hostname: `chat.lab.chaseconover.com`
- purpose: private Matrix homeserver for Element and other Matrix clients
- RAM profile: medium
- database: Postgres 16
- secret file: `/etc/self-hosted/synapse.env`
- backup: yes

### vikunja

- hostname: `tasks.lab.chaseconover.com`
- purpose: task manager for todos, ideas, and projects
- RAM profile: low
- database: Postgres 16
- secret file: `/etc/self-hosted/vikunja.env`
- backup: yes

### firefly

- hostname: `finance.lab.chaseconover.com`
- purpose: personal finance tracker and budgeting
- RAM profile: medium
- database: Postgres 16
- secret file: `/etc/self-hosted/firefly.env`
- backup: yes

### gitea

- hostname: `git.lab.chaseconover.com`
- purpose: self-hosted Git server for collaborative development
- RAM profile: low
- database: Postgres 16
- secret file: `/etc/self-hosted/gitea.env`
- SSH: port 2222 (Gitea built-in SSH server)
- backup: yes
- notes: open registration enabled so friends can create accounts

### kiwix

- hostname: `archive.lab.chaseconover.com`
- purpose: offline knowledge archive (Wikipedia, Stack Overflow, books)
- RAM profile: low
- data path: `/mnt/disk1/archive/kiwix` (ZIM files)
- backup: no (ZIM files are re-downloadable)

### gluetun

- purpose: VPN container that provides the network namespace for the torrent client (kill-switch-enforced — no torrent traffic flows if the VPN drops)
- RAM profile: low
- ports: 6881 TCP/UDP (torrent peer), 51413 TCP/UDP (Transmission peer), 9091 (Transmission web UI, proxied by Caddy)
- backup: config only
- notes: monitored by the `self-hosted-vpn-healthcheck.timer` systemd unit, which restarts gluetun + Transmission every 5 minutes if the VPN is unhealthy. See [architecture-decisions.md Decision 4](architecture-decisions.md).

### transmission

- hostname: `torrents.lab.chaseconover.com` (proxied by Caddy to `gluetun:9091`)
- purpose: active torrent client — runs inside gluetun's network namespace via `network_mode: service:gluetun`
- RAM profile: low
- download path: `/mnt/disk1/homelab/uploads/incoming` (mapped to `/downloads` inside the container)
- backup: yes (config only)
- notes: when adding a torrent via the web UI, set the destination to `/downloads/movies`, `/downloads/shows`, or `/downloads/music` so the ingest script can pick it up. See [Media Ingest](operations.md#media-ingest).

### qbittorrent (disabled)

- purpose: alternative torrent client — compose file is retained but `enabled: false` in `all.yml`
- notes: swapped out for Transmission due to peer discovery problems behind gluetun. See [architecture-decisions.md Decision 4](architecture-decisions.md).

### chronicle

- hostname: `journal.chaseconover.com` (**public** via Cloudflare Tunnel, not Caddy)
- purpose: personal journal app — AI-cleaned entries, lens reflections, goal tracking
- RAM profile: medium
- exposure: NOT routed through Caddy. `cloudflared` forwards `journal.chaseconover.com` directly to the chronicle container on the `internal` Docker network.
- auth: Clerk (Phase 1: allowlist of one — owner only). See [Phase 2 multi-user roadmap in the chronicle repo](https://github.com/ChaseConover33/chronicle/blob/main/docs/multi-user-roadmap.md).
- secret file: `/etc/self-hosted/chronicle.env` (Clerk + Anthropic keys; placeholder generated on first run, fill in manually)
- data path: `/mnt/disk1/homelab/data/chronicle/chronicle.db` (SQLite + WAL)
- backup: yes
- image: `ghcr.io/chaseconover33/chronicle:latest` (built by GitHub Actions on every main push)

### cloudflared

- purpose: Cloudflare Tunnel daemon — outbound-only connection to Cloudflare's edge for public-facing services
- exposure: no inbound ports, no UI. Public hostname routing is configured in the Cloudflare Zero Trust dashboard, NOT in this repo.
- RAM profile: low
- secret file: `/etc/self-hosted/cloudflared.env` (`TUNNEL_TOKEN` from the dashboard)
- backup: no (token is recreated by re-pasting from the dashboard)
- security note: dashboard ingress rules MUST point at app containers directly (e.g. `http://chronicle:3000`), never at `caddy:443` — see [cloudflare-tunnel.md](cloudflare-tunnel.md).

## Tier 2 (Enabled)

### jellyfin

- hostname: `media.lab.chaseconover.com`
- purpose: media streaming (direct-play focused)
- RAM profile: medium
- media path: `/mnt/disk1/media`
- backup: yes

## Disabled (Available to Enable)

### vaultwarden

- hostname: `vault.lab.chaseconover.com`
- purpose: password manager
- RAM profile: low

### syncthing

- hostname: `sync.lab.chaseconover.com`
- purpose: file synchronization
- RAM profile: medium

### navidrome

- hostname: `music.lab.chaseconover.com`
- purpose: music server
- RAM profile: medium

### trader

- purpose: algorithmic trading bot (Alpaca paper/live)
- RAM profile: low
- secret file: `/etc/self-hosted/trader.env`

## Service Contract

Each service definition in `platform/compose/services/` should document:

- image
- purpose
- exposure mode
- hostnames if proxied
- volumes
- expected resource profile
- backup expectations
