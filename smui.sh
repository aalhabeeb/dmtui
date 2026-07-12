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
SMUI_VERSION="1.1.2"
APP_TITLE="SMUI - Storage Management UI v${SMUI_VERSION}"
PKG_MGR=""          # dnf | yum | apt-get
DISTRO_ID=""        # rhel | ubuntu | debian | ...
ROOT_DISK=""        # disk die de root-mount bevat (beschermd)

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
    # commando -> pakketnaam (whiptail zit in 'newt' op RHEL, 'whiptail' op Debian)
    local -a missing=()
    command -v whiptail >/dev/null 2>&1 || missing+=("whiptail")
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
            whiptail)
                if [[ "$PKG_MGR" == "apt-get" ]]; then pkgs+=("whiptail"); else pkgs+=("newt"); fi
                ;;
            lvm2)      pkgs+=("lvm2") ;;
            parted)    pkgs+=("parted") ;;
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

    command -v whiptail >/dev/null 2>&1 || die "whiptail installeren is mislukt."
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
# Whiptail-wrappers
# ---------------------------------------------------------------------------
# Bepaalt veilige dialooggroottes op basis van de werkelijke terminalgrootte,
# zodat vensters nooit groter zijn dan de terminal (anders faalt whiptail).
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

    # Lijsthoogte ruim binnen de box houden: whiptail heeft ~12 regels nodig voor
    # titel, prompttekst, knoppen en randen. Te grote lijst => whiptail faalt.
    LIST_H=$(( DLG_H - 12 ))
    if (( LIST_H < 3 )); then LIST_H=3; fi

    if [[ "${SMUI_DEBUG:-0}" == "1" ]]; then
        echo "SMUI_DEBUG: term=${lines}x${cols}  box=${DLG_H}x${DLG_W}  list=${LIST_H}" >&2
    fi
}

msg_box() {
    whiptail --title "$APP_TITLE" --msgbox "$1" "$DLG_H" "$DLG_W"
}

info_scroll() {
    # Toon lange tekst scrollbaar.
    whiptail --title "$APP_TITLE" --scrolltext --msgbox "$1" "$DLG_H" "$DLG_W"
}

confirm_box() {
    # Retourneert 0 (ja) of 1 (nee). Standaard op 'nee' voor veiligheid.
    whiptail --title "$APP_TITLE" --defaultno --yesno "$1" "$DLG_H" "$DLG_W"
}

input_box() {
    # $1 = prompt, $2 = default. Print resultaat op stdout, of niets bij annuleren.
    local result
    result=$(whiptail --title "$APP_TITLE" --inputbox "$1" 11 "$DLG_W" "${2:-}" 3>&1 1>&2 2>&3) || return 1
    printf '%s' "$result"
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

    whiptail --title "$APP_TITLE" --menu "$prompt" "$DLG_H" "$DLG_W" "$LIST_H" "${items[@]}" 3>&1 1>&2 2>&3
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

    whiptail --title "$APP_TITLE" --menu "$prompt" "$DLG_H" "$DLG_W" "$LIST_H" "${items[@]}" 3>&1 1>&2 2>&3
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
    whiptail --title "$APP_TITLE" --menu "$prompt" "$DLG_H" "$DLG_W" "$LIST_H" "${items[@]}" 3>&1 1>&2 2>&3
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
    whiptail --title "$APP_TITLE" --menu "$prompt" "$DLG_H" "$DLG_W" "$LIST_H" "${items[@]}" 3>&1 1>&2 2>&3
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
    whiptail --title "$APP_TITLE" --menu "$prompt" "$DLG_H" "$DLG_W" "$LIST_H" "${items[@]}" 3>&1 1>&2 2>&3
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
    label=$(whiptail --title "$APP_TITLE" --menu \
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
    fstype=$(whiptail --title "$APP_TITLE" --menu "Kies het filesystem voor ${dev}:" 16 70 4 \
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
    out+="=== BLOK-APPARATEN (lsblk) ===\n"
    out+="$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>&1)\n\n"
    out+="=== PHYSICAL VOLUMES (pvs) ===\n"
    out+="$(pvs 2>&1 || echo 'geen')\n\n"
    out+="=== VOLUME GROUPS (vgs) ===\n"
    out+="$(vgs 2>&1 || echo 'geen')\n\n"
    out+="=== LOGICAL VOLUMES (lvs) ===\n"
    out+="$(lvs 2>&1 || echo 'geen')\n"
    info_scroll "$out"
}

# ---------------------------------------------------------------------------
# Feature: verwijderen (LV / VG / PV)
# ---------------------------------------------------------------------------
action_remove_menu() {
    local choice
    choice=$(whiptail --title "$APP_TITLE" --menu "Wat wil je verwijderen?" 16 70 4 \
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
# Begeleide flow: disk kiezen -> partitie (8e) -> PV -> VG -> LV -> filesystem
# -> mounten. Slimme standaardwaarden en één duidelijke samenvatting vooraf.
action_new_disk_wizard() {
    msg_box "WIZARD - nieuwe disk in gebruik nemen\n\nDeze wizard neemt een lege disk in een keer volledig in gebruik:\npartitie (type 8e) -> LVM -> filesystem -> mounten.\n\nKies zo een disk met status 'LEEG - nieuw'.\nDe systeemdisk wordt automatisch beschermd."

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

    local fstype
    fstype=$(whiptail --title "$APP_TITLE" --menu \
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
    if ! whiptail --title "$APP_TITLE" --yesno \
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
        choice=$(whiptail --title "$APP_TITLE" --menu \
            "Kies een actie (optie 1 = nieuwe disk in gebruik nemen):" \
            "$DLG_H" "$DLG_W" "$LIST_H" \
            "1" ">> Nieuwe disk in gebruik nemen (begeleide wizard)" \
            "2" "Layout tonen (disks, PV/VG/LV)" \
            "3" "--- Geavanceerd: Partitie aanmaken (type 8e / LVM)" \
            "4" "Geavanceerd: Physical Volume aanmaken (pvcreate)" \
            "5" "Geavanceerd: Volume Group aanmaken (vgcreate)" \
            "6" "Geavanceerd: Logical Volume aanmaken (lvcreate)" \
            "7" "Geavanceerd: Volume Group uitbreiden (vgextend)" \
            "8" "Geavanceerd: Logical Volume uitbreiden (lvextend)" \
            "9" "Geavanceerd: Formatteren + mounten (mkfs + fstab)" \
            "0" "Verwijderen (LV / VG / PV)" \
            "q" "Afsluiten" \
            3>&1 1>&2 2>&3) || break

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
    compute_dialog_size
    detect_root_disk
    main_menu
}

main "$@"
