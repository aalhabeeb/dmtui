# SMUI — Storage Management UI

Een **nmtui-achtige TUI voor opslagbeheer** op Linux. Werkt op zowel
**RHEL/Rocky/AlmaLinux** (dnf/yum) als **Ubuntu/Debian** (apt).

In plaats van losse commando's als `parted`, `pvcreate`, `vgcreate`, `lvcreate`
en `mkfs` uit je hoofd te typen, biedt SMUI een menugestuurde interface
(gebaseerd op `whiptail`) met bevestigingen en een preview van elk commando
voordat het wordt uitgevoerd.

## Functies

- **Layout tonen** — overzicht van disks, partities, PV's, VG's en LV's.
- **Partitie aanmaken** met type **8e / Linux LVM** (via de LVM-vlag in `parted`).
- **Physical Volume** aanmaken (`pvcreate`).
- **Volume Group** aanmaken (`vgcreate`).
- **Logical Volume** aanmaken (`lvcreate`).
- **VG uitbreiden** met een extra disk/partitie (`vgextend`, incl. automatische `pvcreate`).
- **LV uitbreiden** (`lvextend`), optioneel met filesystem meegroeien (`-r`).
- **Formatteren + mounten** — `mkfs` (ext4/xfs/btrfs) + persistente `fstab`-entry op UUID.
- **Verwijderen** van LV / VG / PV met dubbele bevestiging.

## Veiligheid

- Draait alleen als **root** (`sudo`).
- **Systeemdisk-bescherming**: de disk die de root-mount (`/`) bevat wordt
  gedetecteerd en geweigerd voor destructieve bewerkingen.
- **Preview + bevestiging**: elk destructief commando wordt eerst getoond en
  vereist expliciete bevestiging (standaard staat de keuze op *nee*).
- Toont de uitvoer/fouten van elk commando na afloop.

> [!warning]
> Opslagbewerkingen kunnen gegevens **onherstelbaar** wissen. Controleer altijd
> de getoonde disknaam en de preview voordat je bevestigt. Maak back-ups.

## Vereisten

De volgende pakketten worden automatisch geïnstalleerd als ze ontbreken:

| Commando   | RHEL-pakket   | Debian/Ubuntu-pakket |
|------------|---------------|----------------------|
| `whiptail` | `newt`        | `whiptail`           |
| `lvs`/lvm  | `lvm2`        | `lvm2`               |
| `parted`   | `parted`      | `parted`             |
| `lsblk`/`blkid` | `util-linux` | `util-linux`    |

## Gebruik

```bash
git clone <deze-repo> smui
cd smui
chmod +x smui.sh
sudo ./smui.sh
```

Of in één keer draaien vanuit de checkout:

```bash
sudo bash smui.sh
```

## Installeren als pakket (.deb / .rpm)

SMUI kan als los pakket geïnstalleerd worden. De packages worden gebouwd met
[nfpm](https://nfpm.goreleaser.com) — één config levert zowel `.deb` als `.rpm`.

Bouwen (op een Linux-host):

```bash
./packaging/build.sh          # bouwt beide in ./dist
./packaging/build.sh deb      # alleen .deb
./packaging/build.sh rpm      # alleen .rpm
```

Staat `nfpm` niet in `PATH`, dan downloadt het script automatisch een gepinde
versie naar `./bin`. Resultaat in `./dist/`:

```text
dist/smui_1.0.0_all.deb
dist/smui-1.0.0-1.noarch.rpm
```

Installeren:

```bash
# Debian/Ubuntu
sudo apt install ./dist/smui_1.0.0_all.deb

# RHEL/Rocky/Alma
sudo dnf install ./dist/smui-1.0.0-1.noarch.rpm
```

Het pakket installeert `smui` naar `/usr/bin/smui`, een manpage naar
`man 1 smui`, en declareert de runtime-afhankelijkheden (`lvm2`, `parted`,
`util-linux`, en `whiptail`/`newt`). Daarna starten met:

```bash
sudo smui
```

## Typische workflow — nieuwe extra disk toevoegen

1. **Layout tonen** → controleer de naam van de nieuwe disk (bijv. `/dev/sdb`).
2. **Partitie aanmaken (type 8e)** → kies `/dev/sdb`, GPT, grootte `100%`.
3. **Physical Volume aanmaken** → kies `/dev/sdb1`.
4. **Volume Group aanmaken** → kies het PV, naam bijv. `vg_data`.
5. **Logical Volume aanmaken** → kies `vg_data`, naam `lv_data`, grootte `100%FREE`.
6. **Formatteren + mounten** → kies `/dev/vg_data/lv_data`, `ext4`/`xfs`, mount `/mnt/data`.

Later uitbreiden met een tweede disk:

1. **Partitie aanmaken (8e)** op de nieuwe disk → **VG uitbreiden** (`vgextend`).
2. **LV uitbreiden** met `+100%FREE` en filesystem laten meegroeien.

## Beperkingen

- Richt zich op LVM + standaard filesystems; geen RAID/ZFS-beheer.
- Geen ondersteuning voor versleutelde volumes (LUKS) in deze versie.
- Bij een nieuw partitielabel (GPT/MBR) wordt de héle disk gewist.
