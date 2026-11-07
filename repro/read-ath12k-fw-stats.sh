#!/usr/bin/env bash
# Dumps the WCN7850/ath12k firmware transmit counters that evidence the stall.
# Run as root on the device. Adjust PCI path if different.
set -u
P=/sys/kernel/debug/ath12k/pci-0000:01:00.0
echo "### pdev_stats (lifetime TX retries / timeouts / drops) ###"
cat "$P"/mac0/fw_stats/pdev_stats 2>/dev/null \
  | grep -iE 'Excessive retries|SW retries|TX timeout|continuous xretry|PPDUs reaped'
echo "### htt type 5 HW_PDEV_ERRS (hardware TX scheduler) ###"
echo 5 > "$P"/mac0/htt_stats_type; cat "$P"/mac0/htt_stats 2>/dev/null \
  | grep -iE 'hwsch_misaligned_offset_received|hwsch_reset_count|tx_flush|sch_rx_ppdu_no_response'
echo "### htt type 12 TX_SELFGEN (Block-Ack / RTS the firmware generates) ###"
echo 12 > "$P"/mac0/htt_stats_type; cat "$P"/mac0/htt_stats 2>/dev/null \
  | grep -iE '^su_bar|^rts |cts2self'
