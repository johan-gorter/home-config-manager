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
| Isolatie | Docker blijft. De scheiding tussen `jgo` en `homeassistant` is **cosmetisch** — zie 6. `kiosk` is de enige echte beveiligingsgrens |
| Backup | `restic` offsite, geen lokale kopie. YAML apart in een privé GitHub-repo — zie 7. Bestemming nog te bevestigen, zie B1 |
| Langetermijndata | Verbruik, warmte en temperatuur worden **eeuwig** bewaard in InfluxDB, als basis voor een MPC-regeling — zie 11 |
| Toegang van buiten | Tailscale (gratis). **Geen betaald Nabu Casa-abonnement.** Spraakbediening lokaal via Assist — zie 12 |

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

**Besloten:** Docker blijft, en we leggen expliciet vast dat de gebruiker
`homeassistant` géén echte beveiligingsgrens is. De Docker-daemon draait als
root en start de container als root; HA heeft daarmee in de praktijk méér
rechten dan `jgo`. Dat accepteren we — HA is vertrouwde software, en de grens
die er wél toe doet (bezoekers bij de kiosk) ligt bij de `kiosk`-gebruiker.
De user `homeassistant` houden we wel aan, puur voor eigenaarschap van de
bestanden en voor de rechtenopzet uit 1.

Overwogen en afgevallen: HA Core in een venv (echte scheiding, maar Docker
kwijt en veel meer onderhoud) en rootless Podman (kan geen host-networking,
waarmee mDNS/SSDP-ontdekking breekt).

Wat we wel opruimen:

- [ ] `privileged: true` eruit. Vervangen door expliciet wat echt nodig is:
      - `cap_add: [NET_RAW, NET_ADMIN]` — voor `ping`, `wake_on_lan` en
        DHCP-discovery (die falen anders stil)
      - `devices:` met de stabiele Zigbee-symlink
      - `network_mode: host` blijft (nodig voor mDNS/SSDP-discovery)
- [ ] Niemand in de groep `docker` die daar niet hoeft te zitten — lid zijn van
      `docker` is gelijk aan root. `kiosk` in elk geval niet.

## 7. Backup en versiebeheer

**Besloten:** `restic`, alleen offsite — geen lokale tweede kopie. YAML apart
in een **privé GitHub-repo**. Geen VPS (Tailscale dekt de toegang van buiten).
De bestemming is nog niet definitief: zie B1.

Volume blijft bescheiden, ook met de langetermijndata erbij: configuratie is
enkele honderden MB, en InfluxDB doet er na compressie ruwweg 1–2 GB per jaar
bij. Ook over tien jaar zijn dat tientallen GB, geen honderden.

### Wat er in de restic-backup gaat

- [ ] De HA-configuratiemap **inclusief `.storage/`** — daar zitten je
      integraties, apparaten en credentials in. Zonder die map is een restore
      geen restore.
- [ ] **`zigbee2mqtt/coordinator_backup.json`** — bevat de netwerksleutel en de
      apparaattabel. Raak je die kwijt, dan moet je na een crash élk apparaat in
      huis opnieuw koppelen én alle directe binds opnieuw leggen. Dit is het
      kostbaarste bestand van de hele opstelling.
- [ ] `zigbee2mqtt/configuration.yaml` en `database.db`
- [ ] Mosquitto-persistence
- [ ] De gerenderde `docker-compose.yml` en de rest van de datamap
- [ ] **De InfluxDB-data** (zie 11). Dit is de enige écht onvervangbare data in
      de hele opstelling: configuratie kun je opnieuw maken, twee jaar
      temperatuurhistorie niet. Daarom een afwijkende retentie: **maandelijkse
      snapshots eeuwig bewaren**, niet 6 maanden.

### Wat er niet in gaat

- [ ] `home-assistant_v2.db` — dat is korte-termijn historie voor de UI, geen
      configuratie. Honderden MB die elke seconde wijzigen en slecht
      dedupliceren. De data die je écht wilt bewaren staat in InfluxDB (zie 11),
      niet hier.
- [ ] Logs, `tts/`, `deps/`

### Opzet

- [ ] **Push vanaf de laptop** met een B2 application key **zonder
      `deleteFiles`-recht**. Anders kan een gecompromitteerde of stukke laptop
      zijn eigen backups wissen — precies op het moment dat je ze nodig hebt.
- [ ] Omdat die key niet mag verwijderen, kan `restic forget --prune` niet vanaf
      de laptop. Opruimen doen we handmatig met een tweede key, of we laten B2
      lifecycle rules het doen. Retentie: **7 dagelijks / 4 wekelijks /
      6 maandelijks**.
- [ ] Het restic-wachtwoord staat **niet alleen op deze laptop**. Zonder dat
      wachtwoord is de backup onleesbaar — dat is het punt van encryptie, maar
      ook de manier waarop mensen hun backup kwijtraken. In een wachtwoord-
      manager, en de `repository ID` erbij.
- [ ] Nachtelijk via een systemd timer (niet cron — betere logging en geen
      overlappende runs).
- [ ] Monitoring: een melding in HA als de backup langer dan 48 uur geleden
      slaagde. Een backup waarvan je niet weet of hij draait, is geen backup.
- [ ] **Consistente database-snapshot vóór de backup.** Kopieert restic een
      draaiende InfluxDB of SQLite, dan krijg je een halve transactie en dus een
      onbruikbaar bestand — en dat merk je pas bij het herstellen. Er moet een
      dump- of snapshot-stap vooraf. Met de langetermijndata erbij is dit geen
      detail meer.
- [ ] **Restore-test inplannen** zodra de eerste backup staat. Ongetest is
      ongeldig.

### Git

- [ ] Privé GitHub-repo met alléén de YAML: `configuration.yaml`,
      `automations.yaml`, `scripts.yaml`, templates, custom components.
      Privé omdat je automatiseringen verraden wanneer je niet thuis bent.
- [ ] Eigen `.gitignore` **in** de datamap: `.storage/`, `*.db*`, `*.log`,
      `tts/`, `deps/`, `secrets.yaml` uitsluiten. Nu wordt `.storage/` met
      platte-tekst tokens en een database van honderden MB mee-gecommit en
      gepusht.
- [ ] Deze repo (`home-config-manager`, publiek) blijft voor de scripts; de
      configuratie komt in een aparte repo.
- [ ] `git` toevoegen aan de te installeren pakketten. Hij ontbreekt op een kale
      Ubuntu; door `set -euo pipefail` plus de `&&`-keten in de cron-regel zou
      het backup-script stil falen én `maintenance.sh` nooit draaien.

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

## 11. Langetermijndata voor Model Predictive Control

Doel: verbruik (stroom, gas), warmte en temperaturen **jarenlang** bewaren om er
later een MPC-regeling op te bouwen.

- [ ] **InfluxDB als aparte container**, waar HA naartoe schrijft. De
      HA-recorder is hier het verkeerde gereedschap: die is gebouwd voor korte
      historie (standaard 10 dagen) en SQLite op een laptop-SSD is geen
      tijdreeksdatabase. HA's eigen long-term statistics blijven wel eeuwig
      bewaard, maar zijn uurgemiddelden — te grof voor een thermisch model.
- [ ] Recorder blijft kort (UI-historie), InfluxDB bewaart alles.
- [ ] Resolutie: 1–5 minuten voor temperaturen, vermogen en setpoints.
- [ ] **P1-lezer op de slimme meter.** Voor een Nederlands huis veruit de beste
      bron voor stroom en gas — echte meterstanden op hoge frequentie, veel
      beter dan losse klemmen of slimme stekkers.

### Dit moet vanaf dag één draaien

**Dringender dan de rest van deze roadmap.** Je kunt data niet met
terugwerkende kracht verzamelen, en voor een thermisch model heb je een volledig
stookseizoen nodig — dat is een jaar kalendertijd. Elke maand uitstel is een
maand trainingsdata die je nooit meer krijgt. Loggen begint zodra de server
staat, ruim voordat er aan MPC gewerkt wordt.

Twee dingen die een dataset achteraf waardeloos maken:

- [ ] **Log ook de ingangen, niet alleen de uitkomsten**: setpoints, ketel- en
      klepstanden, ramen/deuren open, aanwezigheid. Een model dat alleen
      binnentemperatuur ziet kan niets causaals leren.
- [ ] **Buitentemperatuur én zoninstraling binnenhalen** (weer-integratie of
      KNMI). Dat zijn de dominante verstoringen in elk gebouwmodel; zonder die
      twee is voorspellen onmogelijk.
- [ ] Alles in UTC wegschrijven — zomertijd maakt anders twee uur per jaar
      onbruikbaar.

## 12. Toegang van buitenaf

**Besloten: Tailscale, gratis. Geen betaald Nabu Casa-abonnement.**
Geen poortforwarding, HA komt nergens aan het open internet.

- [ ] Tailscale op de host installeren (niet in de container; HA draait toch op
      host-netwerk).
- [ ] **Key expiry uitzetten voor de server-node.** Node-keys verlopen standaard
      na een half jaar. Op een machine waar je nooit naar kijkt betekent dat:
      over zes maanden werkt toegang van buiten ineens niet meer, zonder
      waarschuwing en zonder duidelijke oorzaak. Dag één regelen.
- [ ] Echt HTTPS-certificaat via `tailscale cert` / `tailscale serve` — de
      companion-app werkt daar veel beter mee dan met een kaal IP-adres.
- [ ] Bij gebruik van `tailscale serve`: `use_x_forwarded_for` en
      `trusted_proxies` in HA zetten. Zonder dat ziet HA elke login vanaf
      hetzelfde adres en werkt de brute-force-bescherming niet meer.
- [ ] `external_url` op de Tailscale-naam zetten.
- [ ] **Subnet routing** aanzetten, dan kun je onderweg ook bij Zigbee2MQTT
      (8080), de router en de rest van het thuisnetwerk.

### Wat we daarmee bewust niet hebben

- **Google Assistant / Alexa** vragen een publiek eindpunt en vallen dus af.
  In plaats daarvan: **HA Assist, volledig lokaal**, met een ESP32-satelliet of
  HA's eigen Voice-hardware. Geen abonnement, geen cloud. Zie B4.
- **Inkomende webhooks** kunnen niet door een dichte tunnel. Mocht dat ooit
  nodig zijn: **Tailscale Funnel** (ook gratis), maar dan alléén voor dat ene
  webhook-pad — niet voor heel HA, want dan geef je de afscherming weg waar je
  Tailscale juist voor koos.

# Deel 2 — Nog te beslissen

> Besloten en verhuisd naar Deel 1: de backupopzet (restic, offsite, YAML in
> privé GitHub-repo — zie 7), de isolatievraag (Docker blijft, `homeassistant`
> is geen echte grens — zie 6), de langetermijndata (InfluxDB — zie 11) en de
> toegang van buitenaf (Tailscale, geen Nabu Casa — zie 12).

## B1. Backup-bestemming: waar precies?

De opzet ligt vast (restic, offsite, delete-loze key), de bestemming nog niet.
Prijzen gecheckt op 2026-09-20, even opnieuw verifiëren voor je bestelt.

- **Hetzner Storage Box BX11** — €3,20/mnd excl. btw (~€3,87 incl.), 1 TB, geen
  setup fee, EU. *Mijn voorkeur.* Niet de goedkoopste, maar een vaste factuur in
  euro's zonder gratis-tier-grenzen die kunnen wijzigen, 1 TB kopruimte, en
  ingebouwde snapshots als tweede verdedigingslinie naast restic. Beheerde
  dienst: geen OS om te patchen, en een aangekondigd onderhoudsvenster kost
  hooguit één overgeslagen nachtelijke run.
- **Cloudflare R2** — 10 GB gratis, daarna ~$0,015/GB/mnd, geen egress-kosten.
  Op ons volume een paar euro per jaar. Goedkoper, maar afhankelijk van een
  gratis tier.
- **Backblaze B2** — $6,95/TB/mnd. Onduidelijk of er een bodem van $6,95/mnd
  geldt; dat kon ik niet bevestigd krijgen (bot-controle op hun site). Zo ja,
  dan is dit juist de duurste optie en valt hij af.

Het omslagpunt waarop Hetzner puur op prijs wint ligt rond 600 GB; daar zitten
we ver onder. De keuze gaat dus niet over ruimte maar over gedoe.

Randvoorwaarde bij elke optie: het backup-script moet een onbereikbare
bestemming netjes overleven, en de "backup is te oud"-melding gaat pas na 48 uur
af — niet na één gemiste run, anders leer je jezelf waarschuwingen negeren.

## B2. Kiosk-sessie: welke browser en welke compositor?

- **Compositor**: `cage` (minimale Wayland-kiosk, geen window manager, geen
  Alt-Tab) versus `gnome-kiosk` (Ubuntu-eigen, meer meegeleverd) versus gewoon
  GNOME met extensies (meest fragiel).
- **Browser**: Chromium heeft veel betere enterprise-policy-ondersteuning voor
  dichttimmeren, maar is op Ubuntu alleen een snap. Firefox `policies.json`
  werkt ook prima en we gebruikten al Firefox. Let op: de `mozillateam` PPA voor
  `firefox-esr` heeft voor 26.04 ("resolute") mogelijk nog geen build — met de
  GDM-route draait de snap-versie wél normaal, dus die hack is misschien niet
  meer nodig.
- **Aanraakbediening?** Is het scherm van de laptop touch, of wordt het bediend
  met de trackpad? Dat bepaalt de dashboard-opzet.
- **Dashboard-opmaak**: willen we de `kiosk-mode` HACS-module om zijbalk en
  koptekst te verbergen?

## B3. Zigbee: adapter, stack en plaatsing

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

## B4. Naamgeving en inventarisatie

- **Hostname**: `silver` was de oude laptop. Wordt het `geulwijk`, of iets
  anders? Werkt door in mDNS, in de repo en in alle documentatie.
- **Welke ruimtes** krijgen de lamp/sensor/knop-opzet, en welke daarvan zijn
  "belangrijk" (= verplichte fysieke fallback)?
- **Welke bestaande apparaten** gaan mee naar het nieuwe huis, en wat komt er
  nieuw bij?

## B5. Kleinere open punten

- **Spraakbediening**: willen we lokale Assist met een wake word, en zo ja op
  welke hardware (ESP32-satellieten of HA Voice PE)? En in welke ruimtes?

- **Watchdog**: healthchecks toevoegen en hem slimmer maken, of helemaal
  schrappen? `restart: unless-stopped` doet al het meeste werk.
- **Recorder-retentie**: hoeveel dagen historie wil je bewaren? (Staat los van
  de backup — de database gaat daar niet in mee.)
- **Matter/Thread** erbij, of voorlopig alleen Zigbee?
- **Onderhoudsvenster**: als de nachtelijke reboot vervalt, wanneer draaien
  updates dan wel — en willen we een melding als er iets te updaten valt in
  plaats van automatisch?
- **Restic prune**: handmatig met een tweede B2-key, of via B2 lifecycle rules?
  Uit te zoeken bij het bouwen.
