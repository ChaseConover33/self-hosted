# Architecture Decisions

This document captures the *why* behind major design decisions in this homelab.
It complements the operational docs by explaining *why* things are the way they are,
not just *how* to operate them.

If a decision is already explained in detail elsewhere, this doc links to that source
rather than duplicating the content. The goal is a single place to understand the
shape of the system without having to reverse-engineer it from Ansible roles and
compose files.

---

## Decision 1: Pi-hole runs outside Caddy

**What:** Pi-hole is the only application service that does not sit behind the Caddy
reverse proxy. It runs with Docker `network_mode: host` and is accessed directly at
`http://192.168.1.167:8080` for the admin UI, and on port 53 for DNS.

**Why:**
- **Split horizon DNS requires host networking.** Pi-hole uses dnsmasq's
  `localise-queries` directive to return a LAN IP (`192.168.1.167`) to queries arriving
  on `wlan0` and a Tailscale IP (`100.x.y.z`) to queries arriving on `tailscale0`. It
  can only distinguish the source interface if it sees the real host interfaces — a
  bridged Docker network would hide them behind a single `docker0` veth. See
  [`docs/dns-routing.md`](dns-routing.md) for the full strategy comparison and
  [`docs/tailscale.md`](tailscale.md) for how this ties into remote access.
- **Chicken-and-egg with TLS.** Caddy obtains Let's Encrypt certificates via the
  Route 53 DNS-01 challenge, which requires working DNS. If Pi-hole were behind Caddy,
  then Caddy would need a valid cert to serve Pi-hole, but Pi-hole would need to be up
  for Caddy (and everything else) to resolve `lab.chaseconover.com` locally. Keeping
  Pi-hole out of the proxy breaks the loop: DNS comes up first, then Caddy requests
  certs, then everything else comes up.
- **Offline resilience.** Pi-hole using `local=/lab.chaseconover.com/` is what lets
  the homelab keep answering for its own hostnames when the internet is down. A
  Caddy-fronted Pi-hole would add another failure dependency to that path.

**Alternatives considered:**
- **Pi-hole behind Caddy on a subdomain** — rejected because of the chicken-and-egg
  TLS problem and because host-networking is required for split horizon DNS.
- **Separate DNS resolver (unbound, CoreDNS) behind Caddy, Pi-hole only for blocklists**
  — rejected as unnecessary complexity for a single-admin homelab.

**Consequences:**
- The Pi-hole admin UI is the one service that is *not* at
  `https://<name>.lab.chaseconover.com`. It is reached by IP and port.
- Pi-hole cannot be moved to a different host without updating every device's DNS
  settings, because it is also the DHCP-independent DNS server for personal devices.
- Pi-hole is a hard dependency for everything else. If it goes down, hostname
  resolution stops, so Caddy cert renewal and remote Tailscale access break. It must
  be kept simple and stable.

---

## Decision 2: Boot-critical files on SD card, data on external HDD

**What:** Compose files, service configs, and secrets live on the SD card under
`/srv/self-hosted/` and `/etc/self-hosted/`. Service data (databases, media, archive)
lives on external HDDs under `/mnt/disk1/`. The fstab entries for the HDDs use
`nofail,x-systemd.device-timeout=30s` so the boot does not block on them.

**Why:**
- **The homelab must boot and provide basic services even if the HDDs fail to mount.**
  Caddy, Pi-hole, Homepage, and Uptime Kuma all run entirely from SD-card-resident
  state. When the external drives are missing, these still come up normally — so DNS,
  HTTPS, the dashboard, and availability monitoring keep working, and the operator
  can SSH in to diagnose.
- **External HDDs are the most likely failure.** The drives are connected through an
  Icy Box IB-1232CL-U3 dual-bay dock over USB. The dock has a documented issue where
  one or both drives fail to enumerate on reboot (see
  [`docs/troubleshooting.md`](troubleshooting.md) and
  [`docs/boot-process.md`](boot-process.md)). If boot-critical state lived on the
  HDDs, every reboot would be a coin flip on whether the entire homelab comes back.
- **Data-heavy services fail gracefully.** Vikunja, Firefly, Gitea, Synapse, Jellyfin,
  and Kiwix bind-mount empty directories when the HDD is missing. They come up
  unhealthy but do not corrupt anything (see
  [`docs/boot-process.md`](boot-process.md) "Do I Need to Clean Up Anything?" for
  the full reasoning on why empty bind-mounts are safe). A manual
  `./scripts/deploy recover` after the drive mounts brings them back.

**Alternatives considered:**
- **Everything on HDD** — rejected because the Icy Box dock's USB enumeration issues
  would make every reboot fragile, and because SD-card writes are low enough that
  wear is not the binding constraint.
- **Everything on SD card** — rejected because 30 TB of media and backups will not
  fit and SD cards are a poor choice for large, write-heavy workloads.
- **Symlinks from SD card to HDD for "boot-critical" paths** — rejected because
  symlinks resolving to a missing filesystem would produce confusing errors instead
  of the clean "empty directory" behavior that bind-mounts give.

**Consequences:**
- Backups have to cover both `/srv/self-hosted/` (configs) and `/mnt/disk1/homelab/data`
  (state) — see [`docs/backup-restore.md`](backup-restore.md).
- There is no automatic recovery when the HDD mounts late. A
  `PathExists`-based watcher was tried and caused restart loops; a mount-unit-based
  approach is the noted future fix. Late mounts require manual
  `./scripts/deploy recover`.
- Secrets live in `/etc/self-hosted/` (SD card) and are explicitly *not* in the
  backup tar. They have to be backed up out of band.

---

## Decision 3: WiFi-only with NetworkManager Docker isolation

**What:** The Pi has no Ethernet cable. All traffic runs over `wlan0`. The `base`
Ansible role drops two config files into `/etc/NetworkManager/conf.d/`:
`docker-unmanaged.conf` (tells NM to ignore `veth*`, `br-*`, and `docker*` interfaces)
and `wifi-powersave-off.conf` (disables the Broadcom driver's power save). It also
installs a `networkmanager-restart.timer` that fires twice a day (04:00 and 16:00)
to restart NetworkManager.

**Why:**
- **Docker creates 15+ veth interfaces** as containers start and stop. By default,
  NetworkManager tracks every interface that appears and processes carrier-state
  events for each one. With this many containers, NM gets a steady stream of carrier
  events that eventually degrades the WiFi stack over hours until non-interactive SSH
  stops working while the Pi itself is still up. Marking the Docker interfaces as
  "unmanaged" short-circuits that event storm. See
  [`docs/boot-process.md`](boot-process.md) "Known Issue: WiFi + Docker" and
  [`docs/troubleshooting.md`](troubleshooting.md) "WiFi Degradation".
- **WiFi power save causes intermittent overnight outages.** The `brcmfmac` driver
  will put the radio to sleep during quiet periods, and it does not always wake
  cleanly. Services become unreachable overnight for no obvious reason. Disabling
  power save removes that class of issue.
- **NetworkManager still degrades slowly even with both fixes applied.** Restarting
  NM on a fixed cadence clears whatever state has accumulated before it becomes
  user-visible. The timer fires at 04:00 and 16:00 — 04:00 is deliberately after
  the 03:15 backup and before the user is awake, and 16:00 gives a second reset
  during the day to catch any faster-than-expected degradation.

**Alternatives considered:**
- **Run an Ethernet cable to the Pi** — would eliminate most of this, but physically
  impossible given the current network layout.
- **Switch off NetworkManager entirely and use `systemd-networkd` or `wpa_supplicant`
  directly** — rejected as a bigger change than needed; the config-file fixes work
  and are easy to understand.
- **Restart NM once a day instead of twice** — tried, still had occasional degradation
  before the next restart. Twice a day is the current working cadence.

**Consequences:**
- Any automation that relies on listing network interfaces through NM will not see
  Docker's veths — this is by design.
- The WiFi stack gets kicked twice a day. Any in-flight long TCP connections at 04:00
  or 16:00 will drop. In practice nothing cares.
- This whole class of issue returns if either of the NM config files is removed or
  the restart timer is disabled. The `base` role is the source of truth.

---

## Decision 4: Transmission via gluetun, not qBittorrent

**What:** The active torrent client is Transmission, running with
`network_mode: service:gluetun` so that all traffic is forced through the gluetun
VPN container. qBittorrent's compose file still exists
(`platform/compose/services/qbittorrent.yml`) but its service entry in
`ansible/inventory/production/group_vars/all.yml` has `enabled: false`. Caddy proxies
`torrents.lab.chaseconover.com` to `gluetun:9091` (Transmission's web UI, exposed via
gluetun's network namespace).

**Why:**
- **qBittorrent has peer discovery problems when sharing gluetun's network namespace.**
  The combination of qBittorrent's connection handling and gluetun's firewall rules
  led to very poor peer connectivity — torrents would crawl or stall. Transmission
  works reliably in the same setup.
- **The VPN kill switch is non-negotiable.** gluetun's firewall is configured to drop
  all traffic that does not traverse the VPN tunnel. By putting the torrent client
  inside gluetun's network namespace (`network_mode: service:gluetun`), there is no
  network path for the client to use *other* than the tunnel. If the VPN drops,
  traffic is blocked, not leaked. This is enforced by gluetun's `FIREWALL_*` env
  vars and the kill-switch-by-default behavior.
- **A separate health check catches stuck VPN state.** The base role installs
  `self-hosted-vpn-healthcheck.timer` which runs every 5 minutes, checks gluetun's
  container health, and restarts gluetun + transmission if the VPN is not healthy.

**Alternatives considered:**
- **qBittorrent behind gluetun** — tried, rejected due to peer discovery issues.
- **Torrent client with its own built-in WireGuard** — rejected because gluetun is
  already battle-tested as a kill-switch wrapper and supports multiple providers.
- **Torrent client with no VPN** — rejected, never an option for this traffic class.

**Consequences:**
- The torrent web UI is reached at `gluetun:9091` from Caddy's perspective, not at
  `transmission:9091`. This surprises people reading the compose files — the upstream
  in the Ansible service map is `gluetun:9091`.
- Transmission's peer port (`51413`) has to be published on gluetun's service, not
  on transmission's, because gluetun owns the network namespace.
- If gluetun's container is recreated, transmission *must* be recreated too, or it
  loses its network. `./scripts/deploy recover` handles this.

---

## Decision 5: Custom Caddy image with the Route 53 DNS module

**What:** Caddy is not run from the stock Docker Hub image. A tiny Dockerfile in
`platform/compose/caddy/Dockerfile` uses `xcaddy` to build Caddy with
`github.com/caddy-dns/route53` compiled in, then copies the resulting binary into
`caddy:2-alpine`. The image is built on the Pi during deploy.

**Why:**
- **Stock Caddy does not include any DNS provider modules.** DNS-01 ACME challenges
  require a provider plugin that can create and delete TXT records in the hosted
  zone. For AWS Route 53 that plugin is `caddy-dns/route53`, which has to be
  compiled into the binary at build time.
- **DNS-01 challenges are the right choice here.** HTTP-01 challenges would require
  exposing port 80 to the public internet. The Verizon CR1000A router cannot
  reliably port-forward and the operator does not want any public ingress anyway.
  Route 53 DNS-01 only needs AWS API credentials, no inbound ports. See
  [`docs/tls.md`](tls.md) for the full setup.

**Alternatives considered:**
- **HTTP-01 challenges with a port forward** — rejected, no public ingress is a
  hard constraint of the network setup and the project principles.
- **A standalone ACME client writing certs to a shared volume** — rejected as more
  moving parts than needed; Caddy's built-in ACME handling is reliable.
- **Tailscale Serve for TLS** — works for individual services (and is used by the
  `self-hosted-share-chat-tailnet` helper per [`docs/tailscale.md`](tailscale.md)),
  but does not give wildcard certs covering every `*.lab.chaseconover.com`
  hostname the homelab wants to present.

**Consequences:**
- The first deploy on a new host has to build the Caddy image, which takes a few
  minutes on a Pi 5. Subsequent deploys reuse the cached image.
- Upgrading Caddy means rebuilding the image, not just pulling a new tag. The
  Dockerfile pins the `caddy:2-builder` and `caddy:2-alpine` base tags — check
  [`docs/docker-image-versioning.md`](docker-image-versioning.md) for the general
  philosophy on image pinning after the Pi-hole v6 incident.
- AWS credentials (`/etc/self-hosted/caddy.env`) are a hard dependency. Losing them
  means no cert renewals.

---

## Decision 6: Tailscale for remote access, not port forwarding

**What:** Remote access to the homelab goes through a Tailscale tailnet. The Pi runs
`tailscaled` with `--advertise-tags=tag:homelab`. A wildcard CNAME in Route 53 points
`*.lab.chaseconover.com` at the Pi's Tailscale hostname. Access for friends is
controlled by Tailscale ACLs.

**Why:**
- **The Verizon CR1000A router does not support reliable port forwarding.** It has
  hardcoded ISP defaults that can't be fully overridden (see
  [`docs/dns-routing.md`](dns-routing.md)'s router-level Pi-hole discussion for a
  related case of the same limitation). Even if it did, exposing inbound ports on a
  shared home network to the internet is not a tradeoff the operator wants to make.
- **Tailscale provides an encrypted overlay network with no router config.** Devices
  on the tailnet can reach each other over the same hostnames they use at home,
  as long as Pi-hole's split horizon DNS returns the right IP. No public DNS
  advertises any IP that is reachable outside the tailnet — the CNAME only resolves
  to a tailnet-internal hostname.
- **ACLs give per-friend, per-port access control.** Friends can be granted browser
  access to Jellyfin, Gitea, the archive, etc. on ports 80/443, plus Pi-hole DNS on
  53 and Gitea SSH on 2222, without ever getting shell access or visibility into
  non-web services. See [`docs/tailscale.md`](tailscale.md) for the ACL policy.

**Alternatives considered:**
- **Port forwarding + dynamic DNS** — rejected, router limitations plus public
  exposure.
- **Cloudflare Tunnel** — viable, but adds a third-party dependency on the hot path
  for every request and requires trusting Cloudflare with TLS termination.
- **WireGuard directly** — what Tailscale is built on, but without the coordination
  server, ACLs, and MagicDNS. More plumbing for the same result.

**Consequences:**
- Friends have to install Tailscale and be invited. There is no "just visit the URL"
  path.
- Pi-hole's split horizon DNS is a hard requirement for Tailscale to work cleanly
  — see Decision 1.
- A Tailscale outage means no remote access. Local LAN access still works because
  Pi-hole continues to answer queries with the LAN IP.

---

## Decision 7: Pi-hole DNS at the device level, not router level

**What:** Pi-hole is manually configured as the primary DNS server on the
operator's personal devices (Mac, iPhone), with the router as the secondary fallback.
The router itself still advertises its default Verizon DNS to everyone else on the
network via DHCP. Roommates' devices, smart TVs, and other shared hardware are not
touched.

**Why:**
- **Shared household, not shared infrastructure.** Forcing Pi-hole as the network-wide
  DNS would apply blocklists and local `lab.chaseconover.com` records to roommates
  who did not opt in. This is a hobbyist homelab, not a household-wide service.
- **The Verizon CR1000A router is hostile to custom DNS config.** Its DHCP DNS
  settings cannot cleanly override the ISP-provided servers. Custom entries are
  added alongside Verizon's, with unpredictable client behavior. See
  [`docs/dns-routing.md`](dns-routing.md) Strategy 3 for a detailed description.
- **Per-device config gives equivalent functionality for the operator.** The only
  devices that need to resolve `lab.chaseconover.com` at home are the ones the
  operator uses, and those are a small fixed set.

**Alternatives considered:**
- **Router-level Pi-hole via DHCP** — rejected for the two reasons above.
- **Dedicated router running OpenWrt** — possible future change, deferred until the
  current Verizon box is replaceable.
- **Only `/etc/hosts` on the Mac** — the original setup; rejected because iPhone and
  anywhere else with no `/etc/hosts` couldn't resolve homelab hostnames, and because
  adding a new service would require touching every device.

**Consequences:**
- Adding a new personal device requires one-time DNS configuration on it.
- Pi-hole analytics show traffic only from the operator's devices, not the whole
  household. That is fine and actually preferred.
- If Pi-hole is down, the operator's devices fall back to the router's DNS and lose
  `lab.chaseconover.com` resolution — but still have working internet. This is the
  right failure mode.

---

## Decision 8: Daily NetworkManager restart at 04:00 (and 16:00)

**What:** `networkmanager-restart.timer` is installed by the `base` role. It runs
`systemctl restart NetworkManager` on an `OnCalendar` schedule of `*-*-* 04:00:00`
and `*-*-* 16:00:00` (twice daily). `Persistent=true` means it catches up on missed
runs after a reboot.

**Why:**
- **Even with Docker interface isolation and power-save disabled, WiFi still
  degrades.** See Decision 3 for the root causes. Empirically, the Pi's WiFi stack
  accumulates enough subtle state that services become flaky roughly every few
  days if nothing is done.
- **Restarting NetworkManager fully clears that state.** It re-associates with the
  AP, rebuilds interface tracking, and resets the connection state machine. The
  containers and Docker networks are unaffected because Docker's interfaces are
  marked `unmanaged` — NM restart doesn't touch them.
- **04:00 was chosen deliberately** to run *after* the 03:15 daily backup (so the
  backup never races the network restart) and *before* the operator is awake (so
  any brief connectivity blip is invisible). 16:00 was added as a second daily reset
  after restarting once a day wasn't always enough.

**Alternatives considered:**
- **Restart only on detected degradation** — rejected as too complex and unreliable;
  detecting "WiFi feels slow" from inside the Pi is hard.
- **Reboot the Pi nightly instead** — rejected because a full reboot gambles on the
  Icy Box dock re-enumerating both drives cleanly.
- **One restart per day** — tried, still had occasional degradation before 24h;
  two per day is the current known-good cadence.

**Consequences:**
- Any long-lived TCP connection open across 04:00 or 16:00 will drop. Nothing in the
  stack currently cares; Caddy, Pi-hole, and the apps reconnect as needed.
- Removing or disabling the timer will bring back the slow WiFi degradation within
  a few days.

---

## Decision 9: `mv` instead of `rsync` in the media ingest script

**What:** `scripts/organize-media.sh` and the Ansible-managed
`self-hosted-ingest-media.sh` reorganize files within `/mnt/disk1/media/` using
plain `mv`. There is no `rsync` in the hot path for on-disk reshuffling.

**Why:**
- **`mv` within the same filesystem is instantaneous.** It updates directory entries;
  no file data is read or written. Renaming a 50 GB season folder completes in
  milliseconds.
- **`rsync` would copy byte-for-byte even on the same partition.** rsync has no
  special case for same-filesystem moves — it reads every source file and writes a
  new copy at the destination, then deletes the source. For the initial media
  reorganization that was hundreds of GB of shows and movies, that was the
  difference between "hours" and "instant". USB-attached HDDs at ~100 MB/s sustained
  write make this extremely painful at scale.
- **The organize script is idempotent via `|| true`**. Files already in the correct
  place are skipped quietly; the script can be re-run safely.

**Alternatives considered:**
- **rsync with `--remove-source-files`** — rejected because it still reads and
  writes every byte.
- **Hard links** — would also be instant, but leaves the old paths in place
  cluttering directory listings. Not the desired semantics.
- **Python `os.rename`** — equivalent to `mv` under the hood; `mv` keeps the shell
  script simple.

**Consequences:**
- The script assumes source and destination are on the same filesystem. Moving
  across mountpoints (e.g., from `/mnt/disk1` to `/mnt/disk2`) would silently fall
  back to a byte-for-byte copy inside `mv` itself — and be slow again. Any future
  script that touches both drives needs to be aware of this.
- Because `mv` is instant, there is no progress bar. This is fine; nothing to wait
  for.

---

## Decision 10: Backups in three locations (SD card, disk1, disk2)

**What:** `self-hosted-backup.timer` runs daily at 03:15 AM and writes a tar.gz
snapshot to three locations: `/mnt/disk1/homelab/backups/` (primary),
`/srv/self-hosted/backups/` (SD card), and `/mnt/disk2/backups/` (secondary HDD).
Each location keeps 7 days of retention. See
[`docs/backup-restore.md`](backup-restore.md) for the full list of what is included
and the restore drill.

**Why:**
- **Survive any single-device failure.** The three locations are on three physically
  independent devices: the SD card in the Pi, external HDD 1, and external HDD 2.
  - If the SD card dies (not uncommon over years of writes) → disk1 and disk2 still
    have the backup *and* the data.
  - If disk1 fails → SD card has configs, disk2 has the backup of disk1's data.
  - If disk2 fails → disk1 still has primary data and backups; SD card has a
    secondary copy.
- **Primary on disk1 is the fast-restore path.** Restoring from the primary location
  is just `tar -xzf` on the same drive the data lives on — no cross-device copying.
- **SD card copy is the "can still function with no HDDs" insurance.** Combined
  with Decision 2 (boot-critical on SD card), a full HDD-pair loss still leaves a
  bootable homelab with recoverable service state sitting next to it.

**Alternatives considered:**
- **Off-site backup (S3, Backblaze B2, etc.)** — not yet implemented; the 7-day
  local retention covers the most common failure modes. Off-site is a reasonable
  future addition for ransomware / catastrophic loss scenarios.
- **ZFS or btrfs snapshots on disk1** — rejected because the Pi's filesystem is
  ext4 on USB-attached drives and adding a CoW filesystem layer is more complexity
  than the benefit justifies at this scale.
- **Single-location backups with higher retention** — rejected because "one disk
  dies" is by far the most likely failure, and retention does not help if the only
  copy is gone.

**Consequences:**
- Backups use roughly 3x the disk they otherwise would (5-6 GB per location after
  7 days of retention = ~15-18 GB total). Acceptable given 30 TB drives.
- If disk2 is unmounted at 03:15, the backup to disk2 silently fails for that run
  and the next day picks it up. The daily cadence tolerates occasional misses.
- Secrets under `/etc/self-hosted/` are *not* in the tar. They have to be recreated
  or backed up by hand during a bare-metal restore.
