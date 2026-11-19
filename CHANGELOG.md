# Changelog

All notable changes to Quench are documented here. The project was known as
Thermite before v0.2.0.

## 0.2.0 (2026-11-19)

The release where Quench grew up: renamed, silent, polished, and packaged.

### Changed

- Renamed the project from Thermite to Quench: crates, binaries
  (`quench-daemon`, `quench`, `quench-gui`), paths (`/etc/quench`,
  `/var/lib/quench`, `/run/quench/quench.sock`), group, systemd unit, and the
  repository (now [Shanu-Kumawat/quench](https://github.com/Shanu-Kumawat/quench))
- New mascot: the fire-quenching salamander, on a rounded dark tile
  (`packaging/quench.svg`, scalable)
- README redesigned: mascot header, quick links, refreshed screenshots

### Fixed

- The hands-off daemon is now silent. Telemetry reads on the acer-wmi
  interface are WMI/EC round-trips (~5 ms each) that stall CPUs, and at the
  old read cadence they were audible as Bluetooth audio jitter. pwm readbacks
  now happen only for fans under Quench control, fans handed back to auto are
  drift-corrected instead of timer-reasserted, and profile readbacks refresh
  once a minute. Hands-off steady state performs zero WMI traffic
- Fan curves under manual control still re-assert every 2 s by design (the
  firmware reverts manual settings; every fan tool on this hardware has the
  same physics)

### Added

- Prebuilt x86_64 Linux release tarballs (daemon, CLI, GUI, unit files) on
  every version tag, with SHA-256 checksums
- This changelog

### Docs

- CONTRIBUTING, ARCHITECTURE, VERIFICATION, HARDWARE, and SAFETY refreshed
  for the new naming and for first-time contributors; hardware verification
  procedure now linked from the compatibility matrix

## 0.1.0 (2026-10-26)

- Initial public release: acer-wmi hwmon driver adapter, per-fan curves with
  hysteresis, layered thermal failsafes, platform profiles with PPD
  coexistence, suspend/resume handling, Unix-socket IPC, CLI, GPUI desktop
  GUI, systemd packaging, CI
