# ROADMAP — Home Assistant server Geulwijk

Plan voor de nieuwe opstelling in het nieuwe huis. De bestaande `scripts/` uit
deze repo gelden als **requirements, niet als implementatie**: het idee klopt
(Docker Compose, templates, systemd, kiosk, watchdog, backup), de uitvoering
wordt opnieuw gedaan op Ubuntu Desktop 26.04.

## Uitgangspunten

| | |
|---|---|
| Hardware | Laptop, Intel, eDP-paneel. Accu = ingebouwde UPS |
| OS | Ubuntu Desktop 26.04 LTS (was: Server) |
| Zigbee | Nieuwe, betere antenne/coördinator (type nog te bepalen — zie B4) |
| Gebruikers | `jgo` (beheer, sudo) · `homeassistant` (draait de stack) · `kiosk` (toont het dashboard) |
| Fysieke beveiliging | **Buiten scope.** Geen LUKS, geen BIOS/GRUB-wachtwoord. Wie bij de laptop kan, is root — dat accepteren we bewust |
| Harde eis | Na een reboot komt alles vanzelf op, zonder handeling, zodat lampen en automatiseringen direct werken |
| Node-RED | **Nee.** HA's eigen automatiseringen volstaan; twee plekken met logica maakt debuggen dubbel zo moeilijk |

---

# Deel 1 — Dit gaan we sowieso doen

## 1. Gebruikers en rechten

- [ ] Gebruiker `homeassistant` (geen sudo) is eigenaar van de datamap.
- [ ] Gebruiker `kiosk` (geen sudo, geen groepslidmaatschappen behalve het
      strikt noodzakelijke) draait alleen de browser.
- [ ] `jgo` wordt lid van groep `homeassistant` en kan daarmee **zonder sudo**
      YAML bewerken.
- [ ] Datamap wordt `root:homeassistant`, mode `750`, met **setgid-bit op alle
      directories** en een **default-ACL** `g:homeassistant:rwX`.
      Zonder die twee lopen we binnen een week vast op bestanden die HA
      aanmaakt en die `jgo` niet meer kan wijzigen.
- [ ] Wat nu `chmod -R 755` is verdwijnt: `.storage/core.config_entries` en
      `secrets.yaml` bevatten alle integratie-wachtwoorden in platte tekst en
      mogen **niet** leesbaar zijn voor `kiosk`.

**Let op de rolverdeling:** apparaten toevoegen en integraties instellen gebeurt
in de webinterface als HA-admin, niet in bestanden. `.storage/` nooit met de
hand bewerken. Bestandstoegang is alleen voor YAML (automatiseringen,
templates, custom components).

## 2. Kiosk — Ubuntu Desktop in plaats van `startx`

De oude aanpak (`kiosk.service` met `startx -- vt7`, openbox) botst frontaal met
GDM: die draait al en is DRM-master op de GPU. De tweede X-server komt er niet
in en de service belandt in een restart-loop.

- [ ] **GDM-autologin** voor gebruiker `kiosk` naar een eigen sessie
      (`/usr/share/wayland-sessions/`), die alleen de browser start.
- [ ] `jgo` kan via "Switch user" gewoon in een normale GNOME-sessie inloggen.
- [ ] `xserver-xorg-video-intel` **niet** installeren (deprecated, kan
      `modesetting` overrulen).
- [ ] Geen `Xwrapper.config allowed_users=anybody` meer nodig.
- [ ] `kiosk` **niet** in groep `input` — dat geeft leesrechten op alle
      `/dev/input` apparaten en is effectief een keylogger op de hele machine,
      inclusief jouw toetsaanslagen. Logind regelt apparaattoegang per seat.
- [ ] Scherm blanken uit, cursor verbergen, schermbeveiliging uit — maar nu via
      de sessie van `kiosk`, niet via een globale `xset`.
- [ ] `screen-control` herschrijven: de oude versie (`DISPLAY=:0 xset` als root)
      faalt op X-authenticatie en werkt onder Wayland sowieso niet.

## 3. Kiosk — beveiliging

Een kiosk-browser is een drempel, geen beveiligingsgrens. Drie lagen:

- [ ] **Aparte, niet-admin HA-gebruiker voor de kiosk.** Grootste winst voor de
      kleinste moeite: een niet-admin ziet Instellingen, Integraties en
      Ontwikkelhulpmiddelen niet. Zonder dit kan elke bezoeker via
      Ontwikkelhulpmiddelen → Acties elke service aanroepen.
- [ ] **Browser-policy als root-eigendom bestand** dat `kiosk` niet kan
      wijzigen: ontwikkelaarstools uit, safe mode uit, privémodus uit,
      downloads uit, printen uit, en een URL-filter die alles blokkeert behalve
      `localhost:8123` (blokkeert meteen `file:///` en `view-source:`).
- [ ] Toegang tot de datamap is dicht via de rechten uit punt 1.

## 4. Betrouwbaarheid na reboot

- [ ] **Udev-regel met een stabiele symlink** voor de Zigbee-coördinator.
      `/dev/ttyUSB0` is de zwakste schakel in de hele opstelling: de nummering
      hangt af van enumeratievolgorde. Verspringt hij, dan start Zigbee2MQTT
      niet en werkt er géén licht. Matchen op serienummer waar mogelijk,
      anders op USB-poortpad.
- [ ] **Slapen volledig uit.** Op Ubuntu Desktop is dit erger dan op Server:
      GNOME zet standaard idle-suspend aan, plus suspend bij klep dicht.
      - `HandleLidSwitch=ignore` + `HandleLidSwitchExternalPower=ignore`
      - `systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`
      - GNOME idle-suspend uit voor de `kiosk`-sessie
- [ ] **Laadlimiet op de accu** (~70%, via
      `/sys/class/power_supply/BAT0/charge_control_end_threshold`). 24/7 op 100%
      sloopt de accu binnen een jaar — en dat is onze UPS.
- [ ] Healthchecks in Compose, zodat "draait maar hangt" ook gedetecteerd wordt.
      De huidige watchdog kijkt alleen naar "not running" terwijl de
      documentatie "unhealthy" belooft.
- [ ] `depends_on` met `condition: service_healthy` voor Zigbee2MQTT → Mosquitto.

## 5. Netwerk en MQTT dichtzetten

- [ ] Mosquitto publiceren op **`127.0.0.1:1883`** in plaats van `0.0.0.0`.
      Nu kan iedereen op de wifi — inclusief gasten — naar
      `zigbee2mqtt/+/set` publiceren en alle lampen bedienen, of via
      `zigbee2mqtt/bridge/request/permit_join` zelf apparaten koppelen.
      Zigbee2MQTT praat via de Docker-bridge (`mqtt://mosquitto:1883`) en heeft
      de gepubliceerde poort niet nodig; HA zit op host-netwerk en komt via
      localhost binnen. Kost dus niets en is meteen dicht.
- [ ] Vast IP of DHCP-reservering. HA-integraties zijn IP-gevoelig.
- [ ] mDNS-hostname via Avahi.

## 6. Container-rechten terugbrengen

- [ ] `privileged: true` eruit. Vervangen door expliciet wat echt nodig is:
      - `cap_add: [NET_RAW, NET_ADMIN]` — voor `ping`, `wake_on_lan` en
        DHCP-discovery (die falen anders stil)
      - `devices:` met de stabiele Zigbee-symlink
      - `network_mode: host` blijft (nodig voor mDNS/SSDP-discovery)

## 7. Backup en versiebeheer

- [ ] Eigen `.gitignore` **in** de datamap: `.storage/`, `*.db*`, `*.log`,
      `tts/`, `deps/` uitsluiten. Wat overblijft is YAML — precies wat je wilt
      versioneren. Nu wordt `.storage/` met platte-tekst tokens en een
      voortdurend wijzigende database van honderden MB mee-gecommit en gepusht.
- [ ] `git` toevoegen aan de te installeren pakketten. Hij ontbreekt op een
      kale Ubuntu; door `set -euo pipefail` plus de `&&`-keten in de cron-regel
      zou het backup-script stil falen én `maintenance.sh` nooit draaien.
- [ ] HA's eigen (versleutelde) backup voor de volledige staat inclusief
      `.storage`. **Bestemming: eigen VPS — zie besluit B1.**

## 8. Onderhoud opruimen

- [ ] **Nachtelijke reboot om 3:30 schrappen.** Hij staat 30 minuten na een
      `apt-get upgrade` + `docker compose pull`, die makkelijk langer duren —
      dan reboot je midden in een dpkg-transactie of tijdens een schrijfactie op
      de SQLite-database. En wie om 3:31 naar de wc loopt heeft geen licht.
      Een nachtelijke reboot is symptoombestrijding; als er iets lekt zoeken we
      dat op.
- [ ] `apt-get upgrade -y` uit cron halen. Security-updates via
      `unattended-upgrades` (fijnmaziger, met logging), de rest handmatig zodat
      je erbij bent als er iets breekt.
- [ ] `claude update` hoort niet in het onderhoudsscript van de huisinstallatie.
- [ ] `recorder` purge-instelling + chatty sensoren uitsluiten, anders groeit de
      database naar meerdere GB op de laptop-SSD.
- [ ] Logrotatie voor Mosquitto (`log_dest file` groeit nu oneindig).

## 9. Opruimwerk in de repo

- [ ] `scripts/watchdog.sh` en `scripts/config-backup.sh` zijn gegenereerde
      bestanden die per ongeluk gecommit zijn, mét een hardgecodeerd
      `/home/jgo/workspace/config`. Weg, en in `.gitignore`.
- [ ] `render_template` escapet zijn waarden niet; een `&` of `|` breekt de
      `sed`-substitutie stilletjes.
- [ ] Watchdog: `--filter "name=$container"` doet substring-matching.
- [ ] Watchdog vecht met handmatig beheer: stop je iets om te debuggen, dan
      staat het binnen 5 minuten weer aan. Escape-luik inbouwen.
- [ ] `install.sh` echt idempotent maken (meerdere keren draaien mag niets stuk
      maken).
- [ ] CLAUDE.md bijwerken: `setup_nightly_reboot` staat niet in de beschrijving,
      hostname `silver` en `/dev/ttyUSB0` kloppen straks niet meer.

## 10. Functionele requirements (blijven staan)

- [ ] **Belangrijke lampen houden een fysieke fallback.** Toiletten, gangen en
      trappen krijgen een directe `genOnOff` Zigbee-bind van knop naar lamp, die
      werkt op radioniveau — zonder coördinator, MQTT of HA. Slim gedrag is een
      extra laag, nooit een afhankelijkheid. Zie `docs/light-with-fallback.md`.
- [ ] Naamgevingsconventie `{Ruimte} lamp/sensor/knop` aanhouden.
- [ ] De Bilresa/IKEA-knop join-procedure blijft relevant (zie de skill in
      `.claude/skills/`).

---

# Deel 2 — Nog te beslissen

## B1. Backup naar VPS — hoe precies?

Vastgesteld: **backuppen gaat naar de eigen VPS, niet naar GitHub.**
Open vragen:

- **Welke tool?** `restic` of `borg` (dedup, versleuteld, snapshots, retentie —
  mijn voorkeur) versus simpel `rsync` versus HA's eigen backup + `rclone`.
- **Push of pull?** Push vanaf de laptop is simpel, maar dan heeft de laptop
  schrijfrechten op de backups — een gecompromitteerde of kapotte laptop kan zijn
  eigen backups wissen. Pull vanaf de VPS, of push naar een append-only
  repository, is veiliger. Mijn voorkeur: push naar `restic` met een
  append-only key.
- **Wat gaat er heen?** Alleen de HA-backup-tarballs, of de hele datamap?
  Ook Zigbee2MQTT's `coordinator_backup.json` (cruciaal — zonder die file moet
  je bij een crash élk apparaat opnieuw koppelen) en de Mosquitto-persistence?
- **Retentie?** Bijvoorbeeld 7 dagelijks / 4 wekelijks / 6 maandelijks.
- **En de YAML-git-repo?** Blijft die op GitHub (publiek/privé?) of komt er een
  bare repo op de VPS naast de backups? Twee bestemmingen is prima, maar we
  moeten het expliciet kiezen.
- **Herstel testen.** Wanneer doen we de eerste restore-test? Een ongeteste
  backup is geen backup.
- Wat zijn de specs van de VPS (schijfruimte, waar staat hij, al iets op
  geïnstalleerd)?

## B2. Is `homeassistant` een echte beveiligingsgrens?

Met Docker draait de daemon als root en start hij de container als root. Een
gebruiker `homeassistant` aanmaken verandert daar niets aan — HA heeft dan in de
praktijk méér rechten dan `jgo`.

- **A. Accepteren** (aanbevolen): HA is vertrouwd, de echte grens is de
  `kiosk`-gebruiker. Wel `privileged: true` eruit (zie 6). Past op de bestaande
  opzet, kost niets.
- **B. Echt isoleren**: HA Core in een venv als `homeassistant`. Dan is de
  scheiding echt, maar we leveren Docker in en Zigbee2MQTT/Mosquitto moeten
  apart opgetuigd. Meer werk, meer onderhoud.

Te beslissen: A of B. Bij A leggen we expliciet vast dat de user-scheiding
cosmetisch is en dat de kiosk de enige echte grens is.

## B3. Kiosk-sessie: welke browser en welke compositor?

- **Compositor**: `cage` (minimale Wayland-kiosk, geen window manager, geen
  Alt-Tab) versus `gnome-kiosk` (Ubuntu-eigen, meer meegeleverd) versus gewoon
  GNOME met extensies (meest fragiel).
- **Browser**: Chromium heeft veel betere enterprise-policy-ondersteuning voor
  dichttimmeren, maar is op Ubuntu alleen een snap. Firefox `policies.json`
  werkt ook prima en we gebruikten al Firefox. Let op: de `mozillateam` PPA voor
  `firefox-esr` heeft voor 26.04 ("resolute") mogelijk nog geen build — met de
  GDM-route draait de snap-versie wél normaal, dus die hack is misschien niet
  meer nodig.
- **Aanraakbediening?** Is het scherm van de laptop touch, of wordt het
  bediend met de trackpad? Dat bepaalt de dashboard-opzet.
- **Dashboard-opmaak**: willen we de `kiosk-mode` HACS-module om zijbalk en
  koptekst te verbergen?

## B4. Zigbee: adapter, stack en plaatsing

- **Welke coördinator** wordt het precies? (merk/chipset — TI CC2652, Silicon
  Labs EFR32, …). Bepaalt de `adapter:`-instelling en of udev op serienummer kan
  matchen; goedkope CH340's hebben vaak geen uniek serienummer.
- **Zigbee2MQTT of ZHA?** We staan nu op Zigbee2MQTT (bredere
  apparaatondersteuning, en directe binds zijn er makkelijker). Bij ZHA vervalt
  Mosquitto — maar de fysieke-fallback-binds zijn daar bewerkelijker. Voorstel:
  Zigbee2MQTT houden.
- **Plaatsing!** De adapter moet aan een **USB-verlengkabel**, weg van de
  laptop. USB 3.0-poorten en SSD's stralen breed in de 2.4 GHz band en een
  coördinator die direct in de laptop steekt haalt een fractie van zijn bereik.
  Een betere antenne compenseert dat niet. Waar komt de laptop te staan, en is
  dat centraal genoeg in het huis?
- **Migratie**: nemen we het bestaande Zigbee-netwerk mee (netwerksleutel +
  coordinator-backup overzetten, apparaten blijven gekoppeld) of koppelen we
  alles opnieuw in het nieuwe huis? Bij een andere chipset is overzetten vaak
  niet mogelijk.
- **Kanaalkeuze** afstemmen op het wifi-kanaal in het nieuwe huis.

## B5. Toegang van buitenaf

Nog niet besproken, maar de VPS maakt dit vanzelf een vraag.

- Wil je HA van buiten het huis kunnen bereiken? (waarschijnlijk ja — telefoon,
  locatie-gebaseerde automatiseringen)
- **Hoe?** Tailscale/WireGuard (geen open poorten, veruit het veiligst),
  reverse proxy op de VPS met een tunnel, of Nabu Casa (betaald, maar steunt het
  project en regelt meteen Google/Alexa).
- Hangt samen met B1: als er toch een VPS is, kan die ook de tunnel-endpoint zijn.
- **Géén** poortforwarding naar HA vanaf het internet.

## B6. Naamgeving en inventarisatie

- **Hostname**: `silver` was de oude laptop. Wordt het `geulwijk`, of iets
  anders? Werkt door in mDNS, in de repo en in alle documentatie.
- **Welke ruimtes** krijgen de lamp/sensor/knop-opzet, en welke daarvan zijn
  "belangrijk" (= verplichte fysieke fallback)?
- **Welke bestaande apparaten** gaan mee naar het nieuwe huis, en wat komt er
  nieuw bij?

## B7. Kleinere open punten

- **Watchdog**: healthchecks toevoegen en hem slimmer maken, of helemaal
  schrappen? `restart: unless-stopped` doet al het meeste werk.
- **Recorder-retentie**: hoeveel dagen historie wil je bewaren?
- **Matter/Thread** erbij, of voorlopig alleen Zigbee?
- **Onderhoudsvenster**: als de nachtelijke reboot vervalt, wanneer draaien
  updates dan wel — en willen we een melding als er iets te updaten valt in
  plaats van automatisch?
