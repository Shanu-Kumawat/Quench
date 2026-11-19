<h1 align="center">Quench</h1>

<p align="center">
  <img src="packaging/quench.svg" alt="Quench mascot: the fire-quenching salamander" width="200">
</p>

<p align="center">
  <strong>Thermal and fan management for Linux laptops.</strong><br>
  Custom fan curves, layered thermal failsafes, performance profiles, live<br>
  monitoring.<br>
  <em>Legend says the salamander lives in fire unharmed.</em>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#device-support">Device support</a> ·
  <a href="COMPATIBILITY.md">Compatibility</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="docs/SAFETY.md">Safety</a>
</p>

<p align="center">
  <img src="docs/img/dashboard.png" alt="Quench dashboard" width="880">
</p>

Built driver-first: each laptop family gets a small, honest driver, and the
safety policy around it is hardware-agnostic. Quench never writes to the
Embedded Controller, hands control back to the firmware when temperatures
cross critical limits, and survives firmware overrides, suspend/resume, and
crashes by design. See [Safety](docs/SAFETY.md).

## Screenshots

| Fans & curves | Profiles |
|---|---|
| ![Fan control](docs/img/fan-control.png) | ![Profiles](docs/img/profiles.png) |

## Device support

Quench rides on the **mainline kernel `acer-wmi` driver**, so compatibility
follows the kernel's own quirk table. The full model-by-model list with
support levels lives in [**COMPATIBILITY.md**](COMPATIBILITY.md). In short:

| Level | Models |
|---|---|
| ✅ **Full, hardware-tested** | Acer Nitro V 15 (ANV15-51) |
| 🔶 Full, expected but untested | Nitro AN515-58 / AN16-41, Predator PH16-72, Helios Neo 16 (PHN16-72), PT14-51 |
| 🔶 Monitor + profiles | Predator PHN16-71 / PH16-71 / PH18-71 (kernel exposes no pwm yet), other 2021+ Nitro/Predator via `predator_v4=1` |
| 🔶 Driver wanted | ASUS, HP, ThinkPads; see [the driver guide](docs/DRIVERS.md) |

Getting a laptop supported is designed to be a small, testable contribution:
read [`docs/DRIVERS.md`](docs/DRIVERS.md). "Full, expected" models need
exactly one thing we can't do ourselves: someone running
`quench doctor` + the probe from the driver guide on real hardware and
reporting back.

## How it works

```
crates/
├── quench-core     # pure policy: curves, hysteresis, failsafes, config
├── quench-proto    # versioned IPC over a Unix socket (CLI + GUI clients)
├── quench-backend  # device drivers (drivers/ registry) + hwmon + NVML
├── quench-daemon   # control loop, failsafes, IPC server (runs as root)
├── quench-cli      # `quench` command-line client
└── quench-gui      # GPUI desktop client
```

- **Fan curves:** per-fan piecewise-linear temperature→duty curves with
  hysteresis (no fan chatter), duty floors, and battery variants
  (`balanced-battery` is picked automatically on battery).
- **Modes:** firmware auto, fixed manual %, or curve, per fan. Manual duty
  is re-asserted every 2 s so firmware overrides don't stick; drift is
  detected and alerted.
- **Failsafes:** the warn threshold forces 100% duty; the crit threshold hands the
  fan back to the firmware's own controller and latches until temperatures
  recover. Curves are validated before use; 0-RPM above configurable temps is
  impossible.
- **Suspend/resume:** fans restored to auto before sleep; writes held for a
  grace window after resume while the EC reinitializes.
- **Profiles:** platform profiles when the firmware offers them, or full
  hands-off (`[platform] active = "none"`) to coexist with
  power-profiles-daemon.
- **No EC writes, ever.** Full reasoning in [`docs/HARDWARE.md`](docs/HARDWARE.md).

## Install

### Prebuilt release (x86_64 Linux)

Grab `quench-v0.2.0-x86_64-linux.tar.gz` from the
[releases page](https://github.com/Shanu-Kumawat/quench/releases), unpack it,
then as root:

```sh
install -m755 quench-0.2.0/quench-daemon quench-0.2.0/quench quench-0.2.0/quench-gui -t /usr/bin/
install -Dm644 quench-0.2.0/quench.service -t /usr/lib/systemd/system/
install -Dm644 quench-0.2.0/sysusers.conf /usr/lib/sysusers.d/quench.conf
install -Dm644 quench-0.2.0/tmpfiles.conf /usr/lib/tmpfiles.d/quench.conf
groupadd quench 2>/dev/null; usermod -aG quench "$USER"   # relogin needed
systemctl daemon-reload && systemctl enable --now quench
```

Then set your config (`/etc/quench/quench.toml`, see [Quick start](#quick-start))
and run `quench doctor`.

### From source

```sh
git clone https://github.com/Shanu-Kumawat/quench.git
cd quench
cargo build --release -p quench-daemon -p quench-cli -p quench-gui
sudo bash scripts/quench-setup.sh   # service + group + config; idempotent
# undo: sudo bash scripts/quench-remove.sh   (--keep-app keeps the app)
```

The setup script also installs the stopgap DKMS module when your kernel
predates the in-tree acer-wmi quirk (ANV15-51 on kernel 7.2). Arch users:
PKGBUILDs are in [`packaging/`](packaging/) (AUR packages planned).

### Check what your machine supports

```sh
quench doctor   # driver match, capability level, sensors, profiles; no root needed
```

## Quick start

```sh
quench status                  # snapshot: temps, fans, failsafe phase
quench monitor                 # live view
quench fan list                # fans your driver reports
quench fan set cpu curve balanced
quench fan set cpu manual 55   # percent duty
quench fan set cpu auto        # back to firmware control
quench profile list
quench-gui                     # desktop app (join the `quench` group first)
```

Configuration lives at `/etc/quench/quench.toml` (strictly validated; see
[`examples/quench.toml`](examples/quench.toml)). Runtime changes made
from the GUI/CLI persist across daemon restarts.

## FAQ

**I want zero background activity. How do I turn Quench off?**

```sh
sudo systemctl stop quench      # and: disable, to keep it off across reboots
```

On shutdown the daemon returns every fan to the firmware's automatic
controller, so your laptop simply reverts to stock fan behavior. Nothing is
left stuck at the last commanded duty. Start it again with
`sudo systemctl start quench`.

## Documentation

- [`docs/SAFETY.md`](docs/SAFETY.md): the failsafe design and the things
  Quench deliberately never does
- [`docs/DRIVERS.md`](docs/DRIVERS.md): adding support for a new laptop
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): crates, IPC, control loop
- [`docs/HARDWARE.md`](docs/HARDWARE.md): ANV15-51 findings (WMI vs EC,
  profile semantics, firmware quirks

## Contributing

Bug reports, new device drivers, and curve/profile experience reports are all
are welcome, see [`CONTRIBUTING.md`](CONTRIBUTING.md). For new laptops,
[`docs/DRIVERS.md`](docs/DRIVERS.md) walks through probing your hardware and
writing a driver in ~150 lines, with tests that need no hardware.

## License

MIT, see [LICENSE](LICENSE). The stopgap kernel module in
[`driver/acer-wmi-anv15/`](driver/acer-wmi-anv15/) is a patched copy of
GPL-2.0 kernel source and remains GPL-2.0-only.
