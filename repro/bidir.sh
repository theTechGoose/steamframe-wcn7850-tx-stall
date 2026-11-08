#!/usr/bin/env bash
# Measure one client's uplink, downlink, and BOTH-concurrent to a wired peer.
# The collapse shows up only in the BOTH phase.
#
#   CLIENT = ssh target of the device under test, or "local"
#   PEER   = ssh target of a WIRED helper on the same LAN (must have python3)
#   CLIENT_IP / PEER_IP = their LAN IPs
#
# Usage: CLIENT=steamos@192.168.1.40 CLIENT_IP=192.168.1.40 \
#        PEER=user@192.168.1.50     PEER_IP=192.168.1.50    ./bidir.sh
set -u
here=$(cd "$(dirname "$0")" && pwd); DUR=12
runc(){ [ "$CLIENT" = local ] && bash -c "$1" || ssh -o BatchMode=yes "$CLIENT" "$1"; }
runp(){ ssh -o BatchMode=yes "$PEER" "$1"; }
push(){ [ "$CLIENT" = local ] || scp -q "$here/udpflood.py" "$here/udpsink.py" "$CLIENT":/tmp/ 2>/dev/null; scp -q "$here/udpflood.py" "$here/udpsink.py" "$PEER":/tmp/ 2>/dev/null; }
CF=/tmp/udpflood.py; CS=/tmp/udpsink.py; [ "$CLIENT" = local ] && { CF="$here/udpflood.py"; CS="$here/udpsink.py"; }
push
echo "== UPLINK only (client -> peer) =="
runp "python3 /tmp/udpsink.py 9 $DUR" & sleep 1
runc "python3 $CF $PEER_IP 9 $DUR" ; wait
echo "== DOWNLINK only (peer -> client) =="
runc "python3 $CS 9 $DUR" & sleep 1
runp "python3 /tmp/udpflood.py $CLIENT_IP 9 $DUR" ; wait
echo "== BOTH concurrent (this is the test) =="
runp "python3 /tmp/udpsink.py 9 $DUR" & A=$!
runc "python3 $CS 9 $DUR" & B=$!
sleep 1
runc "python3 $CF $PEER_IP 9 $DUR" & C=$!
runp "python3 /tmp/udpflood.py $CLIENT_IP 9 $DUR" & D=$!
wait $A $B $C $D
echo "A healthy client sustains both directions. The device under test collapses its uplink here."
