# Changelog

Alle noemenswaardige wijzigingen aan SMUI worden in dit bestand bijgehouden.

Het formaat is gebaseerd op [Keep a Changelog](https://keepachangelog.com/nl/1.1.0/)
en dit project volgt [Semantic Versioning](https://semver.org/lang/nl/).

## [Unreleased]

## [1.1.1] - 2026-07-12

### Opgelost
- SMUI sloot direct af met "SMUI afgesloten." op een standaard 80x24-terminal
  doordat het hoofdmenu te groot was. Dialooggroottes passen zich nu aan de
  werkelijke terminalgrootte aan (met veilige maxima), zodat vensters nooit groter
  zijn dan de terminal.

## [1.1.0] - 2026-07-12

### Toegevoegd
- Begeleide **wizard "Nieuwe disk in gebruik nemen"** als eerste menu-optie: neemt
  een lege disk in een keer volledig in gebruik (partitie 8e -> PV -> VG -> LV ->
  filesystem -> mounten) met slimme standaardwaarden en een duidelijke samenvatting
  vooraf.

### Gewijzigd
- Disk-overzicht toont nu per disk een **statuslabel** (`LEEG - nieuw`,
  `in gebruik: N partitie(s)`, `SYSTEEMDISK`), zodat direct zichtbaar is welke disk
  nieuw en veilig te kiezen is.
- Hoofdmenu opgesplitst in een begeleide optie en gemarkeerde geavanceerde opties.

## [1.0.1] - 2026-07-12

### Gewijzigd
- Release-workflow publiceert de packages nu naar de publieke repo
  `aalhabeeb/SMUI-releases` (broncode blijft privé).

## [1.0.0] - 2026-07-12

### Toegevoegd
- Interactieve `whiptail`-TUI (`smui.sh`) voor opslagbeheer op RHEL/Rocky/Alma
  en Ubuntu/Debian.
- Layout tonen: disks, partities, PV's, VG's en LV's.
- Partitie aanmaken met type **8e** / Linux LVM (via `parted` LVM-vlag, GPT of MBR).
- LVM-beheer: Physical Volume (`pvcreate`), Volume Group (`vgcreate`),
  Logical Volume (`lvcreate`).
- VG uitbreiden (`vgextend`, met automatische `pvcreate`) en LV uitbreiden
  (`lvextend -r`, filesystem groeit mee).
- Formatteren + mounten (ext4/xfs/btrfs) met persistente `fstab`-entry op UUID.
- Verwijderen van LV / VG / PV met dubbele bevestiging.
- Systeemdisk-bescherming: de disk met de root-mount wordt geweigerd voor
  destructieve bewerkingen.
- Preview + bevestiging vóór elk destructief commando.
- Automatische distro-detectie en dependency-installatie.
- `--help` en `--version` opties.
- Packaging met nfpm: `.deb` en `.rpm` uit één config (`packaging/nfpm.yaml`),
  build-script (`packaging/build.sh`) en manpage (`packaging/smui.1`).
- GitHub Actions-workflow voor lint, build en release
  (`.github/workflows/release.yml`).

[Unreleased]: https://github.com/aalhabeeb/SMUI/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.1
[1.1.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.0
[1.0.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.0.1
[1.0.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.0.0
