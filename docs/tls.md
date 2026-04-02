# HTTPS with Let's Encrypt and Route 53

Caddy serves all homelab services over HTTPS using Let's Encrypt certificates, provisioned via DNS challenge with AWS Route 53.

## How It Works

1. Caddy requests a TLS certificate from Let's Encrypt for `*.lab.chaseconover.com`
2. Let's Encrypt asks Caddy to prove domain ownership via a DNS TXT record
3. Caddy uses the Route 53 API to create the TXT record automatically
4. Let's Encrypt verifies and issues the certificate
5. Caddy deletes the TXT record and serves HTTPS

No ports are exposed to the internet. The DNS challenge only requires API access to Route 53, not inbound HTTP.

## Route 53 Setup

### 1. Add a wildcard CNAME record

In the AWS Route 53 console, add this record to your hosted zone for `chaseconover.com`:

| Name | Type | Value |
|------|------|-------|
| `*.lab.chaseconover.com` | CNAME | `chase-raspberrypi.<your-tailnet>.ts.net` |

This points all `*.lab.chaseconover.com` subdomains to the Pi's Tailscale hostname. Only devices on the tailnet can reach it.

### 2. Create an IAM policy

Create an IAM policy with minimal Route 53 permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:GetChange"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/<YOUR_HOSTED_ZONE_ID>"
    }
  ]
}
```

### 3. Create an IAM user

1. Create an IAM user (e.g., `homelab-caddy`)
2. Attach the policy from step 2
3. Generate access keys

### 4. Create the Caddy secrets file on the Pi

SSH into the Pi and create `/etc/self-hosted/caddy.env`:

```bash
sudo tee /etc/self-hosted/caddy.env > /dev/null << 'EOF'
AWS_ACCESS_KEY_ID=<your-access-key>
AWS_SECRET_ACCESS_KEY=<your-secret-key>
AWS_HOSTED_ZONE_ID=<your-hosted-zone-id>
AWS_REGION=us-east-1
EOF
sudo chmod 600 /etc/self-hosted/caddy.env
```

Find your hosted zone ID in the Route 53 console under "Hosted zones".

### 5. Deploy

```bash
./scripts/deploy deploy
```

The first deploy will build a custom Caddy image (includes the Route 53 DNS module) and provision certificates. This takes a few minutes on the Pi.

## Pi-hole DNS (Split Horizon)

Pi-hole resolves `*.lab.chaseconover.com` locally so the homelab works regardless of internet connectivity:

- **On LAN**: Pi-hole returns the LAN IP (`192.168.1.167`) — direct connection
- **On Tailscale (remote)**: Pi-hole returns the Tailscale IP — encrypted tunnel
- **Internet down**: Pi-hole still answers from its local config — homelab works

This is configured automatically by Ansible via dual `address=` entries in the dnsmasq config.

## Custom Caddy Image

The standard Caddy image doesn't include DNS provider modules. A custom image is built from `platform/compose/caddy/Dockerfile` using `xcaddy` to include the `caddy-dns/route53` module. The image is built on the Pi during the first deploy and cached for subsequent deploys.

## Certificate Renewal

Let's Encrypt certificates are valid for 90 days. Caddy automatically renews them before expiry using the same DNS challenge process. No manual intervention needed.
