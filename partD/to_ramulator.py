#!/usr/bin/env python3
"""
Part D step 2 - convert gem5's CommMonitor trace to Ramulator format.

    cd ~/AMCAS/gem5
    python3 convert_trace.py m5out_trace/l2miss.trc.gz --histogram
    python3 convert_trace.py m5out_trace/l2miss.trc.gz l2miss.trace --limit 500000

Why not util/decode_packet_trace.py: it emits 'u' for every packet on a
cache's memory-side port, because it only recognises ReadReq(1) and
WriteReq(4). An L2 mem-side port uses ReadSharedReq, ReadExReq,
WritebackDirty and friends, so the read/write distinction is lost. This
reads the protobuf directly and derives command names from your own
src/mem/packet.hh, so the mapping cannot drift between gem5 versions.

Output is Ramulator 2.1 ReadWriteTrace format:

    R 2133262848
    W 2133266944

Type FIRST, address in DECIMAL. Not the handout's "0x7f2a4c00 R": order
reversed, and Ramulator parses with std::stoll() and no base, so hex
silently becomes 0. See readwrite_trace.cpp lines 75-100.

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
ap.add_argument("--limit", type=int, default=0)
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

# Derive the MemCmd enum order from src/mem/packet.hh - the protobuf
# stores the integer and the enum order is the only ground truth.
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


# Commands that generate no DRAM access and must be dropped.
# CleanEvict tells the next level down that a clean block was evicted, for
# snoop-filter maintenance. It carries no data and never reaches DRAM, so
# counting it as a read would inject phantom traffic (it is ~23% of an L2
# mem-side trace). Same for the other notification-only commands.
DROP = {"CleanEvict", "InvalidateReq", "InvalidateResp", "UpgradeReq",
        "UpgradeResp", "SCUpgradeReq", "SCUpgradeFailReq", "UpgradeFailResp"}


def classify(c):
    if c < len(names):
        n = names[c]
        if n in DROP:
            return None, n
        if "Writeback" in n or "WriteClean" in n or n.startswith("Write"):
            return "W", n
        return "R", n
    return ("W" if c == 4 else "R"), f"cmd{c}"


fin = protolib.openFileRd(args.infile)

# gem5 traces begin with a 4-byte "gem5" magic string, before the header
magic = fin.read(4).decode(errors="replace")
if magic != "gem5":
    sys.exit(f"not a gem5 protobuf trace (magic was {magic!r})")

hdr = packet_pb2.PacketHeader()
protolib.decodeMessage(fin, hdr)
print(f"trace object: {hdr.obj_id}   tick_freq={hdr.tick_freq}")

pkt = packet_pb2.Packet()
hist = Counter()
n = kept = 0
out = open(args.outfile, "w") if args.outfile else None

while protolib.decodeMessage(fin, pkt):
    t, name = classify(pkt.cmd)
    hist[(pkt.cmd, name, t or "drop")] += 1
    n += 1
    if t is None:
        continue
    if out:
        out.write(f"{t} {pkt.addr}\n")
    kept += 1
    if args.limit and kept >= args.limit:
        break

if out:
    out.close()

print(f"\n{n:,} packets read, {kept:,} kept")
print(f"{'cmd':>5} {'name':<26} {'R/W':>5} {'count':>12}")
for (c, name, t), k in sorted(hist.items(), key=lambda x: -x[1]):
    print(f"{c:>5} {name:<26} {t:>5} {k:>12,}")

nr = sum(k for (c, nm, t), k in hist.items() if t == "R")
nw = sum(k for (c, nm, t), k in hist.items() if t == "W")
nd = n - nr - nw
print(f"\nkept {nr:,} reads ({nr/kept:.1%} of trace), "
      f"{nw:,} writes ({nw/kept:.1%})")
print(f"dropped {nd:,} data-less commands ({nd/n:.1%} of packets)")
print(f"wrote {args.outfile}" if out else "\n(--histogram: nothing written)")
print("Check the R/W column against the command names before trusting it.")
