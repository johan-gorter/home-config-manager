# Kiosk

A screen (the laptop's own panel works) that boots straight into the Home
Assistant dashboard, with nothing else reachable.

> **Status:** the design below is current; the session starts and shows the
> dashboard, but on Ubuntu 26.04 GDM was seen to take the screen back after
> about 10 seconds and show the login screen instead (see
> [Known issue](#known-issue-gdm-shows-the-login-screen-after-10-seconds)).
> Verify after a reboot before relying on it.

## Design

```
GDM autologin (user kiosk) → Wayland session "kiosk" → cage → Firefox --kiosk → http://localhost:8123
```

- **GDM autologin** to a dedicated session, not a second X server. The older
  approach (`startx -- vt7` from a systemd service, Openbox) collides with GDM on
  Ubuntu Desktop: GDM is already DRM master on the GPU, the second X server
  cannot get in, and the service ends up in a restart loop.
- **`cage`**: a minimal Wayland compositor that shows exactly one full-screen
  app. No window manager, no Alt+Tab, no screen blanking, no desktop.
- **Firefox** (the Ubuntu snap works fine in this setup) with its own profile
  and a root-owned `user.js`: no first-run pages, no "restore session?" after a
  power cut. A wrapper restarts it if it exits.
- Your own account logs in through Ctrl+Alt+F1 (`cage -s` allows VT switching).
  Make your desktop session lock itself when you switch back — see
  [laptop-as-server.md](laptop-as-server.md#logging-in-at-the-machine).

Files: [`examples/kiosk/`](../examples/kiosk/).

```bash
sudo apt install cage curl
sudo useradd -m -s /bin/bash kiosk && sudo passwd -l kiosk && sudo chmod 750 /home/kiosk
sudo install -m 755 examples/kiosk/kiosk-session examples/kiosk/kiosk-browser /usr/local/bin/
sudo install -D -m 644 examples/kiosk/user.js /usr/local/share/kiosk/user.js
sudo install -m 644 examples/kiosk/kiosk.desktop /usr/share/wayland-sessions/
sudo install -m 644 examples/kiosk/AccountsService-kiosk /var/lib/AccountsService/users/kiosk
# then add the [daemon] lines from examples/kiosk/gdm-custom.conf to /etc/gdm3/custom.conf
```

**Do not install** `xserver-xorg-video-intel` (deprecated, can override the
modern `modesetting` driver), and no `Xwrapper.config allowed_users=anybody`.

## Security

A kiosk browser is a threshold, not a security boundary. Three layers:

1. **A separate, non-admin HA user** for the kiosk, `local_only`, not a person.
   The biggest win for the least effort: a non-admin does not see Settings,
   Integrations or Developer tools. Without it any visitor can call any service
   through Developer tools → Actions. With [remote access](remote-access.md),
   `local_only` is only safe once `trusted_proxies` is set.
2. **The Linux user `kiosk`** has its password locked, no sudo, and is in no
   extra groups — **not** `input` (read access to every keyboard is a keylogger
   on the whole machine, your typing included) and not `docker`. It cannot read
   `/srv/homeassistant` (mode 750). Check: `sudo -u kiosk ls /srv/homeassistant`
   must fail.
3. **A browser policy** owned by root: developer tools, private browsing,
   downloads and printing off, and a URL filter that only allows
   `localhost:8123` (which also blocks `file://` and `view-source:`). Catch:
   the Firefox snap reads `/etc/firefox/policies/policies.json` for **every**
   user, so a URL filter there also locks down your own Firefox. Options: use a
   different browser for the kiosk (Chromium's policies can also be set
   system-wide, but then Chromium is the kiosk's alone), or accept the filter.

## Touch or trackpad

If the panel is not a touchscreen, leave the cursor visible: the trackpad is the
only way to use the dashboard. For a touch panel, hide it.

## Known issue: GDM shows the login screen after 10 seconds

Seen on Ubuntu 26.04 (GDM 50): the autologin session starts, cage sets the mode
on the panel, and about 10 seconds later GDM starts its greeter and takes the
seat away (`Atomic commit failed: Permission denied` in the journal for
`gdm-wayland-session`). The kiosk session ends and the login screen remains.

Likely cause: newer GDM waits for a session to *register* with it and falls back
to the greeter when it does not; only GNOME's own session registers (Ubuntu's
`ubuntu.desktop` declares `X-GDM-SessionRegisters=true`). The candidate fix, **not yet verified**, is to tell GDM this session does not
register, in `kiosk.desktop`:

```ini
X-GDM-SessionRegisters=false
```

Diagnose with:

```bash
sudo journalctl -b -u gdm
sudo journalctl -b | grep gdm-wayland-session
loginctl list-sessions            # is there a session for user kiosk?
```

Update this section once it is confirmed.
