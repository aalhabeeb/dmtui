# dmtui — Disk Management TUI

Een **nmtui-achtige TUI voor opslagbeheer** op Linux. Werkt op zowel
**RHEL/Rocky/AlmaLinux** (dnf/yum) als **Ubuntu/Debian** (apt).

In plaats van losse commando's als `parted`, `pvcreate`, `vgcreate`, `lvcreate`
en `mkfs` uit je hoofd te typen, biedt dmtui een menugestuurde interface
(gebaseerd op `dialog`, met **muisondersteuning** en een kleurthema) met
bevestigingen en een preview van elk commando
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
| `dialog`   | `dialog`      | `dialog`             |
| `lvs`/lvm  | `lvm2`        | `lvm2`               |
| `parted`   | `parted`      | `parted`             |
| `lsblk`/`blkid` | `util-linux` | `util-linux`    |

### Optioneel: `fzf` (aanrader)

Als **`fzf`** geïnstalleerd is, gebruikt dmtui dat voor de disk-/VG-/LV-lijsten:
**typen om te filteren**, muis-klik en scrollen. Ontbreekt `fzf`, dan valt dmtui
automatisch terug op het gewone `dialog`-menu.

```bash
sudo apt install fzf        # Debian/Ubuntu
sudo dnf install fzf        # RHEL/Rocky/Alma (via EPEL)
```

Het `.deb`-pakket adviseert `fzf` automatisch (Recommends). Wil je `fzf` tijdelijk
uitschakelen: start met `DMTUI_NO_FZF=1 sudo dmtui`.

## Gebruik

```bash
git clone https://github.com/aalhabeeb/SMUI.git dmtui
cd dmtui
chmod +x dmtui.sh
sudo ./dmtui.sh
```

Of in één keer draaien vanuit de checkout:

```bash
sudo bash dmtui.sh
```

## Installeren als pakket (.deb / .rpm)

dmtui kan als los pakket geïnstalleerd worden. De packages worden gebouwd met
[nfpm](https://nfpm.goreleaser.com) — één config levert zowel `.deb` als `.rpm`.

Bouwen (op een Linux-host):

```bash
./packaging/build.sh          # bouwt beide in ./dist
./packaging/build.sh deb      # alleen .deb
./packaging/build.sh rpm      # alleen .rpm
```

Staat `nfpm` niet in `PATH`, dan downloadt het script automatisch een gepinde
versie naar `./bin`. Resultaat in `./dist/` (waarbij `<versie>` = `DMTUI_VERSION`
uit `dmtui.sh`):

```text
dist/dmtui_<versie>_all.deb
dist/dmtui-<versie>-1.noarch.rpm
```

Installeren (de glob pakt automatisch de nieuwste gebouwde versie):

```bash
# Debian/Ubuntu
sudo apt install ./dist/dmtui_*_all.deb

# RHEL/Rocky/Alma
sudo dnf install ./dist/dmtui-*.noarch.rpm
```

Het pakket installeert `dmtui` naar `/usr/bin/dmtui`, een manpage naar
`man 1 dmtui`, en declareert de runtime-afhankelijkheden (`lvm2`, `parted`,
`util-linux`, en `dialog`). Daarna starten met:

```bash
sudo dmtui
```

## Releases (CI/CD)

De workflow [.github/workflows/release.yml](.github/workflows/release.yml) bouwt
de packages automatisch met GitHub Actions:

- **Push naar `main` / pull request** → lint (`shellcheck`) + testbuild.
- **Push van een tag `v*`** → build **en** publiceert een Release met de
  `.deb` en `.rpm` in de **publieke releases-repo** (broncode blijft privé).
  De tag moet overeenkomen met `DMTUI_VERSION` in `dmtui.sh` (anders faalt de build).
- **Handmatige run** (workflow_dispatch) → build + upload als artefact.

Een release maken (vervang `X.Y.Z` door het nieuwe versienummer):

```bash
# 1. Bump de versie in dmtui.sh (DMTUI_VERSION="X.Y.Z")
# 2. Commit en tag
git commit -am "release: vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

### Publieke packages, privé broncode

De workflow publiceert de packages naar een aparte **publieke** repo
(`aalhabeeb/dmtui-releases`), terwijl deze broncode-repo **privé** blijft. Zo kan
iedereen de `.deb`/`.rpm` downloaden zonder de code te zien.

Eenmalige setup:

1. Maak een **publieke** repo aan: `aalhabeeb/dmtui-releases` (leeg is prima).
2. Maak een **Personal Access Token** met schrijfrechten op die repo:
   - *Fine-grained token* → repository `dmtui-releases` → permission
     **Contents: Read and write**.
3. Voeg het token toe als **secret** in de privé-repo `SMUI`:
   - Settings → Secrets and variables → Actions → New repository secret →
     naam **`RELEASES_TOKEN`**.

Wil je een andere doel-repo? Pas `repository:` in
[.github/workflows/release.yml](.github/workflows/release.yml) aan.

Downloaden (openbaar, geen auth nodig):

```bash
# Nieuwste release-assets
https://github.com/aalhabeeb/dmtui-releases/releases/latest
```

## Licentie & wijzigingen

- Licentie: [MIT](LICENSE)
- Wijzigingen per versie: [CHANGELOG.md](CHANGELOG.md)


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
