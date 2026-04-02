# Private Homelab Platform

Self-hosted platform on a Raspberry Pi 5 using Ansible, Docker Compose, and Tailscale.

All services are available at `https://<name>.lab.chaseconover.com` with automatic Let's Encrypt certificates. Remote access is via Tailscale with ACL-based friend access.

## Running Services

| Service | URL | Purpose |
|---------|-----|---------|
| Jellyfin | `media.lab.chaseconover.com` | Media streaming |
| Gitea | `git.lab.chaseconover.com` | Git collaboration server |
| Kiwix | `archive.lab.chaseconover.com` | Offline Wikipedia, Stack Overflow, books |
| Vikunja | `tasks.lab.chaseconover.com` | Task management |
| Firefly III | `finance.lab.chaseconover.com` | Personal finance |
| Synapse | `chat.lab.chaseconover.com` | Matrix chat server |
| qBittorrent | `torrents.lab.chaseconover.com` | Torrent client (auth-protected) |
| Homepage | `home.lab.chaseconover.com` | Service dashboard |
| Uptime Kuma | `status.lab.chaseconover.com` | Availability monitoring |
| Pi-hole | `http://192.168.1.167:8080` | DNS ad blocker (admin UI) |

## Common Commands

```bash
# Deploy all changes (Ansible roles + Docker Compose)
./scripts/deploy deploy

# Deploy only compose file changes (faster)
./scripts/deploy compose

# Recover after crash or reboot
./scripts/deploy recover

# Check container health
./scripts/deploy status

# Validate Ansible config
./scripts/deploy validate

# First-time host setup
./scripts/deploy bootstrap
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [Operations](docs/operations.md) | Deployment commands, service management, SSH access |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and fixes |
| [Services](docs/services.md) | All services with hostnames, ports, and config details |
| [Architecture](docs/architecture.md) | System layers, networks, resource budget |
| [DNS Routing](docs/dns-routing.md) | How DNS resolution works (split horizon, Pi-hole, Tailscale) |
| [TLS](docs/tls.md) | HTTPS setup with Let's Encrypt and Route 53 |
| [Tailscale](docs/tailscale.md) | Remote access, ACLs, friend onboarding |
| [Bootstrap](docs/bootstrap.md) | First-time host setup guide |
| [Backup & Restore](docs/backup-restore.md) | Backup strategy and recovery |
| [Archive](docs/archive.md) | Kiwix ZIM file management |

## Infrastructure

- **Host**: Raspberry Pi 5 (16 GB RAM, Debian)
- **Storage**: SD card (OS) + 2x 27.3 TB external USB drives (data/media)
- **Deployment**: Ansible playbooks + Docker Compose
- **Reverse Proxy**: Caddy with automatic HTTPS (Let's Encrypt via Route 53 DNS challenge)
- **DNS**: Pi-hole with split horizon (LAN IP locally, Tailscale IP remotely)
- **Remote Access**: Tailscale with tag-based ACLs
- **Domain**: `*.lab.chaseconover.com` (CNAME to Tailscale hostname in Route 53)
- **Backups**: Daily tar snapshots via systemd timer

## Host Layout

```
/mnt/disk1/homelab/
  config/       # Service configs (Caddy, Synapse, etc.)
  data/         # Service data (databases, caches)
  backups/      # Tar-based snapshots
  uploads/      # Media ingestion staging
  compose/      # Docker Compose deployment files

/mnt/disk1/media/   # Jellyfin library (movies, shows, music)
/etc/self-hosted/   # Secret files (.env for services)
```
