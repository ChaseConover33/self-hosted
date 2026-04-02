# Services

All services are accessible at `https://<name>.lab.chaseconover.com` via Caddy reverse proxy with Let's Encrypt TLS certificates (provisioned via Route 53 DNS challenge). See [tls.md](tls.md) for details.

## Baseline (Infrastructure)

### caddy

- purpose: HTTPS reverse proxy with automatic Let's Encrypt certificates
- exposure: published on LAN ports `80` (redirects to HTTPS) and `443`
- custom image: built with `caddy-dns/route53` module for DNS challenge
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

### qbittorrent

- hostname: `torrents.lab.chaseconover.com`
- purpose: torrent client with web UI for downloading media and books
- RAM profile: low
- download path: `/mnt/disk1/homelab/uploads/incoming`
- ports: 6881 TCP/UDP (torrent peer connections)
- backup: yes (config only)
- notes: built-in username/password auth on web UI. Downloads go to the media ingest directory.

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
