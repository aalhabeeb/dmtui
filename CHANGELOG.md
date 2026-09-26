# Changelog

Alle noemenswaardige wijzigingen aan dmtui worden in dit bestand bijgehouden.

Het formaat is gebaseerd op [Keep a Changelog](https://keepachangelog.com/nl/1.1.0/)
en dit project volgt [Semantic Versioning](https://semver.org/lang/nl/).

## [Unreleased]

Versie in `dmtui.sh` staat op **2.1.0**.

### Toegevoegd
- **k8s-modus (`DMTUI_MODE=k8s`)** om dmtui als privileged pod op een
  Kubernetes-node te draaien, met name **Talos** (geen shell, geen package manager).
  De modus is gericht op **TopoLVM**: alleen PV + VG (hele disk, geen partitie),
  geen LV's, filesystems of fstab. Hij schakelt automatisch in binnen een pod
  (`DMTUI_MODE=auto`).
- **Container-image** `ghcr.io/aalhabeeb/dmtui` (Debian 13-slim) met een
  LVM-config voor containers (geen udev/dmeventd/devices-file). CI pusht `:edge`
  vanaf `main` en `:X.Y.Z`, `:X.Y` en `:latest` bij een tag.
- **`k8s/dmtui-pod.yaml`** als alternatief voor `kubectl debug node`.
- **Nieuwe actie: "Disk vergroot? PV laten meegroeien"** (host: menu `g`, k8s:
  optie 3). Laat de kernel de disk opnieuw inlezen, vergroot de partitie met
  `growpart` (als het PV op een partitie staat) en draait `pvresize`. Op een host
  wordt `growpart` (`cloud-guest-utils` / `cloud-utils-growpart`) aangeboden als
  het ontbreekt.
- **TopoLVM-config tonen**: de Helm-values (`lvmd.deviceClasses`) voor een VG.

### Gewijzigd
- **Bescherming van disks** werkt nu met een lijst in plaats van alleen de
  root-disk en kijkt naar de onderliggende disk(s) van een apparaat. Voorheen was het een
  prefix-vergelijking, waardoor `/dev/sda` ook `/dev/sdaa` blokkeerde. In k8s-modus
  zijn ook Talos-partities en host-mounts beschermd.
- **Volume Group verwijderen** weigert nu een VG die nog Logical Volumes bevat
  (voorheen nam `vgremove -y` die mee).
- **Broncode is nu publiek.** De privé-repo `SMUI` is (met volledige geschiedenis)
  samengevoegd in `aalhabeeb/dmtui`; broncode, packaging en releases staan nu in
  één repo. De release-workflow publiceert naar deze repo met de standaard
  `GITHUB_TOKEN` (het secret `RELEASES_TOKEN` is niet meer nodig).
- Het achtergebleven duplicaat `smui.sh` is verwijderd; gebruik `dmtui.sh`.

## [2.0.0] - 2026-07-14

### Gewijzigd (breaking)
- **Hernoemd van SMUI naar `dmtui` (Disk Management TUI).** Het commando heet nu
  `dmtui` (voorheen `smui`), het pakket heet `dmtui`, en de bestanden zijn
  `dmtui.sh` / `dmtui.1`. Omgevingsvariabelen heten nu `DMTUI_DEBUG` en
  `DMTUI_NO_FZF` (voorheen `SMUI_*`). Wie de oude `smui` had geïnstalleerd kan die
  verwijderen (`sudo apt remove smui` / `sudo dnf remove smui`) en `dmtui`
  installeren.

## [1.5.1] - 2026-07-12

### Gewijzigd
- Copyright en package-metadata (maintainer, vendor, homepage) aangepast naar
  **lean-it.nl**.

## [1.5.0] - 2026-07-12

### Gewijzigd
- **Alle menu's** (hoofdmenu, wizard-keuzes, filesystem, verwijderen, partitielabel)
  lopen nu via `render_menu`. Met `fzf` betekent dit: **dubbelklik = direct kiezen**,
  enkele klik = markeren, en typen om te filteren. Zonder `fzf` gewoon het
  `dialog`-menu (klik + OK). Bij een `fzf`-fout wordt automatisch teruggevallen op
  dialog.

## [1.4.4] - 2026-07-12

### Gewijzigd
- Achtergrond (desktop-backdrop) van blauw naar **zwart**; de vensters blijven
  wit/leesbaar. Aan te passen in het `DIALOGRC`-thema (`screen_color`).

## [1.4.3] - 2026-07-12

### Gewijzigd
- **Layout tonen** gebruikt nu een echte tekstviewer (`dialog --textbox`) die de
  uitvoer letterlijk toont, zodat de kolommen van `lsblk`/`pvs`/`vgs`/`lvs` netjes
  uitgelijnd blijven (voorheen vouwde de msgbox spaties samen en liepen de kolommen
  door elkaar). De LVM-overzichten tonen alleen de nuttige kolommen.

## [1.4.2] - 2026-07-12

### Opgelost
- De wizard viel na het intro-scherm terug naar het hoofdmenu wanneer `fzf`
  geïnstalleerd was: SMUI gebruikte `fzf`-opties (`--border=rounded`, `--info=inline`,
  uitgebreide `--color`) die oudere `fzf`-versies niet kennen, waardoor `fzf` direct
  met een fout stopte. Nu worden alleen breed-ondersteunde opties gebruikt, én valt
  SMUI automatisch terug op het `dialog`-menu als `fzf` toch een fout geeft.

## [1.4.1] - 2026-07-12

### Gewijzigd
- SMUI probeert bij de eerste start `fzf` **automatisch** te installeren
  (best-effort, eenmalig via een marker, nooit blokkerend). Zo krijg je de
  filterbare lijsten ook zonder handmatige installatie. Op RHEL zonder EPEL of
  bij `SMUI_NO_FZF=1` wordt dit netjes overgeslagen en gebruikt SMUI het
  `dialog`-menu.

## [1.4.0] - 2026-07-12

### Toegevoegd
- **Kleurthema** voor `dialog` (via een gegenereerd `DIALOGRC`): frissere,
  consistente kleuren met een blauw/witte look.
- **Optionele `fzf`-integratie** voor de disk-/VG-/LV-/PV-lijsten: **typen om te
  filteren**, muis-klik en scrollen. Ontbreekt `fzf`, dan valt SMUI automatisch
  terug op het `dialog`-menu. Uit te schakelen met `SMUI_NO_FZF=1`.
- `.deb` adviseert `fzf` (Recommends); optioneel op RHEL via EPEL.

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
  `aalhabeeb/dmtui` (broncode blijft privé).

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

[Unreleased]: https://github.com/aalhabeeb/SMUI/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v2.0.0
[1.5.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.5.1
[1.5.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.5.0
[1.4.4]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.4.4
[1.4.3]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.4.3
[1.4.2]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.4.2
[1.4.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.4.1
[1.4.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.4.0
[1.3.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.3.0
[1.2.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.2.0
[1.1.3]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.3
[1.1.2]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.2
[1.1.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.1
[1.1.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.1.0
[1.0.1]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.0.1
[1.0.0]: https://github.com/aalhabeeb/SMUI/releases/tag/v1.0.0
