# HTTPS with Let's Encrypt and Cloudflare DNS

Caddy serves all homelab services over HTTPS using Let's Encrypt certificates, provisioned via DNS challenge with Cloudflare DNS.

## How It Works

1. Caddy requests a TLS certificate from Let's Encrypt for `*.lab.chaseconover.com`
2. Let's Encrypt asks Caddy to prove domain ownership via a DNS TXT record
3. Caddy uses the Cloudflare API to create the TXT record automatically
4. Let's Encrypt verifies and issues the certificate
5. Caddy deletes the TXT record and serves HTTPS

No ports are exposed to the internet. The DNS challenge only requires API access to Cloudflare, not inbound HTTP.

## Cloudflare Setup

### 1. Add a wildcard CNAME record

In the Cloudflare DNS dashboard for `chaseconover.com`, add this record:

| Name | Type | Value | Proxy |
|------|------|-------|-------|
| `*.lab` | CNAME | `chase-raspberrypi.<your-tailnet>.ts.net` | DNS only (gray cloud) |

The full hostname is `*.lab.chaseconover.com`. **Proxy must be off (gray cloud)** — Cloudflare cannot proxy traffic to a Tailscale hostname; this record is publicly resolvable but only reachable from inside the tailnet.

### 2. Create a scoped API token

In Cloudflare → My Profile → API Tokens → **Create Token**:

- Use the **Edit zone DNS** template
- **Permissions:** `Zone — DNS — Edit`
- **Zone Resources:** `Include — Specific zone — chaseconover.com`
- (Leave IP filter and TTL unset, or scope as you prefer)

Copy the token. It is shown only once.

### 3. Create the Caddy secrets file on the Pi

SSH into the Pi and create `/etc/self-hosted/caddy.env`:

```bash
sudo tee /etc/self-hosted/caddy.env > /dev/null << 'EOF'
CLOUDFLARE_API_TOKEN=<your-token>
EOF
sudo chmod 600 /etc/self-hosted/caddy.env
```

### 4. Deploy

```bash
./scripts/deploy deploy
```

The first deploy will build a custom Caddy image (includes the Cloudflare DNS module) and provision certificates. This takes a few minutes on the Pi.

If you are migrating from a previous DNS provider (e.g. Route 53), the existing Caddy image was built with a different DNS module and must be rebuilt:

```bash
ssh chaseconover@192.168.1.167 \
  'cd /srv/self-hosted/compose && \
   sudo docker compose --project-name homelab build caddy && \
   sudo docker compose --project-name homelab up -d caddy'
```

## Pi-hole DNS (Split Horizon)

Pi-hole resolves `*.lab.chaseconover.com` locally so the homelab works regardless of internet connectivity:

- **On LAN**: Pi-hole returns the LAN IP (`192.168.1.167`) — direct connection
- **On Tailscale (remote)**: Pi-hole returns the Tailscale IP — encrypted tunnel
- **Internet down**: Pi-hole still answers from its local config — homelab works

This is configured automatically by Ansible via dual `address=` entries in the dnsmasq config.

## Custom Caddy Image

The standard Caddy image doesn't include DNS provider modules. A custom image is built from `platform/compose/caddy/Dockerfile` using `xcaddy` to include the `caddy-dns/cloudflare` module. The image is built on the Pi during the first deploy and cached for subsequent deploys.

## Certificate Renewal

Let's Encrypt certificates are valid for 90 days. Caddy automatically renews them before expiry using the same DNS challenge process. No manual intervention needed.
