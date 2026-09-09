# Part C — NVSim: the same 2 MB as STT-MRAM

Same capacity, same periphery, different bitcell. Covers all four tasks
of Assignment 1 Part C.

## Requirements

NVSim from github.com/SEAL-UCSB/NVSim.

**The build fails on modern gcc.** `BankWithHtree.cpp` errors with
`reference to 'data' is ambiguous` — the local `data` collides with
`std::data` from C++17. One-line fix:

```bash
sed -i 's/^CXXFLAGS := -Wall/CXXFLAGS := -Wall -std=c++11/' Makefile
make clean && make -j
```

Put `run.sh`, `stt.cell` and `stt.cfg` next to the `nvsim` binary.
NVSim's own `SRAM.cell` is used as the control.

## Running

```bash
chmod +x run.sh
./run.sh          # all four tasks
./run.sh 3        # one task only
```

## Config

`stt.cfg` is the shipped `sample_STTRAM_cache.cfg` with four changes so
it matches the Part B CACTI baseline: ProcessNode 22→45, Capacity 8→2 MB,
Associativity 16→8, CacheAccessMode Sequential→Normal. WordWidth 512 bit,
Temperature 350 K, OptimizationTarget ReadEDP left as shipped.

`stt.cell` is the handout's 16-line file with the merged-line bug fixed
(see Notes).

## Results

**Task 1 — data array, same tool and config, only the .cell changed**

| Metric | SRAM | STT-MRAM | Ratio |
|---|---|---|---|
| Read latency | 753.4 ps | 1.448 ns | 1.92× worse |
| Write latency | 520.0 ps | 10.608 ns | **20.4× worse** |
| Read energy | 561.2 pJ | 662.0 pJ | 1.18× worse |
| Write energy | 517.8 pJ | 454.1 pJ | 1.14× better |
| Leakage | 2.981 W | 369.5 mW | **8.07× better** |
| Area | 5.944 mm² | 3.142 mm² | **1.89× better** |
| Area efficiency | 83.44 % | 58.39 % | |
| Subarray | 64 × 256 | 512 × 512 | |

Cache level, including the tag array:

| | SRAM | STT-MRAM |
|---|---|---|
| Total area | 6.393 mm² | 3.590 mm² |
| Hit latency | 0.850 ns | 1.589 ns |
| Write latency | 0.520 ns | 10.608 ns |
| Hit energy | 575 pJ | 760 pJ |
| Leakage | 3196.1 mW | 425.2 mW |

**Task 2 — which two are dramatically worse, which two dramatically better**

Worse: **write latency** (20.4×) and **read latency** (1.9×).
Better: **leakage** (8.07×) and **area** (1.89×).

Write latency is set by the switching physics, not the circuit: the free
layer needs 200 µA held for 10 ns to flip. NVSim reports Write Pulse
Duration = 10.000 ns out of a 10.608 ns total, so 94 % of the write is
just waiting for the magnetisation to reverse. An SRAM write is a
capacitive node flip and finishes in 520 ps.

Leakage collapses because there is no static current path through an MRAM
cell — only the access transistor's subthreshold leakage. The SRAM cell
has two cross-coupled inverters holding state, and 16 million of them.

Area comes from the cell: 54 F² against SRAM's 146 F², 2.7× denser. Note
the array only realises 1.89× of that, because array efficiency drops from
83 % to 58 % — see Task 4.

**Task 3 — TMR 2:1 → 3:1**

| | R_on/R_off | Read latency | Bitline latency | Senseamp latency | Area |
|---|---|---|---|---|---|
| TMR 2:1 | 3 kΩ / 6 kΩ | 1.448 ns | 90.8 ps | 803.5 ps | 3.142 mm² |
| TMR 3:1 | 4 kΩ / 12 kΩ | 1.453 ns | 96.0 ps | 803.5 ps | 3.132 mm² |

**Nothing moves more than 0.4 %, and read latency gets slightly worse.**

Sense-amp latency is byte-identical at 803.455 ps — in NVSim it is a
technology constant, not derived from the sense margin. So doubling TMR
buys nothing on speed. What did change is bitline latency, 90.8 → 96.0 ps,
and it got *worse*, because this TMR improvement was achieved partly by
raising R_on from 3 kΩ to 4 kΩ, and R_on directly sets the bitline RC.

The lesson: TMR ratio is the wrong figure of merit at the array level. It
buys sensing *margin* — which converts to yield and robustness, not
latency. What actually matters for speed is the absolute R_on. A TMR
headline obtained by raising R_on is worse for the array than the same
ratio obtained by lowering R_off.

**Task 4 — halve ResetCurrent to 100 µA**

| Run | Reset current | AccessCMOSWidth | Area | Efficiency | Write energy |
|---|---|---|---|---|---|
| I200_W6 | 200 µA | 6 F | 3.142 mm² | 58.39 % | 454.1 pJ |
| I100_W6 | 100 µA | 6 F | **3.142 mm²** | 58.39 % | 388.5 pJ |
| I100_W3 | 100 µA | 3 F | **2.545 mm²** | **72.10 %** | 313.9 pJ |

**Area does not move when you halve the current alone.** That is the
finding, not a broken run. The handout's cell file pins
`CellArea (F^2): 54` and `AccessCMOSWidth (F): 6`, so NVSim uses the
stated area regardless of what current the cell now needs. The chain the
task describes is cut at its first link.

Let the width follow the current — 6 F → 3 F — and the chain reconnects:
area falls 19 % to 2.545 mm², array efficiency jumps from 58 % to 72 %,
write energy falls 31 %, and NVSim can now fit 1024-row subarrays instead
of 512.

That efficiency number is the whole point. At 200 µA the write drivers and
access transistors are so large that a 54 F² cell only achieves 58 %
array efficiency, against SRAM's 83 % with a 146 F² cell. **The write
current, not the bitcell, is what limits MRAM density.** Halving it
recovers most of the gap.

## Notes

**The handout's cell file has a merged line.** It gives

```
-SetMode: current-SetCurrent (uA): 200
```

NVSim parses `SetMode` as the whole string `current-SetCurrent (uA): 200`
and never sees `SetCurrent`. Split into two lines.

**The handout's cell file is also incomplete.** The shipped
`sample_STTRAM.cell` has five fields the handout's 16 lines omit:
`ReadVoltage`, `MinSenseVoltage`, `VoltageDropAccessDevice`, `ResetEnergy`
and `SetEnergy`. Adding `ReadVoltage`/`MinSenseVoltage` does not rescue
Task 3 — sense-amp latency stays fixed at 803.455 ps either way — but it
is worth stating that the model is being driven with fewer inputs than it
supports.

**The shipped cell differs from the handout's** in several values:
`CellAspectRatio` 0.54 vs 2.0, `ResetCurrent`/`SetCurrent` 80 vs 200 µA,
`ReadPower` 30 vs 145 µW, `AccessCMOSWidth` 8 vs 6 F. Task 1 says "the
shipped STT-MRAM cell" but the handout then prints its own. These results
use the handout's values.

**Why compare inside NVSim rather than against CACTI.** A CACTI-vs-NVSim
comparison changes the tool, the wire model, the optimiser and the
periphery search all at once. Running NVSim's own `SRAM.cell` against
`stt.cell` holds all of that fixed so only the bitcell varies — which is
what the central question asks. For reference, the cross-tool numbers
disagree substantially: CACTI gives the 2 MB SRAM 2.902 ns and 11.474 mm²,
NVSim gives it 0.850 ns and 6.393 mm². Quote the controlled comparison and
mention the cross-tool gap as a limitation.
