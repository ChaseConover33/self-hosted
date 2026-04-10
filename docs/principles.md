# Principles

The short list of rules this homelab is designed around. When in doubt, pick the
option that is most consistent with these. The longer "why" for each is in
[`architecture-decisions.md`](architecture-decisions.md).

## 1. Optimize for WiFi-only

The Pi runs on `wlan0` and there is no Ethernet cable. Anything that assumes a stable
wired link will eventually bite. Docker interfaces are marked `unmanaged` in
NetworkManager, WiFi power save is off, and NetworkManager is restarted on a timer.
Do not remove those mitigations. Do not add services that require rock-solid
low-latency networking between containers and the host network namespace.

## 2. Boot-critical on SD card, data on HDD

Compose files, service configs, and secrets live on the SD card
(`/srv/self-hosted/`, `/etc/self-hosted/`). Databases, media, archives, and anything
that grows live on `/mnt/disk1/`. The homelab must be able to boot and serve Caddy,
Pi-hole, Homepage, and Uptime Kuma with both external drives missing. If a new
service breaks this invariant, either move its state, or accept that it's in the
"needs HDD" tier and will be unhealthy on cold boots without drives.

## 3. VPN kill switch is non-negotiable for torrent traffic

Transmission runs with `network_mode: service:gluetun`. gluetun has a firewall-based
kill switch that blocks all non-VPN traffic. A VPN health check timer restarts
gluetun + transmission if gluetun goes unhealthy. Never run a torrent client
outside this namespace, not even "just to test". There is no configuration of the
torrent client that is safe without the wrapper.

## 4. Pi-hole stays outside Caddy

Pi-hole uses Docker host networking and is reached directly by IP. This is required
by split horizon DNS (host networking is needed to see the source interface) and by
the TLS chicken-and-egg (Caddy needs DNS to get certs, so DNS cannot depend on
Caddy). Do not put Pi-hole behind the reverse proxy.

## 5. Use the project's scripts, never ad-hoc docker/ansible

Deploys go through `./scripts/deploy`. Media ingest goes through the ingest script.
Backups are checked with `./scripts/backup-check`. Archive updates go through
`./scripts/update-archive.sh`. Reaching past these to run `docker compose` or
`ansible-playbook` directly bypasses environment assumptions (secrets, inventory,
host targeting) and produces drift between what Ansible thinks is deployed and what
is actually running. Fix or extend the scripts instead.

## 6. No public ingress

The Verizon router does not forward ports, and that is a feature not a limitation.
Remote access is exclusively via Tailscale. Route 53 holds a CNAME pointing at a
Tailscale hostname that is only reachable inside the tailnet. Nothing in the
homelab should require opening a public port. New services go behind Caddy on the
internal Docker network, and Caddy only listens on the LAN + Tailscale interfaces.

## 7. Document the *why*, not just the *how*

Runbooks answer "how do I do X"; this project already has those in
[`operations.md`](operations.md), [`troubleshooting.md`](troubleshooting.md), and
[`boot-process.md`](boot-process.md). But the *why* behind design decisions tends
to live only in the operator's head, which is the bus-factor problem this
documentation effort exists to solve. When you make a non-obvious choice, add it
to [`architecture-decisions.md`](architecture-decisions.md) with the alternatives
you rejected and the constraints that forced your hand. "Because it works" is not
enough; describe *why* the rejected alternatives didn't work.

## 8. Fail gracefully, recover manually

The boot process is designed so that partial failures (HDD doesn't mount, VPN is
down, a container is unhealthy) leave the rest of the system running and leave
nothing corrupted. Recovery is a manual step (`./scripts/deploy recover`,
`sudo mount -a`, etc.) because reliable automatic recovery is harder than it looks
— the disabled `homelab-compose-remount.path` is a cautionary tale about trying
to auto-recover with `PathExists` and ending up in restart loops. Prefer manual
recovery steps that are documented over clever automation that might run away.

## 9. Pin images deliberately

After the Pi-hole v6 incident (see
[`docker-image-versioning.md`](docker-image-versioning.md)), images are pinned
where unexpected upgrades would cause downtime. `:latest` is fine for stateless
services where a rollback is cheap; long-lived stateful services should pin to a
known-good tag. When a pin is moved, treat it as a deploy, not a routine update.

## 10. Three backup copies, seven days retention

Backups go to three physically independent devices (SD card, disk1, disk2) every
day at 03:15 AM. Seven days of retention at each location. This survives any single
device failure. Off-site backup is a known gap; if it is added, treat it as a
fourth location, not a replacement.
