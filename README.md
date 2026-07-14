# dmtui — Disk Management TUI (releases)

[![Nieuwste release](https://img.shields.io/github/v/release/aalhabeeb/SMUI-releases?label=nieuwste%20versie&color=2ea043&sort=semver)](https://github.com/aalhabeeb/SMUI-releases/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/aalhabeeb/SMUI-releases/total?label=downloads&color=1f6feb)](https://github.com/aalhabeeb/SMUI-releases/releases)
[![Licentie: MIT](https://img.shields.io/badge/licentie-MIT-blue)](https://github.com/aalhabeeb/SMUI-releases/blob/main/LICENSE)

Publieke **`.deb`** en **`.rpm`** packages voor **dmtui** (Disk Management TUI):
een nmtui-achtige TUI voor opslagbeheer (partities, LVM PV/VG/LV, filesystems
formatteren en mounten) op **RHEL/Rocky/Alma** en **Ubuntu/Debian**.

> De broncode wordt privé beheerd. In deze repo vind je **alleen** de gebouwde packages.

## Downloads

- Nieuwste versie: **[Releases → latest](https://github.com/aalhabeeb/SMUI-releases/releases/latest)**
- Alle versies: **[Releases](https://github.com/aalhabeeb/SMUI-releases/releases)**

## Installeren op Ubuntu / Debian (.deb)

Automatisch de nieuwste versie ophalen en installeren:

```bash
url=$(curl -s https://api.github.com/repos/aalhabeeb/SMUI-releases/releases/latest \
  | grep -o 'https://[^"]*_all\.deb')
curl -L -o dmtui.deb "$url"
sudo apt install ./dmtui.deb
sudo dmtui
```

Of handmatig: download de `dmtui_*_all.deb` van de
[nieuwste release](https://github.com/aalhabeeb/SMUI-releases/releases/latest) en:

```bash
sudo apt install ./dmtui_*_all.deb
```

> Gebruik `sudo apt install ./bestand.deb` (mét `./`), niet `dpkg -i`. Zo worden
> de afhankelijkheden (`dialog`, `lvm2`, `parted`, `util-linux`, en het optionele
> `fzf`) automatisch mee-geïnstalleerd.

## Installeren op RHEL / Rocky / Alma (.rpm)

Automatisch de nieuwste versie ophalen en installeren:

```bash
url=$(curl -s https://api.github.com/repos/aalhabeeb/SMUI-releases/releases/latest \
  | grep -o 'https://[^"]*\.noarch\.rpm')
curl -L -o dmtui.rpm "$url"
sudo dnf install ./dmtui.rpm
sudo dmtui
```

Of handmatig: download de `dmtui-*.noarch.rpm` van de
[nieuwste release](https://github.com/aalhabeeb/SMUI-releases/releases/latest) en:

```bash
sudo dnf install ./dmtui-*.noarch.rpm
```

> `fzf` (optioneel, voor filterbare lijsten met muis) zit op RHEL in **EPEL**.
> Zonder `fzf` werkt dmtui gewoon met het `dialog`-menu.

## Gebruik

`dmtui` moet als root draaien:

```bash
sudo dmtui           # start de interactieve TUI
dmtui --help         # toon hulp
dmtui --version      # toon de versie
```

Via de TUI kun je:

- de opslag-layout tonen (disks, PV/VG/LV);
- via de **wizard** een disk in gebruik nemen: nieuwe opslag óf toevoegen aan een
  bestaande Volume Group (partitie type **8e** → PV → VG/LV);
- Physical Volumes, Volume Groups en Logical Volumes aanmaken en uitbreiden;
- filesystems formatteren en persistent mounten (`fstab` op UUID);
- LV/VG/PV verwijderen (met dubbele bevestiging).

De interface werkt met **toetsenbord én muis** (met `fzf`: dubbelklik = kiezen,
typen = filteren). Destructieve bewerkingen tonen eerst een preview en vragen
bevestiging. De disk met de root-mount (`/`) wordt gedetecteerd en beschermd.

## Schermafbeelding

<!-- Voeg hier een screenshot of GIF toe. Sleep in de GitHub-webeditor een
     afbeelding in dit bestand; GitHub maakt er automatisch een URL van, of
     commit een bestand (bijv. docs/dmtui.png) en verwijs ernaar:
     ![dmtui](docs/dmtui.png) -->

_Nog toe te voegen._

## Updates

Er is (nog) geen APT/YUM-repo, dus updates komen **niet** automatisch via
`apt upgrade` / `dnf upgrade`. Haal voor een nieuwe versie opnieuw het nieuwste
`.deb`/`.rpm` op (zie hierboven) en installeer het over de bestaande heen.

## Verwijderen

```bash
sudo apt remove dmtui    # Debian/Ubuntu
sudo dnf remove dmtui    # RHEL/Rocky/Alma
```

> Kwam je van de oude naam? Verwijder die met `sudo apt remove smui` /
> `sudo dnf remove smui`.

## Waarschuwing

Opslagbewerkingen kunnen gegevens **onherstelbaar** wissen. Controleer altijd de
getoonde disknaam en de preview vóór je bevestigt. Test bij voorkeur eerst op een
losse disk of test-VM.

## Licentie

MIT — zie [LICENSE](LICENSE).
