#!/usr/bin/env python3
"""
Part D step 2 - convert gem5's CommMonitor trace to DRAMsim3 format.

    cd ~/AMCAS/gem5
    python3 to_dramsim3.py m5out_trace/l2miss.trc.gz l2miss.trace --limit 500000

DRAMsim3's trace format (src/common.cc, operator>> for Transaction):

    <hex_addr> <READ|WRITE> <arrival_cycle>

Address in HEX, memory op as a word, arrival cycle in decimal memory
cycles. Anything in {WRITE, write, P_MEM_WR, BOFF} counts as a write;
everything else is a read.

Note this is closer to the assignment handout's "0x7f2a4c00 R" than
Ramulator's format ever was - address first and hex - but it needs the
third field, and "R" alone leaves added_cycle unset.

The arrival cycle matters: it lets DRAMsim3 replay the request timing
gem5 actually produced, instead of assuming back-to-back arrivals.
gem5 ticks are picoseconds (tick_freq = 1e12); DDR4-3200 has tCK = 0.625
ns, so cycle = tick / 625. Override with --tck if you use another speed
grade.

Why DRAMsim3 rather than Ramulator: Ramulator 2.1's Python API did not
respond to the address-mapper or channel-count changes Tasks 3 and 4
require (all traffic landed on one channel regardless of settings).
DRAMsim3 exposes both as plain INI fields and responds to both.

Requires:  pip install protobuf --break-system-packages
           protoc --python_out=. --proto_path=src/proto src/proto/packet.proto
"""
import argparse
import os
import re
import sys
from collections import Counter

ap = argparse.ArgumentParser()
ap.add_argument("infile")
ap.add_argument("outfile", nargs="?")
ap.add_argument("--gem5", default=".")
ap.add_argument("--limit", type=int, default=0, help="max requests to keep")
ap.add_argument("--tck", type=float, default=0.625,
                help="memory clock period in ns (DDR4-3200 = 0.625)")
ap.add_argument("--histogram", action="store_true")
args = ap.parse_args()

if not args.histogram and not args.outfile:
    sys.exit("give an output file, or use --histogram")

for p in (args.gem5, os.path.join(args.gem5, "util"),
          os.path.join(args.gem5, "build/X86/proto")):
    sys.path.insert(0, os.path.abspath(p))

try:
    import packet_pb2
except ImportError as e:
    sys.exit(f"import packet_pb2 failed: {e}\ngenerate it with:\n"
             "  protoc --python_out=. --proto_path=src/proto src/proto/packet.proto")
try:
    import protolib
except ImportError as e:
    sys.exit(f"import protolib failed: {e}\nrun from the gem5 root, or pass --gem5")

# Derive the MemCmd enum order from src/mem/packet.hh. The protobuf stores
# the integer; the enum order is the only ground truth.
names = []
try:
    src = open(os.path.join(args.gem5, "src/mem/packet.hh")).read()
    m = re.search(r"enum\s+Command\s*\{(.*?)\}\s*;", src, re.S)
    if m:
        for line in m.group(1).splitlines():
            line = re.sub(r"//.*|/\*.*?\*/", "", line).strip().rstrip(",")
            if line and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", line):
                names.append(line)
except OSError:
    pass
print(f"parsed {len(names)} commands from src/mem/packet.hh"
      if names else "WARNING: could not parse the Command enum")

# Commands that never reach DRAM. CleanEvict tells the level below that a
# clean block was evicted, for snoop-filter maintenance - it carries no
# data. On an L2 mem-side trace it is ~36% of packets, so counting it
# would inject that much phantom read traffic.
DROP = {"CleanEvict", "InvalidateReq", "InvalidateResp", "UpgradeReq",
        "UpgradeResp", "SCUpgradeReq", "SCUpgradeFailReq", "UpgradeFailResp"}


def classify(c):
    if c < len(names):
        n = names[c]
        if n in DROP:
            return None, n
        if "Writeback" in n or "WriteClean" in n or n.startswith("Write"):
            return "WRITE", n
        return "READ", n
    return ("WRITE" if c == 4 else "READ"), f"cmd{c}"


fin = protolib.openFileRd(args.infile)
magic = fin.read(4).decode(errors="replace")
if magic != "gem5":
    sys.exit(f"not a gem5 protobuf trace (magic was {magic!r})")

hdr = packet_pb2.PacketHeader()
protolib.decodeMessage(fin, hdr)
ps_per_tick = 1e12 / hdr.tick_freq
ps_per_cycle = args.tck * 1000
print(f"trace object: {hdr.obj_id}   tick_freq={hdr.tick_freq}")
print(f"tCK={args.tck} ns -> {ps_per_cycle:.0f} ps per memory cycle")

pkt = packet_pb2.Packet()
hist = Counter()
n = kept = 0
t0 = None
out = open(args.outfile, "w") if args.outfile else None

while protolib.decodeMessage(fin, pkt):
    t, name = classify(pkt.cmd)
    hist[(pkt.cmd, name, t or "drop")] += 1
    n += 1
    if t is None:
        continue
    if t0 is None:
        t0 = pkt.tick
    cycle = int((pkt.tick - t0) * ps_per_tick / ps_per_cycle)
    if out:
        out.write(f"{pkt.addr:x} {t} {cycle}\n")
    kept += 1
    if args.limit and kept >= args.limit:
        break

if out:
    out.close()

print(f"\n{n:,} packets read, {kept:,} kept")
print(f"{'cmd':>5} {'name':<26} {'op':>6} {'count':>12}")
for (c, name, t), k in sorted(hist.items(), key=lambda x: -x[1]):
    print(f"{c:>5} {name:<26} {t:>6} {k:>12,}")

nr = sum(k for (c, nm, t), k in hist.items() if t == "READ")
nw = sum(k for (c, nm, t), k in hist.items() if t == "WRITE")
print(f"\nkept {nr:,} reads ({nr/kept:.1%}), {nw:,} writes ({nw/kept:.1%})")
print(f"dropped {n-nr-nw:,} data-less commands ({(n-nr-nw)/n:.1%} of packets)")
print(f"wrote {args.outfile}" if out else "\n(--histogram: nothing written)")
