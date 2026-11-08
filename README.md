# WCN7850 / ath12k on the Steam Frame: Wi-Fi uplink collapses under simultaneous receive (the streaming workload), while a same-AP control client does not

> A bug report for the SteamOS issue tracker, with a reproduction anyone can run and a
> captured run in `results/observed.txt`. Happy to move it to whichever tracker the Frame's
> Wi-Fi stack belongs in.

## Summary

On the Steam Frame, each direction of Wi-Fi works on its own: uplink alone runs 40 to 145
Mbit/s, downlink alone about 90 Mbit/s. Run both at once, which is exactly what game
streaming does (video down, input and audio and protocol ACKs up), and the **uplink
collapses to single digits** while a control laptop on the same AP sustains both directions
without trouble.

Same AP, same wired target, same tool, back to back:

| client | uplink (concurrent) | downlink (concurrent) | uplink solo |
|---|---|---|---|
| control laptop (MacBook) | **806 Mbit/s** | 150 Mbit/s | 726 |
| **Steam Frame** | **3.8 Mbit/s** | 60 Mbit/s | ~133 |

The Mac carries about 950 Mbit/s of simultaneous traffic and does not flinch. The Frame,
on the identical setup, drops its uplink to 3.8 Mbit/s the moment it also has to receive.
So the fault is the Frame's radio, not the router, the path, or the test method. This is
the reason Steam Remote Play (Steam Link) streaming to the headset stutters: the uplink
dies, the host's bandwidth estimate falls, and it throttles the stream.

## What this is, and is not

The fault is a transmit-versus-receive arbitration failure in the WCN7850 as configured on
the Frame: under concurrent receive, the transmit path starves. Each of these was measured
and ruled out:

- Router / path / test method: the Mac control is perfect on the identical AP, target, and tool.
- Rate control: `iw dev wlan0 set bitrates` is ignored, so the host cannot pin the rate; it is firmware-owned.
- The hardware TX scheduler (HWSCH): `hwsch_reset_count` stays flat through the entire collapse, and `hwsch_misaligned_offset_received` climbs even during a healthy 140 Mbit/s transmit, so that counter is benign. (An earlier draft of this report wrongly blamed it; that claim is withdrawn.)
- Firmware crash or recovery: none during these runs (uptime ~32 h, no coredump, no MHI reset, no `time out while waiting for fw stats done`).
- Driver TX errors: zero over 30 h including under load. Even with full transmit debug (`debug_mask = DP_TX|DATA|WMI|MAC|HAL|CE`), the driver logs only clean RX, no ring-full, no descriptor exhaustion, no firmware recovery.
- Signal, channel, thermal, PCIe bandwidth, Wi-Fi power save, Bluetooth coexistence, background scanning, PCIe ASPM / CPU governor / deep-idle: each measured, none of them it.

## Impact

Steam Remote Play (Steam Link) streaming to the headset stutters badly. Streaming is
inherently bidirectional, so the uplink collapse starves the ACK and input path, the host
throttles the video, and the result is the throttle and bad-link pattern other users have
reported on this device. This is the main blocker to using the Frame as a PC-VR / streaming
display over Wi-Fi.

## Environment

| | |
|---|---|
| Device | Steam Frame (SteamOS `holo`, aarch64) |
| OS | SteamOS 0.5.7, BUILD_ID `20261103.6153824`, variant `vr` |
| Kernel | `7.2.0-g9a8c8ea46950` |
| Driver | `ath12k.ko`, license `Dual BSD/GPL`, `intree: Y` (dmesg name `ath12k_wifi7_pci`) |
| Firmware | `fw_version 0x110a0012`, build `2025-08-20`, `QC_IMAGE_VERSION_STRING=WLAN.IOE_HMT.1.1-00018-QCAHMTSWPL_V1.0_V2.0_SILICONZ-1` |
| Chip | WCN785x Wi-Fi 7 2x2 [FastConnect 7800] `[17cb:1107]` rev 01 |
| Link under test | NETGEAR AP (SSID redacted), ch149 / 5745 MHz, 80 MHz HE; Frame signal a steady -60 to -62 dBm |

## Reproduction

Associate the Frame and a healthy control client (any modern laptop) to the same 5 GHz AP,
and pick a wired host on the same LAN as the target. For each client, measure uplink alone,
downlink alone, then both at once. The collapse shows up only in the both phase.

`repro/bidir.sh` drives all three phases between a client and a wired peer:

```
CLIENT=steamos@<frame-ip> CLIENT_IP=<frame-ip> \
PEER=user@<wired-host>    PEER_IP=<wired-host> \
  repro/bidir.sh
```

Run it once with the Frame as `CLIENT`, once with the control laptop as `CLIENT`. The Frame
collapses its uplink in the both phase; the control laptop does not. `results/observed.txt`
has a full captured run with the exact per-second numbers.

To read the firmware counters on the Frame (as root), `repro/read-ath12k-fw-stats.sh`. Note
that `hwsch_reset_count` does not move during the collapse, which is how this report rules
the hardware scheduler out.

## Firmware localization

The fault is in the WCN7850 transmit path. I tried to pin the exact site in `amss.bin` the
way a wake-on-LAN issue on this same device was pinned. The image is ELF32 ARM, stripped,
and built as a `dlpager` (demand-paged) ROM-patching image whose logging uses QSHRINK
message IDs rather than string pointers. Raw searches for the virtual address of the HWSCH
and alignment diagnostic strings return zero code references, and r2 emulation finds no
xrefs, so the transmit and scheduler logic is in paged or ROM code that is not plaintext in
the file. That is the same hard ceiling the wake-on-LAN trace documented on this device. The
exact instruction is recoverable by whoever holds the ROM and the QSHRINK database, that is,
Qualcomm. `QUALCOMM.md` is paste-ready text for that ticket.

## Related

ValveSoftware/SteamOS issue #2831 reports the same chip and the same firmware build
(`WLAN.IOE_HMT.1.1-00018-...SILICONZ-1`, 2025-08-20) in a crash-then-degrade variant on 6
GHz / 160 MHz. This report is a steady-state variant that reproduces on demand with no
crash, which is easier for an engineer to work with.

## The ask

The reproduction is self-contained and the device is available for testing. I can run any
driver change or firmware image you send and return full `htt_stats` dumps, a firmware
coredump (`CONFIG_ATH12K_COREDUMP=y` is set), `trace-cmd`, or an AP-side capture within a
day. Concretely:

1. Is this a known transmit-under-concurrent-receive arbitration issue on WCN7850 with this firmware line, and is a newer firmware image available to try on the Frame?
2. Which HE path is involved (UL OFDMA / trigger handling, aggregation, MU) that would starve the uplink when RX is concurrently active? Is there a driver-side feature toggle I can test from the current driver without a firmware change?
3. Would you like me to A/B any specific WMI or driver setting? I have the Frame on a persistent test setup with a scripted acceptance test and a saved baseline for every configuration.

## Repository contents

- [`repro/udpflood.py`](repro/udpflood.py): UDP transmit load generator (no listener needed)
- [`repro/udpsink.py`](repro/udpsink.py): UDP receiver that reports achieved throughput (the downlink end)
- [`repro/bidir.sh`](repro/bidir.sh): runs uplink, downlink, and both-concurrent for a client vs a wired peer
- [`repro/latency-probe.sh`](repro/latency-probe.sh): 10 Hz ping RTT distribution
- [`repro/read-ath12k-fw-stats.sh`](repro/read-ath12k-fw-stats.sh): dumps the firmware TX counters, including the HWSCH counters (root)
- [`repro/run-comparison.sh`](repro/run-comparison.sh): single-direction device-vs-control flood
- [`results/observed.txt`](results/observed.txt): a full captured run (environment and the numbers above)
- [`QUALCOMM.md`](QUALCOMM.md): paste-ready text for a Qualcomm firmware ticket
