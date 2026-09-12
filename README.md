# ECE2.414 Assignment 1 — Simulating Memory: Devices to Systems

Should the 2 MB L2 cache in our accelerator be SRAM, or STT-MRAM?

One design question carried through five simulators, each answering
something the other four cannot.

| Part | Tool | Question |
|---|---|---|
| A | ngspice | Does the bitcell read correctly? |
| B | CACTI 7 | How fast, big and leaky is a 2 MB SRAM L2 at 45 nm? |
| C | NVSim | Same 2 MB as STT-MRAM — what changes? |
| D | DRAMsim3 · Ramulator 2.1 | Does the miss traffic fit one DDR4 channel? |
| E | gem5 | Does the program actually run faster? |

Each part has its own README with requirements, run instructions, config
and results. Start there.

## Layout

```
partA/   ngspice     run.sh, 45nm_bulk.txt, figures/
partB/   CACTI       run.sh, cache.cfg, task4_check.py, plot.py, task2.csv
partC/   NVSim       run.sh, stt.cell, stt.cfg
partD/   DRAM        patch_monitor.sh, to_*.py, run_partD_*
partE/   gem5        run_partE.sh, summary.csv
report/  the PDF
REPORT_PLAN.md       working notes behind the report
```

The five simulators are not vendored. Each part's README gives the clone
URL, the build command, and any patch needed.

## Reproducing

Parts A–C are independent. Part E must precede Part D, because Part D's
input is a trace captured from gem5.

```bash
cd partA && ./run.sh                       # minutes
cd partB && ./run.sh && python3 plot.py    # minutes
cd partC && ./run.sh                       # minutes
cd partE && ./run_partE.sh                 # 3-4 hours, run with nohup
cd partD && ./run_partD_dramsim3.sh <trace>
```

## Build fixes needed

| Tool | Fix |
|---|---|
| CACTI 7 | none |
| DRAMsim3 | none |
| gem5 | none (warns about gcc 15; harmless) |
| NVSim | `sed -i 's/^CXXFLAGS := -Wall/CXXFLAGS := -Wall -std=c++11/' Makefile` |
| Ramulator 2.1 | needs cmake; `pip install` passes even when the C++ build failed |

## Where the numbers hand off

The assignment's point is that each tool's output is the next one's input.

```
ngspice  ->  read margin, sanity-checks CACTI's bitline delay
CACTI    ->  2.9018 ns  ->  6 cycles  ->  gem5 L2 hit latency
NVSim    ->  1.589 ns   ->  4 cycles  ->  gem5 L2 hit latency
NVSim    ->  6.393 / 3.590 mm^2  ->  1.78x  ->  gem5 iso-area capacity
gem5     ->  L2 miss trace  ->  DRAMsim3
```

## Headline results

| | |
|---|---|
| A | Failure mode is read disturb, not sensing. On a realistic 400 fF bitline at 85 °C the read destroys the stored value. |
| B | 2.9018 ns · 792.9 pJ · 2250 mW · 11.474 mm². One gate delay per doubling is **not** visible — access time scales as √capacity. |
| C | STT-MRAM: 8.07× less leakage, 1.89× less area, 20.4× worse writes. Write current, not the bitcell, limits density. |
| D | 74.6 cycles between requests, so ~10 % channel utilisation. Bandwidth was never the constraint; per-bank tRC is. |
| E | Iso-area MRAM wins **1.369× on bfs**, **1.007× on sssp**. Decided by baseline hit rate, not working-set size. |

## Handout errata found while running

Documented in each part's README, with evidence:

- Part A: `meas tran ... FIND v(blb)-v(bl)` fails in ngspice 42; the
  expression must be assigned to a vector first.
- Part A: the 69 mV reference is a DRAM charge-sharing figure (Lecture 1
  slide 24), not an SRAM read.
- Part B: `-Optimize ED^2` silently overrides the `-design objective`
  weight vector, so Task 3 requires `"NONE"`.
- Part C: the cell file merges two directives onto one line
  (`-SetMode: current-SetCurrent (uA): 200`), so NVSim never reads
  `SetCurrent`.
- Part D: Ramulator 2.0's executable and YAML interface no longer exist;
  2.1 has no FCFS scheduler and a different trace format. Tasks 3–4 do not
  respond in 2.1, so DRAMsim3 was used.
- Part E: `--l2-hit-latency` is not a valid `se.py` option; the latency
  goes in `configs/common/Caches.py`.

## Tool versions

ngspice 42 · CACTI 7 (HewlettPackard/cacti) · NVSim (SEAL-UCSB) ·
DRAMsim3 (umd-memsys) · Ramulator 2.1.0 (CMU-SAFARI) · gem5 25.1.0.1 ·
GAPBS (sbeamer) · Ubuntu, gcc 15.2, Python 3.14

Model cards: PTM 45 nm bulk BSIM4 from ptm.asu.edu (Part A). All other
parts use the shipped 45 nm configs.
