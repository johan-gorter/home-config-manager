# A laptop as server

An old laptop makes a good Home Assistant server: little power, a built-in
screen for a [kiosk](kiosk.md), and a battery that acts as a UPS. It does need
a few changes so it behaves like a server.

**The hard requirement:** after a reboot or power cut, everything comes back by
itself, without anyone logging in, so lights and automations work right away.

## Never sleep

Ubuntu Desktop is worse than Server here: GNOME suspends when idle and when the
lid closes.

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Plus [`examples/systemd/logind-99-homelab.conf`](../examples/systemd/logind-99-homelab.conf)
so closing the lid does nothing, on every power source.

## Battery as UPS — with a charge limit

24/7 at 100 % wears a battery out within a year or two, and then the UPS is gone.
Keep it between 60 and 70 %:
[`examples/systemd/battery-charge-limit.service`](../examples/systemd/battery-charge-limit.service).

Check afterwards that it actually works: unplug, let it drop below 60 %, plug in,
and watch it stop at 70 %. Some firmware (Dell, for one) silently ignores the
thresholds until `charge_types` is set to `Custom`.

## Networking

- **DHCP reservation** in the router for the server and for any network device
  HA talks to by IP (coordinator, WiFi dimmers). Integrations are IP-sensitive.
- **WiFi works** if there is no Ethernet port, but keep the laptop close to an
  access point.
- Pin the **2.4 GHz WiFi channel** of every access point. See [zigbee.md](zigbee.md#channel).

## Updates and reboots

```bash
sudo cp examples/systemd/52homelab-unattended /etc/apt/apt.conf.d/
```

Ubuntu's `unattended-upgrades` installs updates every morning. With this file,
when an update needs a reboot (`/var/run/reboot-required`), the machine reboots
at the next 03:30 — and only then.

**No fixed nightly reboot.** A reboot shortly after a scheduled `apt upgrade` can
land in the middle of a dpkg transaction or a database write, and whoever walks
to the toilet at that minute has no smart light. A reboot to work around a leak
treats a symptom; find the leak instead. Lights on [direct binds](light-with-fallback.md)
keep working during the few minutes a needed reboot takes.

Docker images are updated by hand (see [architecture.md](architecture.md#day-to-day-commands)).

## Logging in at the machine

With a kiosk, the screen shows the dashboard after boot. Switching to the login
screen is Ctrl+Alt+F1. Make sure your own desktop session **locks itself** as
soon as you switch back to the kiosk — otherwise the next visitor can switch VT
and find an unlocked admin desktop. A small user service that watches the
session's `Active` property and calls `loginctl lock-session` does the job.
