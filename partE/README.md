# Part E — gem5: does the program actually run faster?

Runs two GAPBS kernels on three L2 configurations and two CPU models.
Covers Tasks 1–3; Task 4 is the written argument.

## Requirements

gem5 25.1.0.1, built with `scons build/X86/gem5.opt -j$(nproc)`. Builds
clean on gcc 15.2 (it warns that only v11–14.2 are supported; harmless).

GAPBS, **statically linked** — SE mode emulates syscalls rather than
booting Linux, so a dynamic binary dies in the loader:

```bash
git clone https://github.com/sbeamer/gapbs && cd gapbs
make CXX_FLAGS="-std=c++11 -O3 -Wall -static"
file bfs        # must say "statically linked"
```

**Pre-build the graphs outside gem5.** This is the single most important
setup step — see Notes.

```bash
./converter -g 18 -b kron18.sg       # 32.5 MB, unweighted, for bfs
./converter -g 18 -w -b kron18.wsg   # 63.0 MB, weighted, for sssp
```

## Running

```bash
chmod +x run_partE.sh
nohup ./run_partE.sh > partE.log 2>&1 &
tail -f partE.log
```

Nine runs, about 3–4 hours. Writes `results/summary.csv`.

## The two numbers carried in from Parts B and C

gem5 invents neither.

| | Source | Value | Cycles @ 2 GHz |
|---|---|---|---|
| SRAM L2 hit latency | CACTI, Part B | 2.9018 ns | **6** |
| MRAM L2 hit latency | NVSim, Part C | 1.589 ns | **4** |
| Iso-area capacity | NVSim areas, 6.393 / 3.590 mm² | 1.78× | **4 MB** |

`--l2-hit-latency` **is not a valid `se.py` option**, despite appearing in
both the assignment and Interlude slide 27. Verified:
`se.py --help | grep -i latency` returns nothing. The latency is set in
`configs/common/Caches.py`, lines 73–75 (`tag_latency`, `data_latency`,
`response_latency`), which `run_partE.sh` edits and restores per run.

gem5's default `--cpu-clock` is `2GHz`, from `configs/common/Options.py`,
so one cycle is 0.5 ns.

**The handout's configuration is also run** (8 MB, 14 cycles) because its
assumed "4× larger, ~2× slower" does not match our measurements — ours say
1.78× larger and 1.5× *faster*. Both are reported.

## Results

| tag | kernel | L2 | lat | CPU | simSeconds | IPC | L2 miss rate | L2 hits |
|---|---|---|---|---|---|---|---|---|
| sram_bfs | bfs | 2 MB | 6 | O3 | 0.081057 | 0.5768 | 0.6403 | 919,464 |
| mram_bfs | bfs | 4 MB | 4 | O3 | 0.068778 | 0.6798 | 0.4589 | 1,384,021 |
| ho_bfs | bfs | 8 MB | 14 | O3 | 0.059203 | 0.7897 | 0.2039 | 2,022,016 |
| sram_sssp | sssp | 2 MB | 6 | O3 | 0.306604 | 0.5967 | 0.1763 | 23,713,691 |
| mram_sssp | sssp | 4 MB | 4 | O3 | 0.261801 | 0.6988 | 0.1435 | 24,672,191 |
| ho_sssp | sssp | 8 MB | 14 | O3 | 0.304559 | 0.6007 | 0.1276 | 25,111,818 |
| ts_sram_bfs | bfs | 2 MB | 6 | TS | 0.250807 | 0.1864 | 0.6432 | 847,795 |
| ts_mram_bfs | bfs | 4 MB | 4 | TS | 0.216890 | 0.2156 | 0.4260 | 1,363,995 |
| ts_ho_bfs | bfs | 8 MB | 14 | TS | 0.196929 | 0.2374 | 0.1779 | 1,953,515 |

Speedups against the 2 MB SRAM baseline of the same CPU model:

| CPU | kernel | 4 MB / 4 cyc | 8 MB / 14 cyc |
|---|---|---|---|
| O3 | bfs | 1.179× | **1.369×** |
| O3 | sssp | 1.171× | **1.007×** |
| TimingSimple | bfs | 1.156× | **1.274×** |

## Task 2 — bfs wins, sssp is a wash

Under the handout's parameters the two kernels split completely: bfs gains
**1.369×**, sssp gains **1.007×** — nothing.

**The deciding property is the baseline hit rate, not the working-set
size.** This is counterintuitive, because sssp's working set is larger
(63 MB against 32.5 MB) and it benefits less.

| At 2 MB | miss rate | L2 accesses | hits |
|---|---|---|---|
| bfs | 64.0 % | 2.56 M | 0.92 M |
| sssp | 17.6 % | 28.8 M | 23.7 M |

bfs's 2 MB L2 barely works — 64 % of accesses miss. Quadrupling capacity
takes that to 20.4 %, converting ~1.12 M misses into hits. And with only
0.92 M hits to begin with, the extra 8 cycles per hit lands on relatively
few accesses: hit cost rises 5.5 M → 28.3 M cycles.

sssp already hits 82 % of the time at 2 MB. Delta-stepping revisits
vertices repeatedly, so it has genuine temporal locality that a small
cache captures. Quadrupling capacity recovers only ~1.40 M misses out of
28.8 M accesses, while the penalty now applies to 25.1 M hits: hit cost
rises 142.3 M → **351.6 M cycles**. The two effects cancel.

**Rule: extra capacity wins when the baseline cache is already failing.**
If it is working, you pay a latency tax on every hit to buy back very few
misses.

Note that under *our* device numbers (4 MB / 4 cycles) both kernels gain
~17 % near-identically, because more capacity comes with *lower* hit
latency — there is no trade to adjudicate. That inversion is a cross-tool
artifact and belongs in Task 4.

## Task 3 — out-of-order execution was hiding the penalty

| | 2 MB SRAM | 8 MB MRAM | advantage |
|---|---|---|---|
| O3CPU | 0.081057 s | 0.059203 s | **1.369×** |
| TimingSimpleCPU | 0.250807 s | 0.196929 s | **1.274×** |

The advantage shrinks by about 7 points in-order. The mechanism shows in
which configuration suffers more from losing O3:

| Config | O3 → TS slowdown |
|---|---|
| 2 MB / 6 cyc | 3.094× |
| 8 MB / 14 cyc | **3.326×** |

The 8 MB configuration loses more. It has 2.02 M hits at 14 cycles against
the 2 MB configuration's 0.92 M at 6. On O3 those 14-cycle hits overlap
with independent instructions and other outstanding memory operations, so
most of the latency is concealed. On TimingSimpleCPU every access blocks
and all 8 extra cycles per hit are exposed.

So out-of-order execution was **concealing the MRAM's hit-latency
penalty**, making the capacity win look larger than the raw device numbers
justify.

The general point: a latency number means nothing alone — only relative to
a core's ability to hide it. Report "1.37× on bfs with an O3 core", never
"1.37× faster".

## Task 4 — what to argue

**(i) Answer the central question.** Evidence chain:

- Part A: the SRAM bitcell is marginal at this sizing. Read disturb, not
  sensing, is the failure mode; on a realistic 400 fF bitline at 85 °C the
  read destroys the stored value.
- Part B: 2 MB SRAM at 45 nm is 2.9018 ns, 792.9 pJ, 2250 mW, 11.474 mm².
- Part C: same capacity as STT-MRAM is 8.07× less leakage and 1.89× less
  area, at 20.4× worse write latency. Write current, not the bitcell,
  limits density — array efficiency 58 % against SRAM's 83 %.
- Part E: iso-area MRAM wins 1.37× on bfs and 1.007× on sssp, and the win
  depends on the baseline cache already failing.

So: yes for miss-heavy, read-mostly, capacity-starved workloads like bfs;
no for anything with working locality or meaningful write traffic. Note
that none of these runs exercised MRAM's 20× write penalty, because BFS
and SSSP are read-dominated — a write-heavy workload would likely reverse
the conclusion, and that is a limit of the experiment, not a result.

**(ii) Three assumptions to attack.** Strongest candidates from our own
chain:

1. **The cross-tool SRAM disagreement.** CACTI says the 2 MB SRAM is
   2.9018 ns and 11.474 mm²; NVSim says 0.850 ns and 6.393 mm² for the
   same cache with the same 146 F² cell. 3.4× on latency, 1.8× on area.
   That gap is larger than most of the SRAM-vs-MRAM differences being
   reported, and it is what makes our MRAM appear *faster* per hit than
   our SRAM.
2. **The pinned cell file.** Part C Task 4 showed `CellArea` and
   `AccessCMOSWidth` are hard-coded, so halving the write current changed
   area by exactly zero. Every area-derived conclusion — including Part
   E's iso-area capacity — rests on a number the tool was told rather than
   computed.
3. **Nominal everything.** Interlude slide 19: no σ, no yield, no repair;
   16 million cells all typical. Part A's netlist is perfectly symmetric,
   so it has zero device mismatch. And temperature is an input, not a
   state that evolves — relevant because MRAM's switching current is
   temperature-sensitive.

Also available: the flat-trace problem for Part D (Interlude slide 26),
and the compounding error budget from slide 29 (ngspice ±5 %, CACTI ±10 %,
Ramulator ±10 %, gem5 ±20 %, multiplying).

## Notes

**Pre-building the graph is the critical setup step.** With `-g 18`, GAPBS
generates the Kronecker graph inside the simulation, and the phase split
is brutal:

| | `-g 18` | `-f kron18.sg` |
|---|---|---|
| Setup | 3.72 s | **0.00145 s** |
| Traversal (4 trials) | — | 0.0710 s |
| Traversal share | 0.4 % | **97 %** |

Our first attempt fast-forwarded 500 M instructions and still landed
entirely inside graph generation: 15,791 L2 accesses and a 100 % miss
rate. Using a pre-built graph file gives 1.94 M L2 accesses and a 62.9 %
miss rate over the same window — 123× more traffic, and a cache that is
doing real work. No fast-forward is then needed; the whole program is
73 ms simulated.

**sssp needs a weighted graph.** `.sg` fails with `.sg not allowed for
weighted graphs` and exit code 251. Use `converter -g 18 -w -b file.wsg`;
`-w` is a flag, not a filename, despite the help text reading
`-w <file>`.

**After a CPU switch, O3 stats live under `system.switch_cpus`,** not
`system.cpu` — `system.cpu.ipc` reads `nan`. Only relevant if you use
`--fast-forward`; our final runs do not.

**Trial counts differ by kernel.** bfs uses `-n 5`, sssp `-n 3`, because a
sssp trial is ~7× longer (123 ms against 17 ms). Trial times were
consistent with no cold-start outlier, so the first trial was not
discarded.
