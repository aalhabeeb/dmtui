# dmtui als container-image, voor gebruik als privileged pod op een Kubernetes-node
# (bijv. Talos, dat geen shell of package manager heeft). Zie README → "Als pod".
#
#   kubectl debug node/<node> -n kube-system -it --profile=sysadmin \
#     --image=ghcr.io/aalhabeeb/dmtui:latest
FROM debian:13-slim

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      dialog lvm2 parted util-linux fdisk cloud-guest-utils fzf ncurses-bin \
 && rm -rf /var/lib/apt/lists/* \
 && for c in dialog lvm pvcreate parted lsblk blkid findmnt wipefs growpart fzf tput; do \
      command -v "$c" >/dev/null || { echo "ontbreekt: $c" >&2; exit 1; }; \
    done

# LVM in een container: geen udev, geen dmeventd, geen devices-file.
COPY packaging/container/lvm.conf /etc/dmtui/lvm/lvm.conf
RUN mkdir -p /etc/dmtui/lvm/backup /etc/dmtui/lvm/archive

COPY dmtui.sh /usr/bin/dmtui
RUN chmod 0755 /usr/bin/dmtui

ENV DMTUI_MODE=k8s \
    LVM_SYSTEM_DIR=/etc/dmtui/lvm \
    DM_DISABLE_UDEV=1 \
    TERM=xterm-256color \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/dmtui"]
