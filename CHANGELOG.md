# Changelog

Alle noemenswaardige wijzigingen aan SMUI worden in dit bestand bijgehouden.

Het formaat is gebaseerd op [Keep a Changelog](https://keepachangelog.com/nl/1.1.0/)
en dit project volgt [Semantic Versioning](https://semver.org/lang/nl/).

## [Unreleased]

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

[Unreleased]: https://github.com/amjed/SMUI/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/amjed/SMUI/releases/tag/v1.0.0
