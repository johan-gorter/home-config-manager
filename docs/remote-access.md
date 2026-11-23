# Remote access

Reach Home Assistant from outside (the family's phones) without port forwarding
on the home router, without a VPN app on every phone, and without depending on
a cloud service.

```
family (HA app) ──HTTPS + MFA──► VPS (Caddy) ══WireGuard══► server:8123
admin           ──SSH key──────► VPS ══WireGuard══► server:22
```

The home server **dials out** to a small VPS over WireGuard; the VPS runs Caddy
as an HTTPS reverse proxy. The VPS holds no data: replacing it is a quarter of
an hour of work.

Alternatives and why not: port forwarding exposes the home network directly;
Tailscale/Headscale needs an app on every family device and leans on a
third-party relay; Nabu Casa is a paid cloud dependency. All are valid choices —
this setup trades a few euros a month and an hour of work for full control.

## VPS

- Small Debian or Ubuntu VPS (1 vCPU, 1 GB is plenty).
- `unattended-upgrades` with automatic reboot when needed (at a different time
  than the home server).
- SSH: keys only, `AllowUsers` set, root login off.
- `ufw`: 22 (rate-limited), 80, 443, 51820/udp. IP forwarding **off**.
- Caddy from Caddy's apt repository: [`examples/remote-access/Caddyfile`](../examples/remote-access/Caddyfile).
  Caddy fetches and renews certificates itself. DNS: an A (and AAAA) record for
  `ha.example.com` pointing at the VPS.
- WireGuard: [`examples/remote-access/wg0-vps.conf`](../examples/remote-access/wg0-vps.conf).

## Home server

- WireGuard: [`examples/remote-access/wg0-server.conf`](../examples/remote-access/wg0-server.conf),
  `systemctl enable --now wg-quick@wg0`.
- Firewall: [`examples/remote-access/homelab-remote.nft`](../examples/remote-access/homelab-remote.nft)
  with its service. From the tunnel only the VPS, and only ports 22 and 8123; no
  forwarding from the tunnel. A compromised VPS reaches HA's login page and
  SSH's key check, and nothing else — not Zigbee2MQTT, not the LAN.
- **Never put rules in `/etc/nftables.conf`** or enable `nftables.service`: that
  file starts with `flush ruleset` and wipes Docker's rules. Use an own table.
- **Leave `ufw` off on the HA server.** With HA on the host network it breaks
  discovery (mDNS, Matter, Thread) unless configured very carefully.
- Many home connections give the server **public IPv6 addresses**. Without the
  SSH rule above you depend on the router's IPv6 firewall. Test from outside.

## Home Assistant behind the proxy

Required **before** opening `ha.` to the internet:

- `use_x_forwarded_for: true` and `trusted_proxies: 10.77.0.1/32`. Without them
  all traffic arrives as `10.77.0.1`, a private address: HA treats internet
  visitors as local (so a `local_only` kiosk account works from the internet),
  and login bans hit the proxy instead of the attacker.
- `ip_ban_enabled: true`, `login_attempts_threshold: 5`.
- `external_url: https://ha.example.com`.
- **MFA (TOTP) for every account**, family included, before going public.

Recent HA versions ignore an `http:` block in `configuration.yaml` once they
have migrated it: the settings live in HA's store. Change them with the
WebSocket commands `http/config` (read), `http/config/configure` (stores a
*pending* config and restarts HA) and `http/config/promote` (makes it stable).
An unconfirmed pending config reverts by itself after 5 minutes. Right after the
restart call HA answers for a few seconds on the old process; wait before testing.

**Test it:** make a deliberately failed login under a made-up name from a phone
on mobile data. HA's log must show the phone's public address, not `10.77.0.1`.
And logging in as the kiosk user through `ha.example.com` must be refused.

## What stays unreachable — on purpose

Zigbee2MQTT, the coordinator's web UI, InfluxDB and the rest of the home network
are not reachable from outside. Voice control stays local (HA Assist) rather
than through Google or Alexa, which would need a cloud link.
