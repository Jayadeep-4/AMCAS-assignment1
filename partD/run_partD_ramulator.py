#!/usr/bin/env python3
"""
Part D - Ramulator 2.1, all four tasks.

    python3 run_partD.py l2miss.trace

VERSION NOTE. The handout targets Ramulator 2.0: a `ramulator2` binary
driven by ddr4.yaml. That interface no longer exists. Ramulator 2.1
builds a shared library plus a Python module (CMakeLists.txt:
add_library(ramulator SHARED) / nanobind_add_module(_ramulator)), so
configuration is Python. Every YAML key in the handout maps onto a
keyword argument here.

Install:
    git clone https://github.com/CMU-SAFARI/ramulator2
    cd ramulator2 && ./build.sh
    pip install -e . --break-system-packages
"""
import argparse
import sys

try:
    import ramulator
except ImportError:
    sys.exit("import ramulator failed - run 'pip install -e . "
             "--break-system-packages' inside the ramulator2 clone")

ap = argparse.ArgumentParser()
ap.add_argument("trace", help="Ramulator trace: 'R <decimal_addr>' per line")
args = ap.parse_args()

DRAM = dict(org_preset="DDR4_8Gb_x8", timing_preset="DDR4_3200AA", rank=2)


def simulate(tag, scheduler="FRFCFS", addr_mapper="RoBaRaCoCh",
             channels=1, closed_row=False):
    fe = ramulator.frontend.ReadWriteTrace(clock_ratio=8, path=args.trace)

    ctrls = []
    for _ in range(channels):
        rp = (ramulator.row_policy.ClosedCAP(cap=1) if closed_row
              else ramulator.row_policy.Open())
        ctrls.append(ramulator.controller.GenericDDR(
            dram=ramulator.dram.DDR4(**DRAM),
            scheduler=getattr(ramulator.scheduler, scheduler)(),
            refresh_manager=ramulator.refresh_manager.AllBank(),
            row_policy=rp,
            addr_mapper=getattr(ramulator.addr_mapper, addr_mapper)(),
        ))

    mem = ramulator.memory_system.GenericDRAM(
        clock_ratio=3, controllers=ctrls,
        channel_mapper=ramulator.channel_mapper.CacheLineInterleave())

    sim = ramulator.Simulation(fe, mem)
    sim.run()

    # With >1 channel, stats["controller"] is a LIST of per-channel dicts.
    c = sim.stats["memory_system"]["controller"]
    chans = c if isinstance(c, list) else [c]

    def s(key, default=0):
        return sum(ch.get(key, default) or 0 for ch in chans)

    hits, miss, conf = s("row_hits"), s("row_misses"), s("row_conflicts")
    tot = hits + miss + conf
    rate = hits / tot if tot else 0.0

    # avg_read_latency is per channel; weight it by that channel's reads
    rl_num = sum((ch.get("avg_read_latency") or 0) * (ch.get("num_read_reqs") or 0)
                 for ch in chans)
    rl_den = s("num_read_reqs")
    avg_rl = rl_num / rl_den if rl_den else 0.0

    print(f"  {tag:32s} cycles={s('cycles') // len(chans):>7} "
          f"rd_lat={avg_rl:>7.2f} rowhit={rate:>6.2%} "
          f"h/m/c={hits}/{miss}/{conf} "
          f"reqs={rl_den}+{s('num_write_reqs')} "
          f"served={s('num_read_reqs_served')}")
    return dict(cycles=s("cycles") // len(chans), rd_lat=avg_rl, rowhit=rate,
                hits=hits, miss=miss, conf=conf)


print(f"trace: {args.trace}\n")

print("== Task 1: baseline (FRFCFS, RoBaRaCoCh, Open row, 1 channel) ==")
base = simulate("baseline")

print("\n== Task 2: row-buffer locality ==")
print("  NOTE: Ramulator 2.1 has no FCFS scheduler - only FRFCFS and")
print("  FRFCFSRowHit. A closed-row policy reproduces the effect the task")
print("  wants (no row reuse between accesses), so both are shown.")
simulate("FRFCFS + Open row", scheduler="FRFCFS")
simulate("FRFCFSRowHit + Open row", scheduler="FRFCFSRowHit")
simulate("FRFCFS + ClosedCAP(1)", closed_row=True)

print("\n== Task 3: address mapping, row bits below bank bits ==")
simulate("RoBaRaCoCh (row above bank)", addr_mapper="RoBaRaCoCh")
simulate("ChRaBaRoCo (row below bank)", addr_mapper="ChRaBaRoCo")

print("\n== Task 4: double the channel count ==")
simulate("1 channel", channels=1)
simulate("2 channels", channels=2)

print("""
Reading the output
------------------
rowhit    row-buffer hit rate, Task 1 and Task 2's headline
rd_lat    avg read latency in memory cycles
reqs      reads+writes offered by the trace
served    reads that completed before the trace ran out

If served is far below reqs, the trace ended while requests were still in
flight: Ramulator's ReadWriteTrace finishes when the trace is consumed,
not when the memory system drains, so latency is averaged over completed
requests only. Compare configurations against each other rather than
quoting absolutes.

Task 4: if latency barely improves with 2 channels, check whether both
channels actually received traffic. If one is idle the channel mapper is
not splitting your address stream, and the result says nothing about
bandwidth. Otherwise the binding constraint is per-bank timing - compare
tRC (= tRAS + tRP) against your access interval.
""")
