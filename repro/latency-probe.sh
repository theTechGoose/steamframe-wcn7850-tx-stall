#!/usr/bin/env bash
# Pings <target> at 10 Hz for <count> packets and prints the RTT distribution.
# Run concurrently with udpflood.py to measure latency under transmit load.
# Usage: latency-probe.sh <target-ip> [count=110]
target="$1"; count="${2:-110}"
timeout $(( count/10 + 4 )) ping -i 0.1 -c "$count" -W1 "$target" 2>/dev/null \
 | awk -F'[= ]' '/time=/{t=$(NF-1);n++;if(t>mx)mx=t;a[n]=t; if(t>50)hi++}
   END{if(n){asort(a);
     printf "RTT ms: p50=%.0f p90=%.0f p99=%.0f max=%.0f   over-50ms=%d/%d\n",
       a[int(n/2)],a[int(n*0.9)],a[int(n*0.99)],mx,hi,n}
     else print "no replies"}'
