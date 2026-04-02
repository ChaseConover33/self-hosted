# Tailscale Remote Access

This document covers setting up Tailscale for secure remote access to your homelab, including giving friends limited access to services.

## Overview

Tailscale creates a private mesh network (tailnet) between your devices. Combined with ACLs, it lets you:

- Access all homelab services remotely from any device
- Give friends access to web services only (no SSH, no infrastructure)
- Keep everything private — no ports exposed to the public internet

## Initial Setup

### 1. Install Tailscale on the Pi

Ansible handles this automatically via the `tailscale` role. After a deploy:

```bash
# SSH into the Pi and authenticate
sudo tailscale up --advertise-tags=tag:homelab
```

You'll get a URL to authenticate in your browser. The `--advertise-tags` flag tags the Pi for use in ACL rules.

### 2. Set Pi-hole as Tailnet DNS

In the [Tailscale admin console](https://login.tailscale.com/admin/dns):

1. Go to **DNS** settings
2. Under **Nameservers**, add a custom nameserver:
   - Address: your Pi's Tailscale IP (find it with `tailscale ip -4` on the Pi)
   - Restrict to domain: `lab.chaseconover.com`
3. This makes `*.lab.chaseconover.com` resolve for all tailnet devices, even when remote

### 3. Install Tailscale on Your Devices

Install Tailscale on your laptop, phone, etc. and sign in with the same account. You'll immediately be able to reach `media.lab.chaseconover.com`, `git.lab.chaseconover.com`, etc. from anywhere.

## How Remote Access Works (Split Horizon DNS)

Pi-hole uses **split horizon DNS** so that the same hostname resolves to different IPs depending on where you are:

| Query source | Interface | `media.lab.chaseconover.com` resolves to | Connection path |
|---|---|---|---|
| LAN (home WiFi) | `eth0` | `192.168.1.167` (LAN IP) | Direct LAN connection |
| Remote (cell data, friend's house) | `tailscale0` | Pi's Tailscale IP (100.x.y.z) | Encrypted Tailscale tunnel |

This is achieved by:
1. **Pi-hole runs with host networking** — so it can see which interface (LAN vs Tailscale) the DNS query arrived on
2. **Dual DNS records** — Ansible generates two `address=` entries per hostname (one LAN IP, one Tailscale IP)
3. **dnsmasq `localise-queries`** — automatically returns the IP matching the query's source subnet
4. **dnsmasq `local=/lab.chaseconover.com/`** — prevents Pi-hole from forwarding queries upstream to Route 53, which would return the CNAME and override local records. This also ensures the homelab works during internet outages.

No subnet routing is needed. All traffic from remote devices goes directly to the Pi's Tailscale IP through the encrypted tunnel.

## ACL Policy for Friend Access

Tailscale ACLs are configured in the [admin console](https://login.tailscale.com/admin/acls). Paste this policy to give yourself full access while restricting friends to web services only.

```jsonc
{
  // Define tag ownership — only your account can apply these tags
  "tagOwners": {
    "tag:homelab": ["autogroup:admin"]
  },

  // Define groups
  "groups": {
    "group:friends": [
      // Add friends' Tailscale login emails here
      // "friend1@gmail.com",
      // "friend2@gmail.com"
    ]
  },

  "acls": [
    // Admins (you) get full access to everything
    {
      "action": "accept",
      "src":    ["autogroup:admin"],
      "dst":    ["*:*"]
    },

    // Friends can only reach web services (Caddy reverse proxy)
    {
      "action": "accept",
      "src":    ["group:friends"],
      "dst":    ["tag:homelab:80,443"]
    },

    // Friends can reach Pi-hole DNS (so *.lab.chaseconover.com resolves)
    {
      "action": "accept",
      "src":    ["group:friends"],
      "dst":    ["tag:homelab:53"]
    },

    // Friends can use Gitea SSH for git clone/push
    {
      "action": "accept",
      "src":    ["group:friends"],
      "dst":    ["tag:homelab:2222"]
    }
  ]
}
```

### What friends CAN access

| Port | Service | What they can do |
|------|---------|-----------------|
| 80   | Caddy (HTTP) | Browse all web services: Jellyfin, Gitea, Archive, etc. |
| 53   | Pi-hole (DNS) | Resolve `*.lab.chaseconover.com` hostnames |
| 2222 | Gitea (SSH) | `git clone`, `git push` over SSH |

### What friends CANNOT access

- SSH (port 22) — no shell access to the Pi
- Docker API — no container management
- Any direct container ports — everything goes through Caddy
- Pi-hole admin — blocked by Pi-hole's own authentication
- Service databases — only on the internal Docker network

## Inviting Friends

### Option A: Share a node (friends keep their own tailnet)

Best when friends already use Tailscale for their own stuff.

1. Go to [Tailscale admin console](https://login.tailscale.com/admin/machines)
2. Click the **...** menu on your Pi
3. Select **Share...**
4. Enter your friend's Tailscale login email
5. They accept the share invitation on their end

### Option B: Invite to your tailnet

Best when friends don't use Tailscale yet and you want simpler management.

1. Go to [Tailscale admin console](https://login.tailscale.com/admin/users)
2. Click **Invite users**
3. Send them the invite link
4. Once they join and install Tailscale, add their email to `group:friends` in the ACL policy

### Friend setup steps

Send this to your friends:

> 1. Install Tailscale: https://tailscale.com/download
> 2. Sign in (I'll send you an invite or share link)
> 3. Once connected, open these in your browser:
>    - `https://media.lab.chaseconover.com` — Jellyfin (create your own account)
>    - `https://git.lab.chaseconover.com` — Gitea (create your own account)
>    - `https://archive.lab.chaseconover.com` — Offline Wikipedia, Stack Overflow, etc.
> 4. For git over SSH, add this to your `~/.ssh/config`:
>    ```
>    Host git.lab.chaseconover.com
>      Port 2222
>    ```
>    Then: `git clone git@git.lab.chaseconover.com:username/repo.git`

## Firewall Notes

The Tailscale role automatically opens UDP port 41641 for direct peer connections. Tailscale traffic is encrypted end-to-end and authenticated — UFW rules don't apply to Tailscale traffic since it arrives via the `tailscale0` interface after decryption.

The ACLs are the real access control layer. Even if someone joins your tailnet, they can only reach ports explicitly allowed in the ACL policy.

## Tailscale Serve (Optional)

The existing chat helper script at `/usr/local/bin/self-hosted-share-chat-tailnet` uses `tailscale serve` to expose Synapse directly. This is an alternative to the Caddy-based approach and can be useful for specific services that need HTTPS (Tailscale Serve provides automatic TLS).
