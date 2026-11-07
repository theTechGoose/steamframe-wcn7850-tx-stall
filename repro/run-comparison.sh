#!/usr/bin/env bash
# Convenience wrapper. Runs the UDP transmit flood + latency probe from the DEVICE
# and (optionally) from a CONTROL client on the SAME AP, both toward the same wired
# TARGET, and prints the two results side by side.
#
#   DEVICE   : ssh target for the Steam Frame        (e.g. steamos@192.168.x.y)
#   CONTROL  : ssh target for a control laptop, or "local" to use this machine
#   TARGET   : IP of a WIRED host on the same LAN (the flood/ping destination)
#
# Usage: DEVICE=... CONTROL=local TARGET=192.168.1.50 ./run-comparison.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
run_on() {  # $1 = "local" | ssh-target
  local who="$1"
  if [ "$who" = "local" ]; then
    "$here/latency-probe.sh" "$TARGET" 110 > /tmp/lat.$$ 2>&1 &
    python3 "$here/udpflood.py" "$TARGET" 9 12
    wait; cat /tmp/lat.$$; rm -f /tmp/lat.$$
  else
    scp -q "$here/udpflood.py" "$here/latency-probe.sh" "$who":/tmp/ 2>/dev/null
    ssh "$who" "bash -c 'timeout 20 bash /tmp/latency-probe.sh $TARGET 110 >/tmp/lat 2>&1 & python3 /tmp/udpflood.py $TARGET 9 12; wait; cat /tmp/lat'"
  fi
}
echo "=== DEVICE ($DEVICE) transmit flood -> $TARGET ==="; run_on "$DEVICE"
echo; echo "=== CONTROL ($CONTROL) transmit flood -> $TARGET (same AP) ==="; run_on "$CONTROL"
