#!/usr/bin/env bash
# quench-remove.sh — undo everything quench-setup.sh did.
#
#   sudo bash scripts/quench-remove.sh              # remove driver + app
#   sudo bash scripts/quench-remove.sh --keep-app   # remove driver only
#                                       (use this at kernel 7.3+)
#
# Stopping the daemon is safe by design: it returns both fans to Acer's own
# firmware control on the way out.

set -euo pipefail

DKMS_NAME="acer-wmi-anv15"
DKMS_VER="7.2.stopgap.1"
KEEP_APP=false
[[ "${1:-}" == "--keep-app" ]] && KEEP_APP=true

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

step "Stopping the daemon (fans return to firmware control)"
if systemctl is-active --quiet quench 2>/dev/null; then
    systemctl disable --now quench
    info "stopped and disabled"
else
    info "not running"
fi

step "Removing the stopgap driver"
if dkms status -m "$DKMS_NAME" -v "$DKMS_VER" 2>/dev/null | grep -q .; then
    dkms remove "$DKMS_NAME/$DKMS_VER" --all || true
    info "dkms module removed"
else
    info "not installed"
fi
rm -rf "/usr/src/${DKMS_NAME}-${DKMS_VER}"

if lsmod | grep -q '^acer_wmi '; then
    modprobe -r acer_wmi || true
fi
modprobe acer_wmi 2>/dev/null || true
info "in-tree acer_wmi driver active again (or after next reboot)"

if [[ $KEEP_APP == true ]]; then
    info "--keep-app given: leaving quench binaries/service in place"
    exit 0
fi

step "Removing Quench"
rm -f /usr/bin/quench-daemon /usr/bin/quench /usr/bin/quench-gui
rm -f /usr/lib/systemd/system/quench.service
rm -f /usr/lib/sysusers.d/quench.conf
rm -f /usr/lib/tmpfiles.d/quench.conf
rm -f /usr/share/applications/quench-gui.desktop
rm -f /usr/share/icons/hicolor/512x512/apps/quench.png
systemctl daemon-reload
info "removed binaries and service (config kept at /etc/quench if present)"

info "note: the 'quench' group was left in place; remove with 'groupdel quench' if you want"
printf '\nDone. Fans are under Acer firmware control again.\n'
