# Cloudflare Tunnel

Cloudflare Tunnel exposes selected homelab services publicly without opening any router ports or revealing the home IP. The Pi makes an outbound connection to Cloudflare's edge; Cloudflare proxies inbound traffic from the public internet over that tunnel.

This sits alongside Tailscale, not in place of it:

- **Tailscale** — every `*.lab.chaseconover.com` host. Authenticated tailnet access only. Highest security, friends must be on the tailnet.
- **Cloudflare Tunnel** — selected non-`*.lab.*` hostnames (e.g. `journal.chaseconover.com`). Public, anyone on the internet can reach them. Auth happens at the application layer (e.g. Clerk for Chronicle).

The two layers are independent. A service can be on either, both, or neither.

## What's exposed publicly

| Service | Public hostname | App-level auth |
|---|---|---|
| Chronicle | `journal.chaseconover.com` | Clerk (Phase 1: allowlist of one — owner only) |

Nothing else is publicly exposed. Jellyfin, Gitea, Vikunja, Synapse, Firefly, Pi-hole admin, Uptime Kuma, etc. remain tailnet-only.

## How traffic flows

1. Browser hits `https://journal.chaseconover.com`.
2. Cloudflare DNS resolves it to a Cloudflare edge IP.
3. Cloudflare's edge terminates TLS.
4. Edge forwards the request through the open tunnel to the `cloudflared` container running on the Pi.
5. `cloudflared` looks up the inbound hostname in its ingress map (configured in the Cloudflare Zero Trust dashboard) and forwards to `http://chronicle:3000` over the `internal` Docker network.
6. Chronicle's Clerk proxy intercepts unauthed requests and redirects them to the in-app sign-in page.

The Pi has **no public ports**. The `cloudflared` container only makes outbound connections. Even if your home IP leaked, an attacker hitting it directly would get nothing.

## Ingress rules — security-critical

Public hostname routing is configured in the Cloudflare Zero Trust dashboard:

> **Networks → Tunnels → (your tunnel) → Public Hostname**

Each rule is `<hostname> + <service URL>`. The service URL is resolved from inside the `cloudflared` container's view of the Docker network, so use the container name and internal port — e.g. `http://chronicle:3000`.

**Critical rule: do NOT route a public hostname to `caddy:443`.** The internal Caddy serves every `*.lab.chaseconover.com` host. If `cloudflared` ever forwarded to Caddy, the entire homelab — Jellyfin, Gitea, Pi-hole admin, etc. — would become publicly reachable, most without any auth. Always route directly to the application container, not through Caddy.

The current ingress map should contain exactly:

| Hostname | Service URL | Notes |
|---|---|---|
| `journal.chaseconover.com` | `http://chronicle:3000` | Direct to Chronicle container, bypasses Caddy |
| (catch-all) | `http_status:404` | Default — implicit |

## Setting up the tunnel (one-time)

1. Sign up / log in to Cloudflare. Add the `chaseconover.com` domain (or relevant zone) to Cloudflare DNS, OR keep it in Route 53 and use a CNAME for the tunnel record.
2. Go to https://one.dash.cloudflare.com/ → **Networks → Tunnels** → **Create a tunnel** → **Cloudflared**. Name it (e.g. `homelab`).
3. The next screen shows an install command containing the tunnel token. Copy the token.
4. On the Pi, write the token to the secret file (the Ansible role creates a placeholder file on first run):
   ```
   sudo vim /etc/self-hosted/cloudflared.env
   # Paste TUNNEL_TOKEN=<token>
   ```
5. Re-run `./scripts/deploy deploy`. The `cloudflared` container will start and connect to Cloudflare.
6. Back in the Cloudflare dashboard, on the tunnel's **Public Hostname** tab, add: `journal.chaseconover.com` → `http://chronicle:3000`.
7. Wait ~30 seconds, then visit `https://journal.chaseconover.com`. Cloudflare auto-provisions the TLS cert and DNS record.

## Adding a new public service

When you decide to expose another service publicly:

1. **Make sure the service has its own auth.** Cloudflare Tunnel has no built-in auth (Cloudflare Access is a separate paid product). The application is the only thing standing between the public internet and your data.
2. Add a public hostname in the dashboard pointing to the container directly (NOT to Caddy).
3. Pick a hostname that's NOT under `*.lab.*` so the convention "`lab.*` = tailnet, others = public" holds.
4. Update this doc's "What's exposed publicly" table.
5. Update `README.md` Running Services and `docs/services.md`.

## Removing a public service

1. Remove its row from the dashboard's Public Hostname tab.
2. Wait a minute for propagation, verify the public URL returns no DNS resolution or 404.
3. Optionally delete the Cloudflare DNS record (the dashboard does this automatically on hostname removal in most cases).
4. Update docs.

## Trust model

Be honest about what Cloudflare Tunnel does and doesn't do:

- **Hides your home IP**: yes, fully.
- **Protects against DDoS**: yes, Cloudflare's edge absorbs it.
- **Protects against application-level vulnerabilities**: no. If Chronicle has a bug, anyone on the internet can hit it. Patch promptly.
- **Encrypts end-to-end**: no. Cloudflare terminates TLS at their edge and re-encrypts to your origin; they can technically see plaintext request/response bodies. For a personal journal this is industry-standard but worth knowing — Tailscale-fronted services do not have this property.

If a service is too sensitive for plaintext-at-CF, keep it tailnet-only.

## Troubleshooting

- **`cloudflared` container restarting:** check `docker logs cloudflared`. Most common cause: invalid or stale `TUNNEL_TOKEN` in `/etc/self-hosted/cloudflared.env`.
- **`502 Bad Gateway` at the public URL:** the tunnel is connected but `cloudflared` can't reach the upstream container. Check that the target container is on the `internal` Docker network and the container name + port in the dashboard ingress rule match.
- **`1033 — Argo Tunnel error` page from Cloudflare:** the tunnel itself is down. Restart `cloudflared` (`docker compose restart cloudflared`).
- **Sudden dashboard shows the entire homelab on the public URL:** someone (you, future-you, or a config drift) pointed an ingress rule at `caddy:443`. Fix the dashboard immediately, then audit. This is the failure mode this doc exists to prevent.
