# CLAUDE.md

This repository is a **generic blueprint** for a Home Assistant homelab: best
practices and example configuration, no install scripts. Claude Code is used to
set up and manage a server by following these docs.

The user has basic Linux knowledge — prefer clear explanations, avoid jargon,
and run commands directly rather than asking the user to do so.

## Nothing house-specific in this repo

This repo is public and is reused for future installations. Never commit
hostnames, IP addresses, device names, automations, account names, domain names,
tokens or anything else that belongs to one house.

The house-specific setup lives in a **private repo**, loaded through a
`CLAUDE.local.md` in this directory (git-ignored), for example:

```markdown
This server is <house>. Its configuration lives in /path/to/<house>-config.
Where it differs from the generic CLAUDE.md, that file wins. House-specific
edits and commits go there, never to this public repo.

@/path/to/<house>-config/CLAUDE.md
```

If there is no `CLAUDE.local.md` yet, ask the user which machine and house this
is before changing anything on the system.

When a lesson learned in a house is generally useful, generalise it (remove the
names, keep the reasoning) and add it to the docs here.

## Docs, not scripts

Do not add install scripts. Each document explains *what* to do and *why*, with
example code. Apply it by hand on the actual machine, check the result, and
record what was done in the private repo (an install log works well). Example
files in `examples/` use placeholders like `<server-ip>` and `ha.example.com`.

Start with `docs/new-install.md`; `README.md` lists all topics.

## Working rules

- Adding devices and integrations happens in the Home Assistant **web interface
  or API**, not in files. Never hand-edit `.storage/`. See `docs/claude-access.md`.
- **Important lights must have a physical fallback**: lights in essential spaces
  (toilets, hallways, stairs) must keep working through a direct Zigbee bind when
  the network, the server or Zigbee2MQTT is down. Bind the button to a Zigbee
  **group** containing the lamp, not to the lamp itself — a device-level bind
  reports success but does nothing. See `docs/light-with-fallback.md`.
- Ports of internal services (MQTT, databases, Matter server) listen on
  `127.0.0.1` only. See `docs/architecture.md`.
- Anything that changes the firewall, remote access or authentication: explain
  the change and its risk before applying it.
