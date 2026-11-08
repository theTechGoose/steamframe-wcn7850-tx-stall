#!/usr/bin/env python3
# Receive UDP as fast as possible and report achieved throughput.
# Pair with udpflood.py on the other host to measure one direction.
#   udpsink.py <bind-port> <seconds>
import socket, sys, time
port = int(sys.argv[1]); dur = float(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 22)
s.bind(("0.0.0.0", port)); s.settimeout(0.5)
end = time.time() + dur + 2; n = 0; t0 = None
while time.time() < end:
    try:
        d, _ = s.recvfrom(2048)
        if t0 is None: t0 = time.time()
        n += len(d)
    except socket.timeout:
        pass
if t0:
    print(f"recv: {n*8/1e6/max(0.1, time.time()-t0):.1f} Mbit/s, {n} bytes")
else:
    print("recv: 0 packets")
