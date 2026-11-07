# WCN7850 / ath12k: Wi‑Fi transmit throughput collapses on the Steam Frame (~8 Mbit/s vs ~860 Mbit/s for another client on the same AP), breaking Remote Play / Moonlight streaming

> Formatted as a bug report for the SteamOS issue tracker. It is self‑contained and
> reproducible; the `repro/` scripts and a captured run in `results/observed.txt` are
> included. Happy to move it to whichever tracker the Frame’s Wi‑Fi stack belongs in.

## Summary

On the Steam Frame, the Wi‑Fi **transmit** path stalls under sustained load. A client
on the **same access point** transmits at ~860 Mbit/s to a wired host; the Frame, on
that same AP to that same host, manages only **~8 Mbit/s** and its `sendto()` calls
block because the transmit path cannot drain. Receive is healthy (200–400 Mbit/s). The
stall is the reason Remote Play / Moonlight streaming to the headset stutters.

The failure is isolated to the Frame itself (a same‑AP control client is fine), and
within the Frame it is below the driver: the `ath12k` host driver hands frames off
cleanly with zero transmit errors logged, and the firmware’s own counters show large,
climbing retry/timeout activity and a hardware‑scheduler anomaly. Our reading is a
**WCN7850 firmware transmit‑engine problem** (rate control / retries / hardware
scheduler), not a driver, RF, router, or environment problem — but we’ve included
everything needed for you to confirm or correct that.

## Impact

Game streaming to the headset (Steam Remote Play and Moonlight) stutters badly. Because
the Frame must send 802.11 Block‑Acks for the received video, a broken transmit path
degrades the **downlink** video too (the AP stalls waiting for BAs and retransmits),
not just the small uplink. This is the single biggest blocker to using the Frame as a
PC‑VR / streaming display over Wi‑Fi.

## Environment

| | |
|---|---|
| Device | Steam Frame (SteamOS `holo`, aarch64) |
| OS | SteamOS 0.5.7, BUILD_ID `20261103.6153824` |
| Kernel | `7.2.0-g9a8c8ea46950` |
| Driver | `ath12k.ko`, license `Dual BSD/GPL`, `intree: Y` (dmesg name `ath12k_wifi7_pci`) |
| Firmware | `fw_version 0x110a0012`, build `2025-08-20`, `QC_IMAGE_VERSION_STRING=WLAN.IOE_HMT.1.1-00018-QCAHMTSWPL_V1.0_V2.0_SILICONZ-1` |
| Chip | WCN785x Wi‑Fi 7 2x2 [FastConnect 7800] `[17cb:1107]` rev 01; `chip_id 0x2`, `soc_id 0x40170200` |
| Bus | PCIe root `SM8550/SM8650 [17cb:0113]`; link negotiated **Gen2 x1** (downgraded from the x2/8GT cap — not the bottleneck, RX saturates fine) |
| Link under test | NETGEAR RAX41 AP (SSID redacted), ch149 / 5745 MHz, 80 MHz HE; Frame signal a steady −60…−62 dBm |

## TL;DR reproduction

Same AP, same wired target, same tool. One client is the Frame, the other is any
healthy laptop on the same AP:

```
# on the Frame:
python3 udpflood.py <wired-host-ip> 9 12      # -> ~8 Mbit/s, sendto() blocks
# on a laptop on the SAME AP:
python3 udpflood.py <wired-host-ip> 9 12      # -> ~860 Mbit/s
```

A ~100× transmit gap on an identical path. `repro/run-comparison.sh` automates it.

## Full reproduction

Topology: the Frame and a control laptop both associate to the **same AP/BSSID**; the
flood/ping **target is a wired host on the same LAN** (so Frame→target is a single
wireless hop and the wired host is never the bottleneck).

1. **Baseline, confirm receive is fine.** Stream or `iperf3`/large download *to* the
   Frame — it receives at 200–400 Mbit/s. The problem is transmit‑only.
2. **Transmit flood from the Frame:**
   ```
   python3 repro/udpflood.py <wired-host> 9 12
   # concurrently, in another shell on the Frame:
   bash repro/latency-probe.sh <wired-host>
   ```
   Observed: ~8–9 Mbit/s achieved (two runs), `elapsed` exceeds the requested 12 s
   because `sendto()` blocks; latency during it p50≈140–160 ms, max≈640–690 ms.
3. **Same flood from a control client on the same AP** → ~860 Mbit/s. This is the
   control that isolates the fault to the Frame.
4. **Read the firmware counters** on the Frame (root):
   ```
   bash repro/read-ath12k-fw-stats.sh
   ```

See `results/observed.txt` for a full captured run with exact numbers.

## Results

| client (same AP → same wired host) | UDP transmit achieved | latency during its flood |
|---|---|---|
| **Steam Frame**, run 1 | **8 Mbit/s** | p50 162 / p99 540 / max 640 ms |
| **Steam Frame**, run 2 | **9 Mbit/s** (`sendto` blocked) | p50 137 / p99 562 / max 687 ms |
| control laptop | **861 Mbit/s** | p50 96 / p99 297 / max 391 ms |

**Caveat we want to be upfront about:** the absolute latency figures are inflated by
bufferbloat on the path — the control laptop is elevated too — so we do **not** lean on
them. The clean, decisive signal is the **throughput gap (≈8 vs ≈861 Mbit/s)**.

## Evidence it is the Frame’s transmit, not the AP / path / environment

The same‑AP control (861 Mbit/s) already exonerates the router and the path. In
addition, each of these was tested and ruled out:

- **Signal / antenna:** −60…−62 dBm, both chains balanced (`[-65,-62]`), AP ACKs
  −59…−68 dBm, both TX chains active. Receive runs 200–400 Mbit/s on the same radio.
- **Channel:** survey ~10% busy, noise −96 dBm, single BSS. Clear air.
- **Thermal:** 30–37 °C across all sensors; stall is immediate, not heat‑driven.
- **PCIe bandwidth:** Gen2 x1, zero AER errors; RX saturates it, so it is not the cap.
- **DFS:** ch149 (UNII‑3) is non‑DFS — no radar‑driven interruptions.
- **Wi‑Fi power save:** off.
- **Host CPU / scheduler:** loopback ping on the Frame stays <0.3 ms *even under full
  transmit load*, while over‑air latency spikes — so the jitter is not the Frame’s CPU
  or kernel, and the latency numbers are not a measurement artifact.
- **Bluetooth coexistence:** blocking Bluetooth entirely did not change the behaviour.
- **Background scanning / roaming:** none configured, single BSSID, spikes too frequent
  to be scans.
- **PCIe ASPM / CPU governor / deep‑idle:** switching all to “performance” changed
  nothing.

## Firmware‑internal signals

From `ath12k` debugfs on the Frame (lifetime counters, ~30 h uptime):

- `pdev_stats`: `Excessive retries ≈ 1.39M`, `Dropped due to SW retries ≈ 1.32M`,
  `TX timeout ≈ 0.96M`, `PDEV continuous xretry ≈ 40`.
- `htt_stats` type 5 (`HTT_HW_STATS_PDEV_ERRS`): **`hwsch_misaligned_offset_received ≈
  1.47M`**, **`hwsch_reset_count = 48`** — the hardware TX scheduler is receiving
  misaligned offsets en masse and has reset itself dozens of times.
- `htt_stats` type 12 (`HTT_TX_SELFGEN`): `su_bar = 1343` — the firmware is repeatedly
  issuing Block‑Ack‑Requests (BA recovery), consistent with a struggling TX path.

These climb under transmit load. We suspect `hwsch_misaligned_offset_received` /
`hwsch_reset_count` are the most diagnostic — any guidance on what they indicate would
help.

## Localization: driver vs firmware

- Over 30 h of uptime including every load test, the `ath12k` driver logged **32 lines
  total and zero transmit errors** — no ring‑full, no descriptor exhaustion, no
  firmware recovery. With full transmit debug (`debug_mask = DP_TX|DATA|WMI|MAC|HAL|CE`)
  during a transmit flood, the driver emitted thousands of lines, **all clean RX**, not
  one TX fault. The host is handing frames off and seeing successful completions.
- `iw dev wlan0 set bitrates he-mcs-5 1:4 2:4` is **rejected** — the host cannot pin
  the rate; rate selection is firmware‑owned.

Taken together: the host/driver layer is not where the frames fail; the transmit
rate‑control / retry / scheduling that is failing lives in the WCN7850 firmware.

## Questions for the maintainers

1. Is this a known transmit‑stall / rate‑control issue on WCN7850 with the
   `WLAN.IOE_HMT…SILICONZ` firmware line, and is a newer firmware image available to
   try on the Frame?
2. What do `hwsch_misaligned_offset_received` and `hwsch_reset_count` indicate, and are
   they expected to be nonzero at this scale?
3. Are there driver‑side feature toggles (HE/EHT features, aggregation, MU/OFDMA,
   RTS/CTS protection) that are known to trip or avoid this, that we could test from
   the current driver without a firmware change?
4. Would you like additional captures — full `htt_stats` dumps, a firmware coredump
   (`CONFIG_ATH12K_COREDUMP=y` is set), `trace-cmd`, or a packet capture from the AP?

## Methodology note

This write‑up is the end of a from‑scratch root‑cause pass with full access to the
Frame, the router, a wired host, and a control client: throughput and latency
instrumentation, firmware‑stat deltas under load, driver‑log capture, same‑AP control,
and elimination of each alternative above. We do a lot of low‑level
software/systems work and would be glad to help investigate further or test candidate
fixes — including kernel/driver changes against the in‑tree `ath12k` — in whatever way
is useful to the team.

## Repository contents

```
repro/udpflood.py            minimal UDP transmit load generator (no listener needed)
repro/latency-probe.sh       10 Hz ping RTT distribution, run concurrently with the flood
repro/read-ath12k-fw-stats.sh dumps the firmware TX counters cited above (root)
repro/run-comparison.sh      runs device-vs-control flood and prints the comparison
results/observed.txt         a full captured run (environment + the numbers above)
```
