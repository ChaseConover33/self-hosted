# DNS Routing Strategies

This document covers three approaches to DNS resolution for the homelab, including the tradeoffs of each and which was chosen.

DNS (Domain Name System) is the service that translates human-readable names like `tasks.lab.chaseconover.com` or `google.com` into IP addresses that computers actually route to. Every device on your network makes DNS queries constantly — every tab you open, every app that checks for updates.

---

## Strategy 1: Current State (router DNS + /etc/hosts)

Before Pi-hole. The Mac has homelab hostnames hardcoded in `/etc/hosts`. All other DNS goes through the router. The iPhone has no way to resolve homelab hostnames at all.

```mermaid
flowchart TD
    subgraph Mac
        APP1[Browser / App]
        HOSTS["/etc/hosts\n(hardcoded homelab hostnames)"]
    end

    subgraph iPhone
        APP2[Browser / App]
    end

    subgraph Roommates
        APP3[Their devices]
    end

    ROUTER["Router\n192.168.1.1"]
    VERIZON["Verizon DNS\n71.252.0.12"]
    PI["Raspberry Pi\n192.168.1.167"]

    APP1 -->|"lab.chaseconover.com query"| HOSTS
    HOSTS -->|"resolved locally\nno network query"| APP1
    APP1 -->|"all other queries"| ROUTER
    ROUTER --> VERIZON
    VERIZON -->|"returns IP"| ROUTER
    ROUTER --> APP1

    APP2 --> ROUTER
    APP3 --> ROUTER
    ROUTER --> VERIZON
```

**Problems with this approach:**
- iPhone cannot reach homelab services by hostname — only by raw IP
- Adding a new service requires manually editing `/etc/hosts` on every device
- No ad blocking

---

## Strategy 2: Per-Device Pi-hole (chosen)

Each personal device (Mac, iPhone) is manually configured to use Pi-hole as its DNS server. The router and roommates' devices are completely unchanged.

```mermaid
flowchart TD
    subgraph Mac
        APP1[Browser / App]
    end

    subgraph iPhone
        APP2[Browser / App]
    end

    subgraph Roommates
        APP3[Their devices\nunchanged]
    end

    PIHOLE["Pi-hole\n192.168.1.167:53\n\ncustom.list:\nlab.chaseconover.com hostnames\nblock: ad/tracker domains"]
    ROUTER["Router\n192.168.1.1\n(secondary / fallback)"]
    VERIZON["Verizon DNS\n71.252.0.12"]
    PI_SERVICES["Homelab Services\nvia Caddy"]

    APP1 -->|"DNS query\nprimary"| PIHOLE
    APP2 -->|"DNS query\nprimary"| PIHOLE

    PIHOLE -->|"lab.chaseconover.com query\nresolved from custom.list"| PI_SERVICES
    PIHOLE -->|"ad/tracker domain\nblocked — returns nothing"| APP1
    PIHOLE -->|"everything else"| VERIZON

    APP1 -->|"Pi-hole down\nfallback to secondary"| ROUTER
    APP2 -->|"Pi-hole down\nfallback to secondary"| ROUTER
    ROUTER --> VERIZON

    APP3 -->|"unaffected\nnormal internet"| ROUTER
    ROUTER --> VERIZON
```

**Device DNS configuration:**
| Device | Primary DNS | Secondary DNS |
|--------|-------------|---------------|
| Mac | `192.168.1.167` | `192.168.1.1` |
| iPhone | `192.168.1.167` | `192.168.1.1` |
| All others | (unchanged — via router) | |

**Why this approach was chosen:**
- Roommates are completely unaffected — no shared infrastructure changes
- Fallback to router → Verizon DNS if Pi is down, so internet still works
- Homelab hostnames resolve on Mac and iPhone without `/etc/hosts` entries
- New services added to `platform_services` are automatically resolvable after next deploy (Ansible regenerates `custom.list`)

---

## Strategy 3: Router-Level Pi-hole (reference)

The router is configured to advertise Pi-hole as the DNS server for all devices via DHCP. Every device on the network automatically uses Pi-hole without any per-device configuration.

```mermaid
flowchart TD
    subgraph All Devices
        APP1[Mac]
        APP2[iPhone]
        APP3[Roommates]
        APP4[Smart TV / IoT]
    end

    ROUTER["Router\n192.168.1.1\nDHCP advertises Pi-hole as DNS"]
    PIHOLE["Pi-hole\n192.168.1.167:53\n\ncustom.list:\nlab.chaseconover.com hostnames\nblock: ad/tracker domains"]
    FALLBACK["Secondary DNS\n71.252.0.12 (Verizon)\nused if Pi-hole unreachable"]
    VERIZON["Verizon DNS\n71.252.0.12"]

    APP1 -->|"DNS query\n(via DHCP)"| PIHOLE
    APP2 --> PIHOLE
    APP3 --> PIHOLE
    APP4 --> PIHOLE

    PIHOLE -->|"lab.chaseconover.com\nresolved from custom.list"| APP1
    PIHOLE -->|"everything else"| VERIZON
    PIHOLE -->|"Pi-hole down\ndevices fall back"| FALLBACK
```

**Why this was not chosen (yet):**
- Affects roommates without their knowledge
- Verizon CR1000A has hardcoded DNS server entries that cannot be deleted — custom DNS entries are added alongside Verizon's, not in place of them. Behavior when multiple DNS servers are configured is unpredictable.
- Per-device approach provides equivalent functionality for personal devices with no shared risk

**When to switch to this approach:**
- If you move to your own router hardware (not ISP-provided)
- If you live alone or roommates consent
- Once Pi-hole reliability is established over time

---

## Remote Access via Tailscale (current)

Tailscale provides secure remote access to the homelab from any network. Pi-hole uses **split horizon DNS** to return the right IP based on where the query comes from.

```mermaid
flowchart TD
    subgraph "Home LAN"
        MAC[Mac / iPhone]
    end

    subgraph "Remote (cell data / friend's house)"
        PHONE[Phone with Tailscale]
        FRIEND[Friend with Tailscale]
    end

    PIHOLE["Pi-hole (host networking)\n\nlocal=/lab.chaseconover.com/\nlocalise-queries\n\nLAN queries → 192.168.1.167\nTailscale queries → 100.x.y.z"]

    CADDY["Caddy (HTTPS)\nLet's Encrypt certs\nvia Route 53 DNS challenge"]

    ROUTE53["Route 53\n*.lab.chaseconover.com\nCNAME → Pi's Tailscale hostname"]

    MAC -->|"DNS query on eth0"| PIHOLE
    PIHOLE -->|"returns 192.168.1.167\n(LAN IP)"| MAC
    MAC -->|"direct LAN"| CADDY

    PHONE -->|"DNS query on tailscale0"| PIHOLE
    PIHOLE -->|"returns 100.x.y.z\n(Tailscale IP)"| PHONE
    PHONE -->|"encrypted tunnel"| CADDY

    FRIEND -->|"DNS via Tailscale"| PIHOLE
    FRIEND -->|"encrypted tunnel"| CADDY
```

**How it works:**

1. Pi-hole runs with **host networking** so it can see whether a DNS query arrived on `eth0` (LAN) or `tailscale0` (Tailscale)
2. Each hostname has **two `address=` records** in dnsmasq — one LAN IP, one Tailscale IP
3. The `localise-queries` directive returns the IP matching the query's source subnet
4. The `local=/lab.chaseconover.com/` directive prevents Pi-hole from forwarding queries upstream to Route 53 (which would return the CNAME and override local records)
5. Caddy serves all requests over **HTTPS** with Let's Encrypt certificates provisioned via Route 53 DNS challenge

**DNS resolution by scenario:**

| Location | DNS server | Interface | IP returned | Connection |
|----------|-----------|-----------|-------------|------------|
| Home LAN | Pi-hole | eth0 | 192.168.1.167 | Direct |
| Home LAN, internet down | Pi-hole | eth0 | 192.168.1.167 | Direct (still works) |
| Remote via Tailscale | Pi-hole | tailscale0 | 100.x.y.z | Encrypted tunnel |
| Not on tailnet | Route 53 | N/A | Tailscale hostname (unreachable) | Blocked |

**Key dnsmasq config files:**

- `/etc/dnsmasq.d/01-tailscale.conf` — enables `localise-queries` and `local=/lab.chaseconover.com/`
- `/etc/dnsmasq.d/02-homelab.conf` — dual `address=` records for all services (auto-generated by Ansible)
