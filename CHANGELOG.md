# Changelog

Alle noemenswaardige wijzigingen aan SMUI worden in dit bestand bijgehouden.

Het formaat is gebaseerd op [Keep a Changelog](https://keepachangelog.com/nl/1.1.0/)
en dit project volgt [Semantic Versioning](https://semver.org/lang/nl/).

## [Unreleased]

## [1.3.0] - 2026-07-12

### Gewijzigd
- **Modernere UI:** overgestapt van `whiptail` naar `dialog`. Dit geeft
  **muisondersteuning** (klikken op keuzes en knoppen), een **kleurthema** met een
  vaste kopbalk (backtitle), en Nederlandse knoplabels (Ja/Nee/Kies/Annuleren).
  Toetsenbordbediening (pijltjes/Tab) blijft gewoon werken.
- Runtime-dependency is nu `dialog` (in plaats van `whiptail`/`newt`); zit in de
  standaard apt- én dnf-repos.

## [1.2.0] - 2026-07-12

### Toegevoegd
- De wizard vraagt nu wat je met de disk wilt doen:
  - **Nieuwe opslag** aanmaken (nieuwe VG + LV + mount), zoals voorheen; of
  - **Toevoegen aan een bestaande Volume Group**: partitie (type 8e) -> `pvcreate`
    -> `vgextend`, en optioneel meteen een bestaand Logical Volume vergroten
    (`lvextend -l +100%FREE -r`, filesystem groeit mee).

## [1.1.3] - 2026-07-12

### Opgelost
- **Echte oorzaak** dat het menu direct afsloot: een menu-item begon met `---`,
  waardoor whiptail dat als een optie las en het hele menu faalde (de fout was
  onzichtbaar door de fd-omleiding). Alle leidende streepjes/decoraties uit de
  menu-items verwijderd.
- Het menu toont nu een duidelijke melding als whiptail toch faalt, in plaats van
  stil af te sluiten.

## [1.1.2] - 2026-07-12

### Opgelost
- Menu bleef direct afsluiten met "SMUI afgesloten." doordat de menu-lijsthoogte
  te groot was voor de dialoogbox (whiptail heeft ruimte nodig voor titel, tekst,
  knoppen en randen). De lijsthoogte is nu conservatiever (`DLG_H - 12`) en de
  hoofdmenu-prompt is ingekort tot één regel.
- `SMUI_DEBUG=1 smui` toont nu de berekende terminal- en boxafmetingen (voor
  diagnose).

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

[Unreleased]: https://github.com/aalhabeeb/SMUI/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.3.0
[1.2.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.2.0
[1.1.3]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.3
[1.1.2]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.2
[1.1.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.1
[1.1.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.0
[1.0.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.0.1
[1.0.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.0.0
