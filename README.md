# SMUI — Releases

Publieke **`.deb`** en **`.rpm`** packages voor **SMUI** (Storage Management UI):
een nmtui-achtige TUI voor opslagbeheer (partities, LVM PV/VG/LV, filesystems
formatteren en mounten) op **RHEL/Rocky/Alma** en **Ubuntu/Debian**.

> De broncode wordt privé beheerd. In deze repo vind je **alleen** de gebouwde packages.

## Downloads

- Nieuwste versie: **[Releases → latest](https://github.com/aalhabeeb/SMUI-releases/releases/latest)**
- Alle versies: **[Releases](https://github.com/aalhabeeb/SMUI-releases/releases)**

## Installeren op Ubuntu / Debian (.deb)

```bash
# 1. Download het pakket (vervang de versie indien nodig)
wget https://github.com/aalhabeeb/SMUI-releases/releases/download/v1.1.0/smui_1.1.0_all.deb

# 2. Installeren — apt lost automatisch de dependencies op
sudo apt install ./smui_1.1.0_all.deb

# 3. Starten
sudo smui
```

> Gebruik `sudo apt install ./bestand.deb` (mét `./`), niet `dpkg -i`. Zo worden
> de afhankelijkheden (`lvm2`, `parted`, `whiptail`, `util-linux`) automatisch
> mee-geïnstalleerd.

## Installeren op RHEL / Rocky / Alma (.rpm)

```bash
# 1. Download het pakket
wget https://github.com/aalhabeeb/SMUI-releases/releases/download/v1.1.0/smui-1.1.0-1.noarch.rpm

# 2. Installeren — dnf lost automatisch de dependencies op
sudo dnf install ./smui-1.1.0-1.noarch.rpm

# 3. Starten
sudo smui
```

## Gebruik

`smui` moet als root draaien:

```bash
sudo smui            # start de interactieve TUI
smui --help          # toon hulp
smui --version       # toon de versie
```

Via de TUI kun je:

- de opslag-layout tonen (disks, PV/VG/LV);
- een partitie aanmaken met type **8e** (Linux LVM);
- Physical Volumes, Volume Groups en Logical Volumes aanmaken en uitbreiden;
- filesystems formatteren en persistent mounten (`fstab` op UUID);
- LV/VG/PV verwijderen (met dubbele bevestiging).

Destructieve bewerkingen tonen eerst een preview en vragen bevestiging. De disk
met de root-mount (`/`) wordt gedetecteerd en beschermd.

## Download-URL structuur

Vaste versie (aanbevolen, reproduceerbaar):

```
https://github.com/aalhabeeb/SMUI-releases/releases/download/<tag>/<bestandsnaam>
```

Bijvoorbeeld: `.../download/v1.1.0/smui_1.1.0_all.deb`

## Updates

Er is (nog) geen APT/YUM-repo, dus updates komen **niet** automatisch via
`apt upgrade` / `dnf upgrade`. Download voor een nieuwe versie opnieuw het
`.deb`/`.rpm` van de nieuwste release en installeer het over de bestaande heen.

## Verwijderen

```bash
sudo apt remove smui     # Debian/Ubuntu
sudo dnf remove smui     # RHEL/Rocky/Alma
```

## Waarschuwing

Opslagbewerkingen kunnen gegevens **onherstelbaar** wissen. Controleer altijd de
getoonde disknaam en de preview vóór je bevestigt. Test bij voorkeur eerst op een
losse disk of test-VM.

## Licentie

MIT.
