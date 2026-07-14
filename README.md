# dmtui — Disk Management TUI

[![Nieuwste release](https://img.shields.io/github/v/release/aalhabeeb/dmtui?label=nieuwste%20versie&color=2ea043&sort=semver)](https://github.com/aalhabeeb/dmtui/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/aalhabeeb/dmtui/total?label=downloads&color=1f6feb)](https://github.com/aalhabeeb/dmtui/releases)
[![Licentie: MIT](https://img.shields.io/badge/licentie-MIT-blue)](https://github.com/aalhabeeb/dmtui/blob/main/LICENSE)

**dmtui** is een terminalgebaseerde beheertool voor opslag op Linux. Het biedt een
overzichtelijke interface voor het partitioneren van schijven, het beheren van LVM
(Physical Volumes, Volume Groups en Logical Volumes), en het formatteren en mounten
van bestandssystemen — met een preview en bevestiging van elke bewerking.

Ondersteunde platformen: **RHEL, Rocky Linux, AlmaLinux** en **Ubuntu / Debian**.

> Deze repository bevat de publieke **`.deb`**- en **`.rpm`**-packages.
> De broncode wordt privé beheerd.

## Schermafbeeldingen

### Hoofdmenu
![dmtui — hoofdmenu](docs/menu.png)

### Wizard — nieuwe schijf in gebruik nemen
![dmtui — wizard](docs/wizard.png)

### Opslag-layout
![dmtui — layout](docs/layout.png)

## Functionaliteit

- Schijven partitioneren met partitietype **8e (Linux LVM)**.
- Volledig LVM-beheer: Physical Volumes, Volume Groups en Logical Volumes aanmaken
  en uitbreiden.
- Begeleide wizard om een nieuwe schijf in gebruik te nemen: nieuwe opslag aanmaken
  óf toevoegen aan een bestaande Volume Group.
- Bestandssystemen formatteren (ext4/xfs/btrfs) en persistent mounten via `fstab`
  op UUID.
- Overzicht van de actuele opslag-layout (schijven, PV's, VG's, LV's).
- Bediening met **toetsenbord en muis**; met `fzf` filterbare lijsten (dubbelklik
  om te kiezen).

## Installatie

### Ubuntu / Debian (.deb)

```bash
url=$(curl -s https://api.github.com/repos/aalhabeeb/dmtui/releases/latest \
  | grep -o 'https://[^"]*_all\.deb')
curl -L -o dmtui.deb "$url"
sudo apt install ./dmtui.deb
```

### RHEL / Rocky / Alma (.rpm)

```bash
url=$(curl -s https://api.github.com/repos/aalhabeeb/dmtui/releases/latest \
  | grep -o 'https://[^"]*\.noarch\.rpm')
curl -L -o dmtui.rpm "$url"
sudo dnf install ./dmtui.rpm
```

De packages installeren automatisch de vereiste afhankelijkheden (`dialog`, `lvm2`,
`parted`, `util-linux`). Het optionele `fzf` (filterbare lijsten) wordt op
Debian/Ubuntu aanbevolen; op RHEL is het beschikbaar via EPEL.

Handmatig installeren kan ook: download het gewenste bestand van de
[nieuwste release](https://github.com/aalhabeeb/dmtui/releases/latest) en gebruik
`sudo apt install ./dmtui_*_all.deb` of `sudo dnf install ./dmtui-*.noarch.rpm`.

## Gebruik

dmtui vereist rootrechten:

```bash
sudo dmtui           # interactieve interface
dmtui --help         # help
dmtui --version      # versie
```

Elke destructieve bewerking toont vooraf een overzicht en vraagt om bevestiging.
De schijf met de root-mount (`/`) wordt automatisch gedetecteerd en beschermd.

## Updates

Er is nog geen APT/YUM-repository; updates worden dus niet automatisch via
`apt upgrade` / `dnf upgrade` opgehaald. Haal een nieuwe versie op via de
bovenstaande stappen en installeer deze over de bestaande installatie heen.

## Verwijderen

```bash
sudo apt remove dmtui    # Debian / Ubuntu
sudo dnf remove dmtui    # RHEL / Rocky / Alma
```

## Waarschuwing

Opslagbewerkingen kunnen gegevens onherstelbaar wissen. Controleer altijd de
getoonde schijfnaam en het overzicht vóór bevestiging, en test bij voorkeur eerst
op een losse schijf of een test-VM.

## Licentie

Uitgebracht onder de [MIT-licentie](LICENSE).
