# Part D — DRAM: the L2 miss stream on a DDR4 channel

Captures the L2 miss stream from gem5 and replays it on a DDR4 channel.
All four tasks in **DRAMsim3**; Tasks 1–2 also in **Ramulator 2.1** as a
cross-tool check.

## Why two simulators

The handout targets **Ramulator 2.0**: a `ramulator2` executable driven by
`ddr4.yaml`. That interface no longer exists. Four mismatches, all
confirmed by building and running:

| Handout | Ramulator 2.1 |
|---|---|
| `./ramulator2 -f ddr4.yaml` | no executable, no YAML — shared library plus a Python module (`CMakeLists.txt`: `add_library(ramulator SHARED)`, `nanobind_add_module(_ramulator)`) |
| trace `0x7f2a4c00 R` | `ReadWriteTrace` wants `R <decimal>` — order reversed, and `std::stoll` with no base makes hex silently 0 (`readwrite_trace.cpp:75-100`) |
| `Frontend: impl: SimpleO3` with that trace | `SimpleO3` wants `<bubble_count> <addr>`; the two were never compatible |
| `Scheduler: { impl: FCFS }` | no FCFS scheduler exists; only `FRFCFS` and `FRFCFSRowHit` |

Tasks 1 and 2 work in Ramulator 2.1. **Tasks 3 and 4 do not.** Switching
`addr_mapper` between `RoBaRaCoCh` and `ChRaBaRoCo` gave byte-identical
output, and with two channels all traffic landed on one controller with the
other idle, at every `interleave_bits` value tried:

```
nch=2 interleave_bits=0: reads/chan=[0, 40250]
nch=2 interleave_bits=3: reads/chan=[0, 40250]
nch=2 interleave_bits=6: reads/chan=[0, 40250]
```

Whether this is a 2.1 bug, a missing parameter, or a binding issue was not
determined. DRAMsim3 — listed in the assignment as the alternative —
exposes channel count and address mapping as plain INI fields and responds
to both, so it carries all four tasks.

## Requirements

**gem5** with a CommMonitor on the L2 memory-side port. No flag exists;
`patch_monitor.sh` rewrites the connection at `configs/common/CacheConfig.py`
line 140 and restores it afterwards.

**DRAMsim3** — builds clean on gcc 15, no patches:

```bash
git clone https://github.com/umd-memsys/DRAMsim3
cd DRAMsim3 && make -j$(nproc)
```

**Ramulator 2.1** — needs cmake:

```bash
sudo apt install cmake
git clone https://github.com/CMU-SAFARI/ramulator2
cd ramulator2 && ./build.sh
pip install -e . --break-system-packages
```

Note `pip install` succeeds and `import ramulator` passes even when
`./build.sh` failed for want of cmake — the Python wrapper installs
without the compiled extension. Verify properly with
`python3 -c "import ramulator; print(ramulator.scheduler.FRFCFS())"`.

**Trace conversion:**

```bash
pip install protobuf --break-system-packages
cd ~/AMCAS/gem5
protoc --python_out=. --proto_path=src/proto src/proto/packet.proto
```

## Running

```bash
# 1. capture the trace (once)
cd ~/AMCAS/gem5
./patch_monitor.sh on
env L2_TRACE_FILE=l2miss.trc.gz ./build/X86/gem5.opt \
  --outdir=m5out_trace configs/deprecated/example/se.py \
  --cpu-type=O3CPU --caches --l2cache \
  --l1d_size=32kB --l1i_size=32kB --l2_size=2MB --l2_assoc=8 \
  --mem-type=DDR4_2400_8x8 --mem-size=4GB \
  --cmd=$HOME/AMCAS/gapbs/bfs \
  --options="-f $HOME/AMCAS/gapbs/kron18.sg -n 5"
./patch_monitor.sh off

# 2. convert, once per simulator
python3 to_dramsim3.py m5out_trace/l2miss.trc.gz l2miss_d3.trace --limit 500000
python3 to_ramulator.py m5out_trace/l2miss.trc.gz l2miss.trace   --limit 500000

# 3. run
cd ~/AMCAS/DRAMsim3
CYCLES=40000000 ./run_partD_dramsim3.sh ~/AMCAS/gem5/l2miss_d3.trace

cd ~/AMCAS/ramulator2
python3 run_partD_ramulator.py ~/AMCAS/gem5/l2miss.trace
```

`CYCLES=40000000` matters: the trace spans 37,286,853 memory cycles, and
the 2,000,000 default only completes 6 % of it.

## The trace

500,000 requests kept from 779,951 packets:

| cmd | name | op | count |
|---|---|---|---|
| 25 | ReadSharedReq | READ | 339,115 |
| 10 | CleanEvict | **dropped** | 279,951 |
| 7 | WritebackDirty | WRITE | 93,393 |
| 22 | ReadExReq | READ | 67,492 |

406,607 reads (81.3 %), 93,393 writes (18.7 %).

**`CleanEvict` must be dropped** — it tells the level below that a clean
block was evicted, for snoop-filter maintenance, and carries no data. At
35.9 % of packets, counting it as a read would inject that much phantom
traffic.

**`util/decode_packet_trace.py` is not usable here.** It labels every
packet `u` because it only recognises `ReadReq`(1) and `WriteReq`(4),
while an L2 mem-side port emits `ReadSharedReq`(25), `ReadExReq`(22) and
`WritebackDirty`(7). Both converters read the protobuf directly and derive
command names from `src/mem/packet.hh`.

| | Ramulator 2.1 | DRAMsim3 |
|---|---|---|
| Format | `R <decimal_addr>` | `<hex_addr> READ\|WRITE <cycle>` |
| Address | decimal | hex |
| Order | type first | address first |
| Arrival timing | **none** | third field, memory cycles |

## Results — DRAMsim3

`configs/DDR4_8Gb_x8_3200.ini`, 40 M cycles, full trace completed
(406,608 reads + 93,393 writes in every configuration).

| Task | Config | row-hit rate | avg read latency | vs baseline |
|---|---|---|---|---|
| 1 | baseline, OPEN_PAGE, 1 ch, `rochrababgco` | 84.73 % | **53.53** | — |
| 2 | CLOSE_PAGE | 0.00 % | **582.16** | **10.9×** |
| 3 | row below bank, `chrabgbaroco` | 50.33 % | **142.32** | **2.66×** |
| 4 | 2 channels | 88.56 % | **48.21** | 0.90× (−9.9 %) |

### Task 1

Row-hit rate 84.73 %, average read latency 53.53 memory cycles
(33.5 ns at tCK = 0.625 ns), all 500,000 requests serviced over 37.3 M
cycles.

### Task 2 — why the penalty is 528 cycles, not 44

The naive figure is tRP + tRCD = 22 + 22 = **44 cycles** per row miss. The
measured penalty is **+528.63 cycles**, twelve times that. The 44-cycle
number is the *unloaded* penalty for one isolated miss; what the simulator
reports is the queueing that follows.

At 84.73 % row-hit rate, accesses arrive in bursts to the same row. Under
OPEN_PAGE a burst of N accesses costs one ACT plus N column accesses at
tCCD ≈ 4 cycles. Under CLOSE_PAGE the row is precharged immediately, so
every access needs its own ACT-RD-PRE — and all of them target the *same
bank*, so they serialise at tRC = tRAS + tRP = **74 cycles** each. A burst
of ten goes from roughly 40 cycles to 740.

So closing the page cuts per-bank throughput by about 18×, and the latency
you measure is dominated by the resulting queue, not by the isolated
ACT/PRE pair.

### Task 3 — bank-level parallelism, not row locality

Row-hit rate falls only to 50.33 %, not to zero, yet latency still rises
2.66×. So this is not loss of row locality — it is loss of **bank-level
parallelism**. With row bits below bank bits, consecutive addresses map
into the same bank instead of spreading across the 16 banks, so requests
queue behind one bank's row cycles rather than overlapping across many.

Note this is a *different* mechanism from Task 2 even though both show up
as higher latency: Task 2 removes row reuse, Task 3 removes bank
interleaving.

### Task 4 — bandwidth was never the constraint

Doubling channels improves latency by 9.9 %, essentially nothing. The
reason is in the trace itself: 500,000 requests spread over 37,286,853
cycles is **74.6 cycles between arrivals**. A DDR4-3200 channel retires a
request every few cycles, so the channel is at roughly 10 % utilisation.

A second channel has almost nothing to relieve. **The binding constraint
is per-bank timing — tRC = tRAS + tRP = 74 cycles — not channel
bandwidth.** How to tell from the output: compare the arrival interval
against tRC, and note that the row-hit rate improved (84.73 % → 88.56 %)
while latency barely moved. The small gain that does appear comes from
splitting the stream so each channel sees slightly better row locality,
not from added bandwidth.

## Cross-tool comparison, Tasks 1–2

| | Ramulator 2.1 | DRAMsim3 | ratio |
|---|---|---|---|
| Task 1 row-hit rate | 99.93 % | 84.73 % | |
| Task 1 avg read latency | 270.90 | 53.53 | **5.1×** |
| Task 2 row-hit rate | 49.94 % | 0.00 % | |
| Task 2 avg read latency | 1224.16 | 582.16 | 2.1× |

The Interlude (slide 22) says of these two: *"If they disagree by more than
10 %, one of your configs is wrong."* They disagree by 5.1× on baseline
latency, and the dominant cause is not a config error — it is the **trace
format**.

Ramulator's `ReadWriteTrace` has no arrival-time field, so it issues
requests as fast as the queue accepts and the channel runs saturated.
DRAMsim3 replays gem5's actual 74.6-cycle spacing, so it sees a lightly
loaded channel. Same trace, same workload, two different load conditions.

Secondary differences that also contribute: Ramulator ran `DDR4_3200AA`
timing with rank 2 and an `Open` row policy; DRAMsim3 ran
`DDR4_8Gb_x8_3200` with `RANK_LEVEL_STAGGERED` refresh and `PER_BANK`
queues. And Task 2's mechanisms differ — `ClosedCAP(cap=1)` in Ramulator
against `CLOSE_PAGE` in DRAMsim3, which is why the row-hit rates land at
49.94 % and 0.00 %.

This is a concrete demonstration of Interlude slide 26: *"a flat address
trace is honest for bandwidth questions and dishonest for
latency-sensitivity questions."* Good material for Part E Task 4.

## Caveats

**Neither simulator has an FCFS scheduler.** Ramulator 2.1 offers only
`FRFCFS` and `FRFCFSRowHit`; DRAMsim3's command queue is FR-FCFS by
construction. A closed-row policy removes row reuse between accesses,
which is the effect Task 2 asks you to quantify. Reported as a
substitution, not as FCFS.

**The CommMonitor perturbs the run.** The traced gem5 run took 0.0933 s
simulated against 0.0811 s untraced, about 15 % slower. The trace
therefore comes from a slightly different execution than the Part E
numbers.

**A replayed trace cannot react.** Interlude slide 26: *"A slower memory no
longer delays the next request — the trace has already decided when it
arrives."* Tasks 2 and 4 ask latency questions off a replayed trace, so
the answers understate how the rest of the machine would respond.
DRAMsim3's arrival-cycle field preserves gem5's original timing but cannot
make it adapt. The fix the Interlude names is gem5's elastic traces
(Trace CPU), which record the dependence graph.

**Only the first 500,000 requests are replayed**, of ~3.24 M packets in the
full trace. Raise `--limit` and `CYCLES` together for the whole stream.

## Files

| File | Purpose |
|---|---|
| `patch_monitor.sh` | insert / remove the gem5 CommMonitor |
| `to_dramsim3.py` | protobuf trace → DRAMsim3 format |
| `to_ramulator.py` | protobuf trace → Ramulator format |
| `run_partD_dramsim3.sh` | Tasks 1–4 |
| `run_partD_ramulator.py` | Tasks 1–2, cross-check |
