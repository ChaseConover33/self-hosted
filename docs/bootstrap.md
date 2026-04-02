# Bootstrap

## Preconditions

- Debian host is reachable over SSH
- your workstation has Ansible installed
- Docker is not required on the workstation
- the repo exists locally on your workstation

## Configure Inventory

Edit `ansible/inventory/production/hosts.yml`:

- set `ansible_host` to the Debian VM IP
- set `ansible_user` to the current SSH-capable user

## Configure Group Vars

Edit `ansible/group_vars/all.yml`:

- leave `platform_lan_cidr: auto` to follow the VM's current network, or set a manual CIDR override
- adjust internal hostnames if needed
- decide whether to enable `platform_manage_admin_user`
- if managing the admin user, add `platform_admin_authorized_keys`
- review which services are enabled

## Validate

```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml
./scripts/validate
```

## Bootstrap

```bash
./scripts/deploy bootstrap
```

This installs:

- base packages
- Docker Engine and Compose plugin
- UFW firewall rules limited to the LAN CIDR
- Caddy JSON config
- systemd timers for lightweight monitoring and backups
- the Compose stack

## Verify

- browse to `https://demo.lab.chaseconover.com`
- browse to `https://status.lab.chaseconover.com`
- verify DNS through hosts-file entries if local DNS is not available yet

Example hosts-file entries:

```text
192.168.64.10 demo.lab.chaseconover.com
192.168.64.10 status.lab.chaseconover.com
```
