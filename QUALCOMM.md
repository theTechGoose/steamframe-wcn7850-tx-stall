# WCN7850 firmware ticket: uplink starves under concurrent downlink (FastConnect 7800, HMT firmware line)

Paste-ready summary for a Qualcomm WLAN firmware ticket. Device: Valve Steam Frame
(SM8550-class SoC, WCN7850 over PCIe). Firmware under test:
`WLAN.IOE_HMT.1.1-00018-QCAHMTSWPL_V1.0_V2.0_SILICONZ-1` (`fw_version 0x110a0012`, built
2025-08-20). Host driver: in-tree `ath12k` on kernel 7.2.

## Symptom

With the station associated 2x2 HE, 80 MHz, 5 GHz (ch149), unidirectional traffic is
healthy: TX-only 40 to 145 Mbit/s, RX-only about 90 Mbit/s. Under **concurrent** bidirectional
UDP load the **transmit path collapses to single-digit Mbit/s** (measured 3.8 Mbit/s) while
receive continues at about 60 Mbit/s. A different 2x2 client on the same AP, same wired
target, and same tool sustains 806 Mbit/s TX and 150 Mbit/s RX concurrently, so the AP and
the path are not the limit. This breaks real-time game streaming, whose traffic is inherently
bidirectional.

## What the host side shows (so you can skip the host as a cause)

- `ath12k` logs zero transmit errors over 30 h including under this load: no TCL ring-full,
  no descriptor exhaustion, no `failed to transmit frame`, no firmware recovery. Full TX
  debug (`debug_mask = DP_TX|DATA|WMI|MAC|HAL|CE`) shows only clean RX completions.
- Host rate control is not involved: `iw dev wlan0 set bitrates` is rejected, rate selection
  is firmware-owned, and the associated TX PHY rate during the collapse is HE-MCS 3 to 6,
  NSS 2 (288 to 648 Mbit nominal), i.e. the firmware is not selecting a floor rate.
- No firmware assert or MHI reset occurs during the collapse.

## Firmware counters during the collapse (ath12k debugfs, HTT stats)

- `hwsch_reset_count` does **not** increment across the collapse (the hardware scheduler is
  not resetting).
- `hwsch_misaligned_offset_received` increments continuously under TX load, including during
  healthy 140 Mbit/s transmit, so it does not track this fault.
- `pdev_stats` show elevated excessive-retries and TX-timeout counts under the concurrent
  load; `htt` TX_SELFGEN shows Block-Ack recovery (`su_bar`).

## The question for firmware

Under concurrent RX, what in the transmit scheduling path starves the uplink on this HMT
firmware line? Candidate areas, for your triage:

- UL OFDMA / trigger-frame handling: is the station deferring its own TX while servicing
  AP triggers or MU scheduling, such that EDCA TX is starved under concurrent RX?
- A-MPDU / Block-Ack handling when TX and RX aggregation sessions are both active.
- MU-EDCA parameters applied while associated to an HE AP.

Please advise whether a newer HMT firmware image addresses this, and whether any WMI toggle
(HE/EHT feature bits, OFDMA/MU, aggregation, MU-EDCA, RTS/CTS) changes the behavior so it can
be A/B tested from the current `ath12k` driver without a firmware change.

## Static RE ceiling (why we cannot hand you the exact site)

`amss.bin` is ELF32 ARM, stripped, dlpager-paged, ROM-patching, with QSHRINK message-ID
logging. String-to-code pivots return zero references (verified for the HWSCH and alignment
strings), so the transmit/scheduler logic is in paged or ROM code not present as plaintext.
The exact site is recoverable internally via the QSHRINK message database and the ROM source.

## Test offer

The device is available with a scripted acceptance test, a saved baseline per configuration,
and a one-command reproduction. Send a firmware image or a driver change and we will return
full `htt_stats` dumps, a firmware coredump (`CONFIG_ATH12K_COREDUMP=y` is set), `trace-cmd`,
and an AP-side capture within a day.
