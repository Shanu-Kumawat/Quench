---
name: Bug report
about: Something misbehaves
title: ""
labels: bug
---

**What happened:**

**What you expected:**

**Machine:** laptop model / kernel / distro / Quench version
(`quench status` first line)

**Logs:**

```
journalctl -u quench -b --no-pager | tail -50
```

**Config** (`/etc/quench/quench.toml`, if relevant — no secrets there,
but feel free to trim):

**Failsafe involved?** If fans went to 100% or control returned to
firmware, temperatures at the time (`quench status`):
