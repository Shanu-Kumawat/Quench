#!/usr/bin/env bash
# quench-setup.sh — one-shot installer for Quench on the Acer Nitro V 15
# (ANV15-51), kernel 7.2.
#
# What it does:
#   1. Preflight checks (binaries built, dkms + kernel headers, Secure Boot)
#   2. Installs the stopgap acer-wmi driver (DKMS, auto-rebuilds on kernel
#      updates) and reloads it
#   3. Installs quench-daemon / quench / quench-gui + systemd unit
#   4. Creates the `quench` group and adds the invoking user to it
#   5. Enables + starts quench.service
#   6. Verifies: capability should read "full fan control"
#
# Undo everything:  sudo bash scripts/quench-remove.sh
#
# NOTE: remove the driver when kernel >= 7.3 ships the quirk in-tree
# (`quench doctor` showing "full" without this module is your signal).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DKMS_NAME="acer-wmi-anv15"
DKMS_VER="7.2.stopgap.1"
INVOKING_USER="${SUDO_USER:-$USER}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
warn()  { printf '\033[1;33m    WARNING: %s\033[0m\n' "$*"; }
die()   { printf '\n\033[1;31mERROR: %s\033[0m\n\n' "$*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

# ---------------------------------------------------------------- 1. checks
step "1/6  Checking prerequisites"

for bin in quench-daemon quench quench-gui; do
    [[ -x "$REPO_ROOT/target/release/$bin" ]] || die "missing $REPO_ROOT/target/release/$bin
    Run this first:  cargo build --release -p quench-daemon -p quench-cli -p quench-gui"
done
info "release binaries: ok"

command -v dkms >/dev/null || die "dkms is not installed. Run: sudo pacman -S dkms"
info "dkms: ok"

KBUILD="/lib/modules/$(uname -r)/build"
[[ -d $KBUILD ]] || die "kernel headers for $(uname -r) are missing. Run: sudo pacman -S linux-headers"
info "kernel headers: ok"

if command -v mokutil >/dev/null; then
    if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        warn "Secure Boot is ON — the driver module is unsigned and will likely be refused."
        warn "Disable Secure Boot in the BIOS, or enroll a MOK key, then re-run this script."
        die "cannot continue with Secure Boot enforcing unsigned modules"
    fi
    info "secure boot: off"
else
    info "mokutil not found — skipping Secure Boot check (fine if it's disabled in BIOS)"
fi

# ---------------------------------------------------------------- 2. driver
step "2/6  Installing the stopgap acer-wmi driver (DKMS)"

if dkms status -m "$DKMS_NAME" -v "$DKMS_VER" 2>/dev/null | grep -q ': installed'; then
    info "already installed for this kernel — skipping build"
else
    [[ -d "/usr/src/${DKMS_NAME}-${DKMS_VER}" ]] || true
    rm -rf "/usr/src/${DKMS_NAME}-${DKMS_VER}"
    mkdir -p "/usr/src/${DKMS_NAME}-${DKMS_VER}"
    cp "$REPO_ROOT/driver/acer-wmi-anv15/acer-wmi.c" \
       "$REPO_ROOT/driver/acer-wmi-anv15/Makefile" \
       "$REPO_ROOT/driver/acer-wmi-anv15/dkms.conf" \
       "/usr/src/${DKMS_NAME}-${DKMS_VER}/"
    dkms add -m "$DKMS_NAME" -v "$DKMS_VER" 2>/dev/null || true
    dkms build -m "$DKMS_NAME" -v "$DKMS_VER"
    dkms install -m "$DKMS_NAME" -v "$DKMS_VER"
    info "driver installed (will auto-rebuild on kernel updates)"
fi

step "      Swapping in the patched driver (fans stay untouched)"
# The first unload/reload after replacing the module file can silently
# no-op on some setups; verify the hwmon appeared and retry a few times.
ACER_HWMON=""
find_acer_hwmon() {
    for d in /sys/class/hwmon/hwmon*; do
        case $(cat "$d/name" 2>/dev/null || true) in
            acer|acer_wmi) echo "$d"; return ;;
        esac
    done
    true
}
for attempt in 1 2 3; do
    if lsmod | grep -q '^acer_wmi '; then
        modprobe -r acer_wmi || warn "could not unload acer_wmi (in use?)"
    fi
    modprobe acer_wmi
    sleep 2
    ACER_HWMON="$(find_acer_hwmon)"
    [[ -n $ACER_HWMON ]] && break
    warn "hwmon did not appear after swap attempt $attempt — retrying"
done
[[ -n $ACER_HWMON ]] || die "acer_wmi loaded but no hwmon appeared.
Check: dmesg | grep -i acer_wmi (last 30 lines)"
info "hwmon found: $ACER_HWMON"
info "fan RPMs: $(cat "$ACER_HWMON"/fan*_input 2>/dev/null | tr '\n' ' ')"

if [[ -e $ACER_HWMON/pwm1_enable ]]; then
    info "manual fan control (pwm): available"
else
    warn "pwm control NOT exposed — Quench will run in monitor+profiles mode only."
    warn "Check 'dmesg | grep -i acer_wmi' and whether the machine actually matched the quirk."
fi

# ---------------------------------------------------------------- 3. install
step "3/6  Installing Quench"

install -Dm755 "$REPO_ROOT/target/release/quench-daemon" /usr/bin/quench-daemon
install -Dm755 "$REPO_ROOT/target/release/quench"        /usr/bin/quench
install -Dm755 "$REPO_ROOT/target/release/quench-gui"    /usr/bin/quench-gui
install -Dm644 "$REPO_ROOT/packaging/quench.service" /usr/lib/systemd/system/quench.service
install -Dm644 "$REPO_ROOT/packaging/sysusers.conf"    /usr/lib/sysusers.d/quench.conf
install -Dm644 "$REPO_ROOT/packaging/tmpfiles.conf"    /usr/lib/tmpfiles.d/quench.conf
# Desktop launcher (app grid / wofi / rofi entry for the GUI)
install -Dm644 "$REPO_ROOT/packaging/quench-gui.desktop" /usr/share/applications/quench-gui.desktop
install -Dm644 "$REPO_ROOT/packaging/quench.png" /usr/share/icons/hicolor/512x512/apps/quench.png
systemd-sysusers /usr/lib/sysusers.d/quench.conf
systemd-tmpfiles --create /usr/lib/tmpfiles.d/quench.conf
info "binaries, service, users and runtime dirs installed"

if [[ -f /etc/quench/quench.toml ]]; then
    info "config already exists at /etc/quench/quench.toml — leaving it alone"
else
    install -Dm600 "$REPO_ROOT/examples/quench.toml" /etc/quench/quench.toml
    info "installed example config to /etc/quench/quench.toml (safe defaults)"
fi

# ---------------------------------------------------------------- 4. group
step "4/6  Granting your user access"

if [[ -n $INVOKING_USER && $INVOKING_USER != root ]]; then
    if id -nG "$INVOKING_USER" | grep -qw quench; then
        info "$INVOKING_USER is already in the quench group"
    else
        usermod -aG quench "$INVOKING_USER"
        info "added $INVOKING_USER to the quench group (takes effect at next login)"
    fi
else
    warn "could not determine invoking user — add yourself later with: sudo usermod -aG quench \$USER"
fi

# ---------------------------------------------------------------- 5. service
step "5/6  Starting the daemon"

systemctl daemon-reload
systemctl enable --now quench
sleep 2
systemctl is-active --quiet quench || die "quench.service is not running.
Check: journalctl -u quench -b --no-pager | tail -30"
info "quench.service is active and enabled at boot"

# ---------------------------------------------------------------- 6. verify
step "6/6  Verifying"

quench doctor | sed 's/^/    /'
echo
if quench doctor 2>/dev/null | grep -q 'full fan control'; then
    printf '\033[1;32m    All good: full fan control is live.\033[0m\n'
else
    warn "capability did not read 'full fan control' — see the doctor output above."
fi

cat <<EOF

------------------------------------------------------------------------
 Done. Try it out:

     quench status                      # snapshot of temps/fans/modes
     quench fan cpu curve balanced      # put the CPU fan on a curve
     quench monitor                     # live view (Ctrl-C to stop)
     quench-gui                         # desktop app (after next login)

 Suspend test (recommended once):
     systemctl suspend
     journalctl -u quench -b --since "5 min ago"

 Undo everything:
     sudo bash "$REPO_ROOT/scripts/quench-remove.sh"

 When kernel >= 7.3 arrives, remove the driver module
 (quench doctor will still say "full" without it):
     sudo bash "$REPO_ROOT/scripts/quench-remove.sh --keep-app"

 Emergency, any time: return all fans to Acer's own control:
     for f in /sys/class/hwmon/hwmon*/pwm[12]_enable; do echo 2 | sudo tee \$f; done
------------------------------------------------------------------------
EOF
