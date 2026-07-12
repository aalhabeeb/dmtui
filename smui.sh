#!/usr/bin/env bash
#
# SMUI - Storage Management UI
# Een nmtui-achtige TUI voor opslagbeheer op RHEL/Rocky/Alma en Ubuntu/Debian.
#
# Functies:
#   * Extra disk kiezen + partitie aanmaken (type 8e / Linux LVM)
#   * Physical Volume / Volume Group / Logical Volume aanmaken
#   * VG en LV uitbreiden (extend)
#   * Filesystem formatteren + mounten (met fstab-entry op UUID)
#   * Bestaande opslag-/LVM-layout tonen
#   * Verwijderen van LV / VG / PV (met dubbele bevestiging)
#
# Backend-tools zijn distro-onafhankelijk (util-linux, parted, lvm2).
# Alleen het installeren van dependencies verschilt per distro.
#
# Gebruik: sudo ./smui.sh
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Constantes / globale variabelen
# ---------------------------------------------------------------------------
SMUI_VERSION="1.4.3"
APP_TITLE="SMUI - Storage Management UI v${SMUI_VERSION}"
# Vaste kopbalk boven elk venster (moderne look).
BACKTITLE="SMUI - Storage Management UI v${SMUI_VERSION}   |   muis + pijltjestoetsen"
PKG_MGR=""          # dnf | yum | apt-get
DISTRO_ID=""        # rhel | ubuntu | debian | ...
ROOT_DISK=""        # disk die de root-mount bevat (beschermd)
DIALOGRC_TMP=""     # tijdelijk themabestand voor dialog (kleurthema)

# Dialooggroottes (worden aangepast aan de terminal in compute_dialog_size).
DLG_H=20            # hoogte voor vensters/menu's
DLG_W=76            # breedte voor vensters/menu's
LIST_H=12           # aantal zichtbare regels in een menu-lijst

# ---------------------------------------------------------------------------
# Basis-helpers
# ---------------------------------------------------------------------------
die() {
    echo "FOUT: $*" >&2
    exit 1
}

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        die "Dit script moet als root draaien. Start met: sudo $0"
    fi
}

# Detecteer distributie en de bijbehorende packagemanager.
detect_distro() {
    if [[ ! -r /etc/os-release ]]; then
        die "/etc/os-release niet gevonden; distro niet te bepalen."
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"

    if command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt-get"
    else
        die "Geen ondersteunde packagemanager gevonden (dnf/yum/apt-get)."
    fi
}

# Installeer benodigde pakketten als een commando ontbreekt.
ensure_deps() {
    # commando -> pakketnaam ('dialog' heet op alle distro's gewoon 'dialog').
    local -a missing=()
    command -v dialog   >/dev/null 2>&1 || missing+=("dialog")
    command -v lvs      >/dev/null 2>&1 || missing+=("lvm2")
    command -v parted   >/dev/null 2>&1 || missing+=("parted")
    command -v lsblk    >/dev/null 2>&1 || missing+=("util-linux")
    command -v blkid    >/dev/null 2>&1 || missing+=("util-linux")

    [[ ${#missing[@]} -eq 0 ]] && return 0

    echo "De volgende afhankelijkheden ontbreken en worden geïnstalleerd: ${missing[*]}"

    local -a pkgs=()
    local m
    for m in "${missing[@]}"; do
        case "$m" in
            dialog)     pkgs+=("dialog") ;;
            lvm2)       pkgs+=("lvm2") ;;
            parted)     pkgs+=("parted") ;;
            util-linux) pkgs+=("util-linux") ;;
        esac
    done

    # dedupliceer
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)

    if [[ "$PKG_MGR" == "apt-get" ]]; then
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    else
        "$PKG_MGR" install -y "${pkgs[@]}"
    fi

    command -v dialog >/dev/null 2>&1 || die "dialog installeren is mislukt."
}

# Best-effort: installeer het OPTIONELE fzf (mooiere, filterbare lijsten).
# Nooit fataal. Probeert het maar één keer (marker), zodat het niet elke start
# opnieuw probeert als het niet beschikbaar is (bijv. RHEL zonder EPEL).
ensure_fzf_optional() {
    command -v fzf >/dev/null 2>&1 && return 0
    [[ "${SMUI_NO_FZF:-0}" == "1" ]] && return 0

    local marker="/var/lib/smui/.fzf-attempted"
    [[ -f "$marker" ]] && return 0
    mkdir -p /var/lib/smui 2>/dev/null || true

    echo "Optioneel: fzf installeren voor filterbare lijsten (eenmalige poging, niet vereist)..."
    if [[ "$PKG_MGR" == "apt-get" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y fzf >/dev/null 2>&1 || true
    else
        "$PKG_MGR" install -y fzf >/dev/null 2>&1 || true
    fi
    : >"$marker" 2>/dev/null || true
}

# Bepaal welke fysieke disk de root-mount (/) bevat, zodat we die beschermen.
detect_root_disk() {
    local root_src part
    root_src=$(findmnt -no SOURCE / 2>/dev/null || true)
    if [[ -n "$root_src" ]]; then
        # Volg door tot de onderliggende disk (pkname van de bron).
        part=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n1 || true)
        if [[ -n "$part" ]]; then
            ROOT_DISK="/dev/${part}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Dialog-wrappers (dialog i.p.v. whiptail: muisondersteuning + kleurthema)
# ---------------------------------------------------------------------------
# Bepaalt veilige dialooggroottes op basis van de werkelijke terminalgrootte,
# zodat vensters nooit groter zijn dan de terminal (anders faalt dialog).
compute_dialog_size() {
    local lines cols
    lines=$(tput lines 2>/dev/null || echo 24)
    cols=$(tput cols 2>/dev/null || echo 80)
    # Vang lege/ongeldige waarden af.
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=24
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    # Boxhoogte: 1 regel marge t.o.v. de terminal, max 23, min 12.
    DLG_H=$(( lines - 1 ))
    if (( DLG_H > 23 )); then DLG_H=23; fi
    if (( DLG_H < 12 )); then DLG_H=12; fi

    # Boxbreedte: 2 kolommen marge, max 84, min 50.
    DLG_W=$(( cols - 2 ))
    if (( DLG_W > 84 )); then DLG_W=84; fi
    if (( DLG_W < 50 )); then DLG_W=50; fi

    # Lijsthoogte ruim binnen de box houden: dialog heeft ~12 regels nodig voor
    # titel, prompttekst, knoppen en randen. Te grote lijst => dialog faalt.
    LIST_H=$(( DLG_H - 12 ))
    if (( LIST_H < 3 )); then LIST_H=3; fi

    if [[ "${SMUI_DEBUG:-0}" == "1" ]]; then
        echo "SMUI_DEBUG: term=${lines}x${cols}  box=${DLG_H}x${DLG_W}  list=${LIST_H}" >&2
    fi
}

msg_box() {
    dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --msgbox "$1" "$DLG_H" "$DLG_W"
}

info_scroll() {
    # Toon lange tekst scrollbaar (scrollbar + pijltjes/muis).
    dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --scrollbar --msgbox "$1" "$DLG_H" "$DLG_W"
}

# Toont tekst/uitvoer LETTERLIJK in een scrollbare tekstviewer (kolommen blijven
# uitgelijnd, i.t.t. msgbox die spaties samenvouwt). $1 = titel, $2 = inhoud.
text_view() {
    local title="$1" content="$2" tmp
    tmp=$(mktemp 2>/dev/null) || { info_scroll "$content"; return; }
    # Zet eventuele letterlijke "\n" om naar echte regeleindes.
    printf '%s\n' "${content//\\n/$'\n'}" >"$tmp"
    dialog --backtitle "$BACKTITLE" --title "$title" --textbox "$tmp" "$DLG_H" "$DLG_W"
    rm -f "$tmp"
}

confirm_box() {
    # Retourneert 0 (ja) of 1 (nee). Standaard op 'nee' voor veiligheid.
    dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --defaultno \
        --yes-label "Ja" --no-label "Nee" --yesno "$1" "$DLG_H" "$DLG_W"
}

input_box() {
    # $1 = prompt, $2 = default. Print resultaat op stdout, of niets bij annuleren.
    local result
    result=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" \
        --ok-label "OK" --cancel-label "Annuleren" \
        --inputbox "$1" 11 "$DLG_W" "${2:-}" 3>&1 1>&2 2>&3) || return 1
    printf '%s' "$result"
}

# Schrijft een modern kleurthema voor dialog naar een tijdelijk bestand en zet
# DIALOGRC erop. Wordt bij afsluiten opgeruimd (trap).
setup_dialog_theme() {
    DIALOGRC_TMP="$(mktemp 2>/dev/null)" || { DIALOGRC_TMP=""; return 0; }
    cat >"$DIALOGRC_TMP" <<'RC'
use_shadow = ON
use_colors = ON
screen_color = (CYAN,BLUE,ON)
shadow_color = (BLACK,BLACK,ON)
dialog_color = (BLACK,WHITE,OFF)
title_color = (WHITE,BLUE,ON)
border_color = (WHITE,WHITE,ON)
border2_color = (WHITE,WHITE,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,BLUE,ON)
button_key_inactive_color = (RED,WHITE,OFF)
button_label_active_color = (YELLOW,BLUE,ON)
button_label_inactive_color = (BLACK,WHITE,ON)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (WHITE,WHITE,ON)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (WHITE,BLUE,ON)
searchbox_border_color = (WHITE,WHITE,ON)
position_indicator_color = (BLUE,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (WHITE,WHITE,ON)
menubox_border2_color = (WHITE,WHITE,ON)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (BLUE,WHITE,ON)
tag_selected_color = (YELLOW,BLUE,ON)
tag_key_color = (RED,WHITE,OFF)
tag_key_selected_color = (YELLOW,BLUE,ON)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,BLUE,ON)
uarrow_color = (GREEN,WHITE,ON)
darrow_color = (GREEN,WHITE,ON)
RC
    export DIALOGRC="$DIALOGRC_TMP"
    trap 'rm -f "${DIALOGRC_TMP:-}"' EXIT
}

# Is fzf beschikbaar? (optioneel; geeft typen-om-te-filteren + muis in lijsten)
have_fzf() {
    [[ "${SMUI_NO_FZF:-0}" != "1" ]] && command -v fzf >/dev/null 2>&1
}

# Toont een keuzelijst en geeft de gekozen 'tag' terug.
# Met fzf: modern, typen om te filteren + muis. Zonder fzf (of bij een fzf-fout):
# val automatisch terug op het dialog-menu.
# $1 = kop/omschrijving, daarna paren: tag omschrijving tag omschrijving ...
render_menu() {
    local header="$1"; shift
    local -a pairs=("$@")

    if have_fzf; then
        local i
        local -a lines=()
        for (( i=0; i<${#pairs[@]}; i+=2 )); do
            lines+=("${pairs[i]}"$'\t'"${pairs[i+1]}")
        done
        # Alleen breed-ondersteunde fzf-opties (compatibel met oudere versies).
        local sel rc=0
        sel=$(printf '%s\n' "${lines[@]}" | fzf \
            --reverse --prompt='Zoek: ' \
            --header="${header}  (typ=filter, muis/pijltjes, Enter=kies, Esc=terug)") || rc=$?
        if (( rc == 0 )) && [[ -n "$sel" ]]; then
            printf '%s' "${sel%%$'\t'*}"
            return 0
        elif (( rc == 130 )); then
            return 1   # gebruiker annuleerde met Esc
        fi
        # rc anders (fzf-optie-/omgevingsfout): val terug op het dialog-menu.
    fi

    dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" \
        --ok-label "Kies" --cancel-label "Annuleren" \
        --menu "$header" "$DLG_H" "$DLG_W" "$LIST_H" "${pairs[@]}" 3>&1 1>&2 2>&3
}

# ---------------------------------------------------------------------------
# Commando-uitvoering met preview
# ---------------------------------------------------------------------------
# Voert een reeks commando's uit ZONDER extra bevestiging en toont de uitvoer.
# Elk argument is één volledig commando (string).
exec_cmds() {
    local -a cmds=("$@")
    local output="" rc=0 c out
    for c in "${cmds[@]}"; do
        output+="\$ ${c}\n"
        if ! out=$(eval "$c" 2>&1); then
            rc=$?
            output+="${out}\n[FOUT] commando faalde (exitcode ${rc}).\n"
            info_scroll "${output}\nUitvoering gestopt door een fout."
            return 1
        fi
        [[ -n "$out" ]] && output+="${out}\n"
    done
    info_scroll "${output}\nKlaar."
    return 0
}

# Voert een reeks commando's uit na een preview + bevestiging.
run_cmds() {
    local -a cmds=("$@")
    local preview="" c
    for c in "${cmds[@]}"; do
        preview+="  ${c}\n"
    done

    if ! confirm_box "De volgende commando's worden uitgevoerd:\n\n${preview}\nDoorgaan?"; then
        msg_box "Geannuleerd. Er is niets gewijzigd."
        return 1
    fi
    exec_cmds "${cmds[@]}"
}

# ---------------------------------------------------------------------------
# Selectie-helpers
# ---------------------------------------------------------------------------
# Geeft de partitienaam voor de eerste partitie van een disk terug.
# nvme0n1 -> nvme0n1p1 ; sdb -> sdb1
part_name() {
    local disk="$1"
    if [[ "$disk" =~ [0-9]$ ]]; then echo "${disk}p1"; else echo "${disk}1"; fi
}

# Geeft een leesbaar statuslabel voor een hele disk terug, zodat de gebruiker
# in één oogopslag ziet welke disk nieuw/leeg is en welke in gebruik is.
disk_status() {
    local disk="$1"
    if [[ -n "$ROOT_DISK" && "$disk" == "$ROOT_DISK" ]]; then
        echo "SYSTEEMDISK (beschermd)"; return
    fi
    local nparts nmounts nlvm
    nparts=$(lsblk -rno TYPE "$disk" 2>/dev/null | grep -cx 'part' || true)
    nmounts=$(lsblk -rno MOUNTPOINT "$disk" 2>/dev/null | grep -c . || true)
    nlvm=$(lsblk -rno TYPE "$disk" 2>/dev/null | grep -cx 'lvm' || true)

    if [[ "${nparts:-0}" -eq 0 && "${nmounts:-0}" -eq 0 && "${nlvm:-0}" -eq 0 ]]; then
        echo "LEEG - nieuw (aanbevolen)"; return
    fi
    local label="in gebruik"
    [[ "${nparts:-0}" -gt 0 ]] && label="${label}: ${nparts} partitie(s)"
    [[ "${nlvm:-0}" -gt 0 ]] && label="${label}, LVM"
    [[ "${nmounts:-0}" -gt 0 ]] && label="${label}, gemount"
    echo "$label"
}

# Toont een menu met hele disks (TYPE=disk) en geeft de gekozen /dev/naam terug.
# Elke disk krijgt een statuslabel (leeg/in gebruik/systeemdisk).
# $1 = titel-prompt
select_disk() {
    local prompt="$1"
    local -a items=()
    local name size model type

    while read -r name size type model; do
        [[ "$type" != "disk" ]] && continue
        local dev="/dev/${name}"
        items+=("$dev" "${size}  ${model:-disk}  |  $(disk_status "$dev")")
    done < <(lsblk -dno NAME,SIZE,TYPE,MODEL)

    [[ ${#items[@]} -eq 0 ]] && { msg_box "Geen disks gevonden."; return 1; }

    render_menu "$prompt" "${items[@]}"
}

# Toont een menu met blok-partities/disks die als PV bruikbaar zijn.
# $1 = titel-prompt
select_block() {
    local prompt="$1"
    local -a items=()
    local name size type mnt

    while read -r name size type mnt; do
        case "$type" in
            part|disk|raid*|crypt) ;;
            *) continue ;;
        esac
        local dev="/dev/${name}"
        local desc="${size} type=${type} mount=${mnt:-geen}"
        items+=("$dev" "$desc")
    done < <(lsblk -rno NAME,SIZE,TYPE,MOUNTPOINT)

    [[ ${#items[@]} -eq 0 ]] && { msg_box "Geen blok-apparaten gevonden."; return 1; }

    render_menu "$prompt" "${items[@]}"
}

# Menu met bestaande Volume Groups.
select_vg() {
    local prompt="$1"
    local -a items=()
    local vg size free
    while read -r vg size free; do
        [[ -z "$vg" ]] && continue
        items+=("$vg" "grootte=${size} vrij=${free}")
    done < <(vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null | awk '{print $1, $2, $3}')

    [[ ${#items[@]} -eq 0 ]] && { msg_box "Geen Volume Groups gevonden."; return 1; }
    render_menu "$prompt" "${items[@]}"
}

# Menu met bestaande Logical Volumes (geeft VG/LV-pad /dev/vg/lv terug).
select_lv() {
    local prompt="$1"
    local -a items=()
    local lv vg size
    while read -r lv vg size; do
        [[ -z "$lv" ]] && continue
        items+=("/dev/${vg}/${lv}" "vg=${vg} grootte=${size}")
    done < <(lvs --noheadings -o lv_name,vg_name,lv_size 2>/dev/null | awk '{print $1, $2, $3}')

    [[ ${#items[@]} -eq 0 ]] && { msg_box "Geen Logical Volumes gevonden."; return 1; }
    render_menu "$prompt" "${items[@]}"
}

# Menu met bestaande Physical Volumes.
select_pv() {
    local prompt="$1"
    local -a items=()
    local pv vg size
    while read -r pv vg size; do
        [[ -z "$pv" ]] && continue
        items+=("$pv" "vg=${vg:-geen} grootte=${size}")
    done < <(pvs --noheadings -o pv_name,vg_name,pv_size 2>/dev/null | awk '{print $1, $2, $3}')

    [[ ${#items[@]} -eq 0 ]] && { msg_box "Geen Physical Volumes gevonden."; return 1; }
    render_menu "$prompt" "${items[@]}"
}

# Veiligheidscheck: weiger bewerkingen op de systeemdisk.
guard_system_disk() {
    local dev="$1"
    if [[ -n "$ROOT_DISK" && "$dev" == "$ROOT_DISK"* ]]; then
        msg_box "GEWEIGERD: $dev hoort bij de systeemdisk ($ROOT_DISK).\nSMUI voert hierop geen destructieve bewerkingen uit."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Feature: partitie (type 8e / Linux LVM) aanmaken
# ---------------------------------------------------------------------------
action_create_partition() {
    local disk
    disk=$(select_disk "Kies een disk om een LVM-partitie (type 8e) op aan te maken:") || return 0
    [[ -z "$disk" ]] && return 0
    guard_system_disk "$disk" || return 0

    local label
    label=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --menu \
        "Partitietabel voor ${disk}.\nLet op: 'nieuw label' WIST alle bestaande partities!" 18 78 4 \
        "keep" "Bestaande tabel behouden, alleen partitie toevoegen" \
        "gpt"  "Nieuw GPT-label (wist disk) - aanbevolen" \
        "msdos" "Nieuw MBR/msdos-label (wist disk)" \
        3>&1 1>&2 2>&3) || return 0

    local size
    size=$(input_box "Grootte van de partitie (bijv. 100%, 50GB, 500MB).\nStandaard vult de resterende ruimte:" "100%") || return 0
    [[ -z "$size" ]] && size="100%"

    local -a cmds=()
    if [[ "$label" != "keep" ]]; then
        cmds+=("parted -s ${disk} mklabel ${label}")
    fi
    # Maak partitie van eerste vrije ruimte tot opgegeven grootte.
    if [[ "$size" == "100%" ]]; then
        cmds+=("parted -s -a optimal ${disk} mkpart primary 0% 100%")
    else
        cmds+=("parted -s -a optimal ${disk} mkpart primary 0% ${size}")
    fi
    # Zet de LVM-vlag (equivalent van partitietype 8e / 8e00).
    cmds+=("parted -s ${disk} set 1 lvm on")
    cmds+=("partprobe ${disk} || udevadm settle")

    run_cmds "${cmds[@]}"
}

# ---------------------------------------------------------------------------
# Feature: Physical Volume aanmaken
# ---------------------------------------------------------------------------
action_create_pv() {
    local dev
    dev=$(select_block "Kies een partitie/disk om als Physical Volume (PV) te initialiseren:") || return 0
    [[ -z "$dev" ]] && return 0
    guard_system_disk "$dev" || return 0

    if ! confirm_box "pvcreate initialiseert ${dev} voor LVM.\nEventuele bestaande gegevens/filesystem gaan verloren.\nDoorgaan?"; then
        return 0
    fi
    run_cmds "pvcreate ${dev}"
}

# ---------------------------------------------------------------------------
# Feature: Volume Group aanmaken
# ---------------------------------------------------------------------------
action_create_vg() {
    local pv
    pv=$(select_pv "Kies het Physical Volume voor de nieuwe Volume Group:") || return 0
    [[ -z "$pv" ]] && return 0

    local vgname
    vgname=$(input_box "Naam van de nieuwe Volume Group:" "vg_data") || return 0
    [[ -z "$vgname" ]] && { msg_box "Geen naam opgegeven."; return 0; }

    run_cmds "vgcreate ${vgname} ${pv}"
}

# ---------------------------------------------------------------------------
# Feature: Logical Volume aanmaken
# ---------------------------------------------------------------------------
action_create_lv() {
    local vg
    vg=$(select_vg "Kies de Volume Group voor het nieuwe Logical Volume:") || return 0
    [[ -z "$vg" ]] && return 0

    local lvname
    lvname=$(input_box "Naam van het nieuwe Logical Volume:" "lv_data") || return 0
    [[ -z "$lvname" ]] && { msg_box "Geen naam opgegeven."; return 0; }

    local size
    size=$(input_box "Grootte van het LV.\nGebruik bijv. 20G, 500M, of 100%FREE voor alle vrije ruimte:" "100%FREE") || return 0
    [[ -z "$size" ]] && size="100%FREE"

    local cmd
    if [[ "$size" == *%* ]]; then
        cmd="lvcreate -l ${size} -n ${lvname} ${vg}"
    else
        cmd="lvcreate -L ${size} -n ${lvname} ${vg}"
    fi
    run_cmds "$cmd"
}

# ---------------------------------------------------------------------------
# Feature: VG uitbreiden met een extra PV
# ---------------------------------------------------------------------------
action_extend_vg() {
    local vg
    vg=$(select_vg "Kies de Volume Group om uit te breiden:") || return 0
    [[ -z "$vg" ]] && return 0

    local dev
    dev=$(select_block "Kies de partitie/disk om aan ${vg} toe te voegen:") || return 0
    [[ -z "$dev" ]] && return 0
    guard_system_disk "$dev" || return 0

    local -a cmds=()
    # Maak er een PV van als dat nog niet zo is.
    if ! pvs "$dev" >/dev/null 2>&1; then
        if ! confirm_box "${dev} is nog geen PV. pvcreate zal gegevens op ${dev} wissen.\nDoorgaan?"; then
            return 0
        fi
        cmds+=("pvcreate ${dev}")
    fi
    cmds+=("vgextend ${vg} ${dev}")
    run_cmds "${cmds[@]}"
}

# ---------------------------------------------------------------------------
# Feature: LV uitbreiden (+ filesystem meegroeien)
# ---------------------------------------------------------------------------
action_extend_lv() {
    local lv
    lv=$(select_lv "Kies het Logical Volume om uit te breiden:") || return 0
    [[ -z "$lv" ]] && return 0

    local size
    size=$(input_box "Extra ruimte toevoegen (bijv. +10G) of nieuwe totale grootte (bijv. 50G).\nGebruik +100%FREE voor alle vrije ruimte in de VG:" "+100%FREE") || return 0
    [[ -z "$size" ]] && return 0

    local grow_fs="no"
    if confirm_box "Filesystem op ${lv} automatisch mee laten groeien?\n(werkt voor ext4/xfs via lvextend -r)"; then
        grow_fs="yes"
    fi

    local cmd
    if [[ "$size" == *%* ]]; then
        cmd="lvextend -l ${size} ${lv}"
    else
        cmd="lvextend -L ${size} ${lv}"
    fi
    [[ "$grow_fs" == "yes" ]] && cmd="${cmd} -r"

    run_cmds "$cmd"
}

# ---------------------------------------------------------------------------
# Feature: formatteren + mounten (met fstab op UUID)
# ---------------------------------------------------------------------------
action_format_mount() {
    local dev
    dev=$(select_block "Kies het apparaat/LV om te formatteren en te mounten:") || return 0
    [[ -z "$dev" ]] && return 0
    guard_system_disk "$dev" || return 0

    local fstype
    fstype=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --menu "Kies het filesystem voor ${dev}:" 16 70 4 \
        "ext4" "Algemeen, breed ondersteund" \
        "xfs"  "Standaard op RHEL, goed voor grote volumes" \
        "btrfs" "Snapshots/subvolumes" \
        3>&1 1>&2 2>&3) || return 0

    local mountpoint
    mountpoint=$(input_box "Mountpoint (map) voor ${dev}:" "/mnt/data") || return 0
    [[ -z "$mountpoint" ]] && { msg_box "Geen mountpoint opgegeven."; return 0; }

    if ! confirm_box "LET OP: ${dev} wordt geformatteerd als ${fstype}.\nALLE gegevens op ${dev} gaan verloren!\n\nMounten op: ${mountpoint}\nDoorgaan?"; then
        return 0
    fi

    local mkfs_cmd="mkfs.${fstype}"
    [[ "$fstype" == "ext4" ]] && mkfs_cmd="mkfs.ext4 -F"
    [[ "$fstype" == "xfs" ]]  && mkfs_cmd="mkfs.xfs -f"
    [[ "$fstype" == "btrfs" ]] && mkfs_cmd="mkfs.btrfs -f"

    local -a cmds=(
        "${mkfs_cmd} ${dev}"
        "mkdir -p ${mountpoint}"
    )
    # UUID ophalen en fstab-entry toevoegen gebeurt na formatteren; we bouwen
    # dat als één samengesteld commando zodat de UUID actueel is.
    cmds+=("UUID=\$(blkid -s UUID -o value ${dev}); \
        grep -q \"\$UUID\" /etc/fstab || echo \"UUID=\$UUID ${mountpoint} ${fstype} defaults 0 2\" >> /etc/fstab")
    cmds+=("systemctl daemon-reload 2>/dev/null || true")
    cmds+=("mount ${mountpoint}")

    run_cmds "${cmds[@]}"
}

# ---------------------------------------------------------------------------
# Feature: layout tonen
# ---------------------------------------------------------------------------
action_show_layout() {
    local out=""
    out+="=== DISKS & PARTITIES (lsblk) ===\n"
    out+="$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>&1)\n\n"
    out+="=== PHYSICAL VOLUMES (pvs) ===\n"
    out+="$(pvs -o pv_name,vg_name,pv_size,pv_free 2>&1 || echo 'geen')\n\n"
    out+="=== VOLUME GROUPS (vgs) ===\n"
    out+="$(vgs -o vg_name,pv_count,lv_count,vg_size,vg_free 2>&1 || echo 'geen')\n\n"
    out+="=== LOGICAL VOLUMES (lvs) ===\n"
    out+="$(lvs -o lv_name,vg_name,lv_size,lv_attr 2>&1 || echo 'geen')\n"
    text_view "Opslag-layout" "$out"
}

# ---------------------------------------------------------------------------
# Feature: verwijderen (LV / VG / PV)
# ---------------------------------------------------------------------------
action_remove_menu() {
    local choice
    choice=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --menu "Wat wil je verwijderen?" 16 70 4 \
        "lv" "Logical Volume verwijderen" \
        "vg" "Volume Group verwijderen" \
        "pv" "Physical Volume-signatuur verwijderen" \
        "back" "Terug" \
        3>&1 1>&2 2>&3) || return 0

    case "$choice" in
        lv) remove_lv ;;
        vg) remove_vg ;;
        pv) remove_pv ;;
        *) return 0 ;;
    esac
}

remove_lv() {
    local lv
    lv=$(select_lv "Kies het Logical Volume om te VERWIJDEREN:") || return 0
    [[ -z "$lv" ]] && return 0

    # Waarschuw als het gemount is.
    local mnt
    mnt=$(findmnt -no TARGET "$lv" 2>/dev/null || true)
    if [[ -n "$mnt" ]]; then
        if ! confirm_box "${lv} is gemount op ${mnt} en wordt eerst geünmount.\nDoorgaan?"; then
            return 0
        fi
    fi

    if ! confirm_box "DEFINITIEF: verwijder Logical Volume ${lv}?\nAlle gegevens gaan verloren."; then
        return 0
    fi

    local -a cmds=()
    [[ -n "$mnt" ]] && cmds+=("umount ${lv}")
    cmds+=("lvremove -y ${lv}")
    run_cmds "${cmds[@]}"
}

remove_vg() {
    local vg
    vg=$(select_vg "Kies de Volume Group om te VERWIJDEREN:") || return 0
    [[ -z "$vg" ]] && return 0

    if ! confirm_box "DEFINITIEF: verwijder Volume Group ${vg}?\nDit kan alleen als er geen actieve LV's meer in zitten."; then
        return 0
    fi
    run_cmds "vgremove -y ${vg}"
}

remove_pv() {
    local pv
    pv=$(select_pv "Kies het Physical Volume om te verwijderen:") || return 0
    [[ -z "$pv" ]] && return 0

    if ! confirm_box "DEFINITIEF: verwijder de LVM-signatuur van ${pv}?\nDit kan alleen als het PV niet meer in een VG zit."; then
        return 0
    fi
    run_cmds "pvremove -y ${pv}"
}

# ---------------------------------------------------------------------------
# Wizard: nieuwe disk in één keer in gebruik nemen
# ---------------------------------------------------------------------------
# Voegt een nieuwe disk toe aan een BESTAANDE Volume Group: partitie (8e) ->
# pvcreate -> vgextend, en optioneel meteen een bestaand LV vergroten (fs groeit
# mee). $1 = de gekozen disk (bijv. /dev/sdc).
wizard_extend_existing() {
    local disk="$1"
    local part; part="$(part_name "$disk")"

    # Zijn er Volume Groups om aan toe te voegen?
    if ! vgs --noheadings -o vg_name 2>/dev/null | grep -q .; then
        msg_box "Er zijn nog geen Volume Groups om aan toe te voegen.\nMaak eerst nieuwe opslag aan via de wizard-optie 'Nieuwe opslag'."
        return 0
    fi

    local vg
    vg=$(select_vg "Kies de Volume Group om ${disk} aan toe te voegen:") || return 0
    [[ -z "$vg" ]] && return 0

    # Optioneel: meteen een bestaand LV in die VG vergroten.
    local grow_lv="" lv=""
    local -a lvitems=()
    local lvn lvsz
    while read -r lvn lvsz; do
        [[ -z "$lvn" ]] && continue
        lvitems+=("/dev/${vg}/${lvn}" "grootte=${lvsz}")
    done < <(lvs --noheadings -o lv_name,lv_size --select "vg_name=${vg}" 2>/dev/null | awk '{print $1, $2}')

    if [[ ${#lvitems[@]} -gt 0 ]]; then
        if confirm_box "Wil je met de nieuwe ruimte meteen een bestaand Logical Volume in ${vg} vergroten?\n\nJa  = kies een LV en groei het (inclusief filesystem).\nNee = alleen de VG uitbreiden; de ruimte blijft vrij in ${vg}."; then
            lv=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --ok-label "Kies" --cancel-label "Annuleren" --menu "Kies het Logical Volume in ${vg} om te vergroten:" "$DLG_H" "$DLG_W" "$LIST_H" "${lvitems[@]}" 3>&1 1>&2 2>&3) || return 0
            [[ -n "$lv" ]] && grow_lv="yes"
        fi
    fi

    local lvline
    if [[ "$grow_lv" == "yes" ]]; then
        lvline="  LV vergroten : ${lv} (+alle nieuwe ruimte, filesystem groeit mee)"
    else
        lvline="  LV vergroten : nee (ruimte blijft vrij in ${vg})"
    fi

    if ! dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --defaultno --yes-label "Ja, uitvoeren" --no-label "Annuleren" --yesno \
"Samenvatting van wat er gaat gebeuren:\n\n\
  Disk         : ${disk}   (wordt VOLLEDIG gewist)\n\
  Partitie     : ${part}   (type 8e / Linux LVM)\n\
  Toevoegen aan: Volume Group ${vg}\n\
${lvline}\n\n\
Wil je dit uitvoeren?" "$DLG_H" "$DLG_W"; then
        msg_box "Geannuleerd. Er is niets gewijzigd."
        return 0
    fi

    local -a cmds=(
        "parted -s ${disk} mklabel gpt"
        "parted -s -a optimal ${disk} mkpart primary 0% 100%"
        "parted -s ${disk} set 1 lvm on"
        "partprobe ${disk} || udevadm settle"
        "pvcreate -y ${part}"
        "vgextend ${vg} ${part}"
    )
    [[ "$grow_lv" == "yes" ]] && cmds+=("lvextend -l +100%FREE -r ${lv}")

    if exec_cmds "${cmds[@]}"; then
        if [[ "$grow_lv" == "yes" ]]; then
            msg_box "Klaar! ${lv} is vergroot met de ruimte van ${disk}.\n\nControleer met:  df -h   of   lvs"
        else
            msg_box "Klaar! ${vg} is uitgebreid met ${part}.\nDe extra ruimte is nu vrij in ${vg} (zie 'Layout tonen')."
        fi
    fi
}

# ---------------------------------------------------------------------------
# Wizard: nieuwe disk in één keer in gebruik nemen
# ---------------------------------------------------------------------------
# Begeleide flow: disk kiezen -> partitie (8e) -> PV -> VG -> LV -> filesystem
# -> mounten. Slimme standaardwaarden en één duidelijke samenvatting vooraf.
action_new_disk_wizard() {
    msg_box "WIZARD - disk in gebruik nemen\n\nJe kunt een disk op twee manieren gebruiken:\n 1) Nieuwe opslag aanmaken (nieuwe VG + LV + mount).\n 2) Toevoegen aan een bestaande Volume Group (uitbreiden),\n    met een partitie van type 8e.\n\nDe systeemdisk wordt automatisch beschermd."

    local disk
    disk=$(select_disk "Kies de disk om in gebruik te nemen\n('LEEG - nieuw' = veilige, lege disk):") || return 0
    [[ -z "$disk" ]] && return 0
    guard_system_disk "$disk" || return 0

    # Waarschuw als de disk niet leeg is.
    local status; status="$(disk_status "$disk")"
    if [[ "$status" != LEEG* ]]; then
        if ! confirm_box "LET OP: ${disk} is niet leeg.\nStatus: ${status}\n\nDe HELE disk wordt gewist als je doorgaat.\nDoorgaan?"; then
            msg_box "Geannuleerd. Er is niets gewijzigd."
            return 0
        fi
    fi

    # Kies wat er met de disk moet gebeuren.
    local mode
    mode=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --ok-label "Kies" --cancel-label "Annuleren" --menu \
        "Wat wil je met ${disk} doen?" "$DLG_H" "$DLG_W" 2 \
        "nieuw" "Nieuwe opslag aanmaken (nieuwe VG + LV + mount)" \
        "uitbreiden" "Toevoegen aan bestaande Volume Group (type 8e)" \
        3>&1 1>&2 2>&3) || return 0
    if [[ "$mode" == "uitbreiden" ]]; then
        wizard_extend_existing "$disk"
        return 0
    fi

    local fstype
    fstype=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --ok-label "Kies" --cancel-label "Annuleren" --menu \
        "Welk filesystem wil je op ${disk}?" 15 72 3 \
        "ext4" "Algemeen, breed ondersteund (aanbevolen)" \
        "xfs"  "Standaard op RHEL, sterk bij grote volumes" \
        3>&1 1>&2 2>&3) || return 0

    local mountpoint
    mountpoint=$(input_box "Waar wil je de opslag koppelen (mountpoint)?\nDeze map wordt aangemaakt en blijft na reboot gemount." "/mnt/data") || return 0
    [[ -z "$mountpoint" ]] && mountpoint="/mnt/data"

    # Namen afleiden van het mountpoint (bijv. /mnt/data -> vg_data / lv_data).
    local base; base="$(basename "$mountpoint")"
    [[ -z "$base" || "$base" == "/" ]] && base="data"
    local vg="vg_${base}"
    local lv="lv_${base}"
    local part; part="$(part_name "$disk")"

    local mkfs_cmd="mkfs.ext4 -F"
    [[ "$fstype" == "xfs" ]] && mkfs_cmd="mkfs.xfs -f"

    # Duidelijke samenvatting in gewone taal.
    if ! dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --defaultno --yes-label "Ja, uitvoeren" --no-label "Annuleren" --yesno \
"Samenvatting van wat er gaat gebeuren:\n\n\
  Disk         : ${disk}   (wordt VOLLEDIG gewist)\n\
  Partitie     : ${part}   (type 8e / Linux LVM)\n\
  Volume Group : ${vg}\n\
  Logical Vol  : ${lv}   (gebruikt 100% van de disk)\n\
  Filesystem   : ${fstype}\n\
  Mountpoint   : ${mountpoint}\n\n\
Na afloop is ${mountpoint} direct bruikbaar en blijft het na een reboot\n\
automatisch gekoppeld (via /etc/fstab).\n\n\
Wil je dit uitvoeren?" "$DLG_H" "$DLG_W"; then
        msg_box "Geannuleerd. Er is niets gewijzigd."
        return 0
    fi

    local -a cmds=(
        "parted -s ${disk} mklabel gpt"
        "parted -s -a optimal ${disk} mkpart primary 0% 100%"
        "parted -s ${disk} set 1 lvm on"
        "partprobe ${disk} || udevadm settle"
        "pvcreate -y ${part}"
        "vgcreate ${vg} ${part}"
        "lvcreate -l 100%FREE -n ${lv} ${vg}"
        "${mkfs_cmd} /dev/${vg}/${lv}"
        "mkdir -p ${mountpoint}"
        "UUID=\$(blkid -s UUID -o value /dev/${vg}/${lv}); grep -q \"\$UUID\" /etc/fstab || echo \"UUID=\$UUID ${mountpoint} ${fstype} defaults 0 2\" >> /etc/fstab"
        "systemctl daemon-reload 2>/dev/null || true"
        "mount ${mountpoint}"
    )

    if exec_cmds "${cmds[@]}"; then
        msg_box "Klaar! ${mountpoint} is nu bruikbaar.\n\nControleer met:  df -h ${mountpoint}\nOf via menu-optie 'Layout tonen'."
    fi
}

# ---------------------------------------------------------------------------
# Hoofdmenu
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        local choice
        if ! choice=$(dialog --backtitle "$BACKTITLE" --colors --title "$APP_TITLE" --ok-label "Kies" --cancel-label "Afsluiten" --menu \
            "Distro: ${DISTRO_ID} | Kies een actie (optie 1 = nieuwe disk):" \
            "$DLG_H" "$DLG_W" "$LIST_H" \
            "1" "Nieuwe disk in gebruik nemen (WIZARD, aanbevolen)" \
            "2" "Layout tonen (disks, PV/VG/LV)" \
            "3" "Geavanceerd: Partitie aanmaken (type 8e / LVM)" \
            "4" "Geavanceerd: Physical Volume aanmaken (pvcreate)" \
            "5" "Geavanceerd: Volume Group aanmaken (vgcreate)" \
            "6" "Geavanceerd: Logical Volume aanmaken (lvcreate)" \
            "7" "Geavanceerd: Volume Group uitbreiden (vgextend)" \
            "8" "Geavanceerd: Logical Volume uitbreiden (lvextend)" \
            "9" "Geavanceerd: Formatteren + mounten (mkfs + fstab)" \
            "0" "Verwijderen (LV / VG / PV)" \
            "q" "Afsluiten" \
            3>&1 1>&2 2>&3); then
            # Niet-nul: gebruiker koos Annuleren/Esc, OF dialog gaf een fout.
            # Bij een fout staat de melding in $choice (via de fd-swap opgevangen).
            if [[ -n "$choice" ]]; then
                clear
                echo "SMUI: het menu kon niet worden getoond." >&2
                echo "dialog-melding: $choice" >&2
            fi
            break
        fi

        case "$choice" in
            1) action_new_disk_wizard ;;
            2) action_show_layout ;;
            3) action_create_partition ;;
            4) action_create_pv ;;
            5) action_create_vg ;;
            6) action_create_lv ;;
            7) action_extend_vg ;;
            8) action_extend_lv ;;
            9) action_format_mount ;;
            0) action_remove_menu ;;
            q) break ;;
            *) break ;;
        esac
    done
    clear
    echo "SMUI afgesloten."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
SMUI - Storage Management UI v${SMUI_VERSION}

Een nmtui-achtige TUI voor opslagbeheer (partities, LVM, filesystems) op
RHEL/Rocky/Alma en Ubuntu/Debian.

Gebruik:
  smui [optie]

Opties:
  (geen)          Start de interactieve TUI (vereist root).
  -h, --help      Toon deze hulp.
  -v, --version   Toon de versie.

Voorbeeld:
  sudo smui
EOF
}

main() {
    case "${1:-}" in
        -h|--help)    usage; exit 0 ;;
        -v|--version) echo "smui ${SMUI_VERSION}"; exit 0 ;;
        "" )          ;;
        * )           echo "Onbekende optie: $1" >&2; usage; exit 2 ;;
    esac

    require_root
    detect_distro
    ensure_deps
    ensure_fzf_optional
    setup_dialog_theme
    compute_dialog_size
    detect_root_disk
    main_menu
}

main "$@"
