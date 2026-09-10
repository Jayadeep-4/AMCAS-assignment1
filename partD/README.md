# Part D — DRAM: the L2 miss stream on a DDR4 channel

Captures the L2 miss stream from gem5 and replays it on a DDR4 channel.
All four tasks in **DRAMsim3**; Tasks 1–2 also in **Ramulator 2.1** as a
cross-tool check.

## Why DRAMsim3

The handout targets **Ramulator 2.0** (`./ramulator2 -f ddr4.yaml`). That
interface no longer exists — 2.1 builds a shared library plus a Python
module, has no FCFS scheduler, and expects `R <decimal>` rather than the
handout's `0x7f2a4c00 R`.

Tasks 1–2 reproduce in 2.1. **Tasks 3–4 do not**: switching `addr_mapper`
between `RoBaRaCoCh` and `ChRaBaRoCo` gave byte-identical output, and with
two channels all traffic landed on one controller at every
`interleave_bits` value tried (0, 3, 6). No pinned version or Docker image
is available from the course. DRAMsim3 — the assignment's stated
alternative — exposes both as INI fields and responds to both.

## Requirements

**gem5** with a CommMonitor on the L2 memory-side port. No flag exists;
`patch_monitor.sh` rewrites `configs/common/CacheConfig.py` line 140 and
restores it afterwards.

**DRAMsim3** — builds clean, no patches:

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

`pip install` succeeds and `import ramulator` passes even when
`./build.sh` failed for want of cmake. Verify properly:
`python3 -c "import ramulator; print(ramulator.scheduler.FRFCFS())"`

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

**`CYCLES=40000000` is required.** The trace spans 37,286,853 memory
cycles; the 2,000,000 default completes only 6 % of it.

## The trace

500,000 requests kept from 779,951 packets:

| cmd | name | op | count |
|---|---|---|---|
| 25 | ReadSharedReq | READ | 339,115 |
| 10 | CleanEvict | **dropped** | 279,951 |
| 7 | WritebackDirty | WRITE | 93,393 |
| 22 | ReadExReq | READ | 67,492 |

406,607 reads (81.3 %), 93,393 writes (18.7 %). Arrival span 37,286,853
cycles, so **74.6 cycles between requests**.

| | Ramulator 2.1 | DRAMsim3 |
|---|---|---|
| Format | `R <decimal_addr>` | `<hex_addr> READ\|WRITE <cycle>` |
| Arrival timing | none | third field |

## Results — DRAMsim3

`configs/DDR4_8Gb_x8_3200.ini`, 40 M cycles, full trace completed
(406,608 reads + 93,393 writes in every configuration).

| Task | Config | row-hit rate | avg read latency | vs baseline |
|---|---|---|---|---|
| 1 | baseline, OPEN_PAGE, 1 ch, `rochrababgco` | 84.73 % | 53.53 | — |
| 2 | CLOSE_PAGE | 0.00 % | 582.16 | 10.9× |
| 3 | row below bank, `chrabgbaroco` | 50.33 % | 142.32 | 2.66× |
| 4 | 2 channels | 88.56 % | 48.21 | 0.90× |

Timing from the config: tRCD = 22, tRP = 22, tRAS = 52, tCK = 0.625 ns.

`address_mapping` is six 2-character fields, MSB first:
`rochrababgco` = ro ch ra ba bg co (row highest);
`chrabgbaroco` = ch ra bg ba ro co (row below bank).

## Cross-check, Tasks 1–2

| | Ramulator 2.1 | DRAMsim3 |
|---|---|---|
| Task 1 row-hit rate | 99.93 % | 84.73 % |
| Task 1 avg read latency | 270.90 | 53.53 |
| Task 2 row-hit rate | 49.94 % | 0.00 % |
| Task 2 avg read latency | 1224.16 | 582.16 |

The configurations are not identical: Ramulator ran `DDR4_3200AA` timing
with rank 2 and an `Open` row policy; DRAMsim3 ran `DDR4_8Gb_x8_3200` with
`RANK_LEVEL_STAGGERED` refresh and `PER_BANK` queues.

Task 2 also uses different substitutions, which is why the row-hit rates
differ: `ClosedCAP(cap=1)` allows one hit per activation (~50 %), while
`CLOSE_PAGE` precharges after every access (0 % by construction).

## Notes

**`CleanEvict` must be dropped.** It notifies the level below that a clean
block was evicted, carries no data, and never reaches DRAM. At 35.9 % of
packets, counting it would inject that much phantom traffic. Both
converters drop it and report the count.

**`util/decode_packet_trace.py` is not usable here.** It labels every
packet `u` because it only recognises `ReadReq`(1) and `WriteReq`(4),
while an L2 mem-side port emits commands 25, 22 and 7. Both converters
read the protobuf directly and derive names from `src/mem/packet.hh`.

**Neither simulator has FCFS.** Ramulator 2.1 offers only `FRFCFS` and
`FRFCFSRowHit`; DRAMsim3's command queue is FR-FCFS by construction. A
closed-row policy is used as the substitute in both.

**The CommMonitor perturbs the run** — 0.0933 s simulated against 0.0811 s
untraced, about 15 % slower. The trace comes from a slightly different
execution than the Part E numbers.

**Only the first 500,000 requests are replayed**, of ~3.24 M packets. Raise
`--limit` and `CYCLES` together for the whole stream.

## Files

| File | |
|---|---|
| `patch_monitor.sh` | insert / remove the gem5 CommMonitor |
| `to_dramsim3.py` | protobuf trace → DRAMsim3 format |
| `to_ramulator.py` | protobuf trace → Ramulator format |
| `run_partD_dramsim3.sh` | Tasks 1–4 |
| `run_partD_ramulator.py` | Tasks 1–2, cross-check |
