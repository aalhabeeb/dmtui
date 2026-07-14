#!/usr/bin/env bash
#
# build.sh - Bouwt .deb en .rpm packages voor dmtui met nfpm.
#
# nfpm (https://nfpm.goreleaser.com) genereert uit één config beide formaten,
# zonder Debian- of RPM-buildtoolchain. Als nfpm niet in PATH staat, wordt een
# gepinde versie lokaal naar ./bin gedownload.
#
# Gebruik:
#   ./packaging/build.sh            # bouwt deb + rpm in ./dist
#   ./packaging/build.sh deb        # alleen deb
#   ./packaging/build.sh rpm        # alleen rpm
#
set -euo pipefail

NFPM_VERSION="2.41.0"

# Ga naar de repo-root (map boven dit script).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
cd "$REPO_ROOT"

CONFIG="packaging/nfpm.yaml"
OUT_DIR="dist"
BIN_DIR="bin"

# Versie uit dmtui.sh halen zodat pakket en script gelijk lopen.
DMTUI_VERSION="$(grep -oP 'DMTUI_VERSION="\K[^"]+' dmtui.sh | head -n1)"
[[ -z "${DMTUI_VERSION:-}" ]] && { echo "Kon DMTUI_VERSION niet uit dmtui.sh lezen." >&2; exit 1; }
export DMTUI_VERSION
echo "==> dmtui versie: ${DMTUI_VERSION}"

# --- nfpm beschikbaar maken -------------------------------------------------
find_nfpm() {
    if command -v nfpm >/dev/null 2>&1; then
        echo "nfpm"
    elif [[ -x "${BIN_DIR}/nfpm" ]]; then
        echo "${BIN_DIR}/nfpm"
    else
        echo ""
    fi
}

download_nfpm() {
    local os arch tar url
    os="Linux"
    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l)        arch="armv7" ;;
        *) echo "Niet-ondersteunde architectuur: $(uname -m)" >&2; exit 1 ;;
    esac
    tar="nfpm_${NFPM_VERSION}_${os}_${arch}.tar.gz"
    url="https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/${tar}"

    echo "==> nfpm niet gevonden; download v${NFPM_VERSION} (${arch})..."
    mkdir -p "${BIN_DIR}"
    local tmp; tmp="$(mktemp -d)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "${tmp}/${tar}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${tmp}/${tar}" "$url"
    else
        echo "curl of wget vereist om nfpm te downloaden." >&2; exit 1
    fi
    tar -xzf "${tmp}/${tar}" -C "${tmp}" nfpm
    mv "${tmp}/nfpm" "${BIN_DIR}/nfpm"
    chmod +x "${BIN_DIR}/nfpm"
    rm -rf "$tmp"
}

NFPM="$(find_nfpm)"
if [[ -z "$NFPM" ]]; then
    download_nfpm
    NFPM="${BIN_DIR}/nfpm"
fi
echo "==> nfpm: $("$NFPM" --version | head -n1)"

# --- Bouwen -----------------------------------------------------------------
mkdir -p "${OUT_DIR}"

build_one() {
    local fmt="$1"
    echo "==> Bouw ${fmt}..."
    "$NFPM" package --config "$CONFIG" --packager "$fmt" --target "${OUT_DIR}/"
}

targets=("${@:-}")
if [[ -z "${targets[*]// }" ]]; then
    targets=(deb rpm)
fi

for t in "${targets[@]}"; do
    case "$t" in
        deb|rpm) build_one "$t" ;;
        *) echo "Onbekend formaat: $t (gebruik deb of rpm)" >&2; exit 2 ;;
    esac
done

echo
echo "==> Klaar. Artefacten in ${OUT_DIR}/:"
ls -1 "${OUT_DIR}"/*.deb "${OUT_DIR}"/*.rpm 2>/dev/null || true
