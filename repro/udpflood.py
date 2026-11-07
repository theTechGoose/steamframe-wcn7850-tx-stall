#!/usr/bin/env python3
"""Minimal uncongested UDP transmit load generator.

Sends 1400-byte UDP datagrams to <host>:<port> as fast as the socket allows for
<seconds>. Needs no listener (the target may ICMP-reject; we only exercise the
sender's Wi-Fi transmit path). Reports datagrams sent, achieved Mbit/s, and the
wall-clock elapsed. If elapsed markedly exceeds the requested duration, sendto()
was blocking -- i.e. the local TX path could not drain the socket buffer.

Usage:  udpflood.py <host> <port> <seconds>
"""
import socket, sys, time

host, port, dur = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
except OSError:
    pass
buf = b"\0" * 1400
t0 = time.time()
n = 0
while time.time() - t0 < dur:
    for _ in range(64):
        try:
            s.sendto(buf, (host, port)); n += 1
        except OSError:
            pass
el = time.time() - t0
print(f"sent={n} pkts  achieved={n*1400*8/el/1e6:.0f} Mbit/s  elapsed={el:.1f}s"
      f"  (requested {dur:.0f}s{'; sendto BLOCKED' if el > dur*1.15 else ''})")
