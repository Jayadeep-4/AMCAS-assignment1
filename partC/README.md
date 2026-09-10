# Part C — NVSim: the same 2 MB as STT-MRAM

Same capacity and periphery, different bitcell. Tasks 1–4.

## Requirements

NVSim from github.com/SEAL-UCSB/NVSim.

**The build fails on modern gcc.** `BankWithHtree.cpp` errors with
`reference to 'data' is ambiguous` — the local `data` collides with
`std::data` from C++17. Fix:

```bash
sed -i 's/^CXXFLAGS := -Wall/CXXFLAGS := -Wall -std=c++11/' Makefile
make clean && make -j
```

Put `run.sh`, `stt.cell` and `stt.cfg` next to the `nvsim` binary.
NVSim's own `SRAM.cell` is the control.

## Running

```bash
chmod +x run.sh
./run.sh        # all four tasks
./run.sh 3      # one task
```

## Config

`stt.cfg` is the shipped `sample_STTRAM_cache.cfg` with four changes so it
matches the Part B CACTI baseline: ProcessNode 22→45, Capacity 8→2 MB,
Associativity 16→8, CacheAccessMode Sequential→Normal. WordWidth 512 bit,
Temperature 350 K, OptimizationTarget ReadEDP left as shipped.

`stt.cell` is the handout's 16-line file with the merged-line bug fixed.

Both runs use the same `stt.cfg`; only `-MemoryCellInputFile` changes.
A CACTI-vs-NVSim comparison would change the tool, wire model, optimiser
and periphery search all at once, so NVSim's own SRAM cell is used as the
control instead.

## Results

**Task 1 — data array** (where the bitcell difference appears)

| Metric | SRAM | STT-MRAM | Ratio |
|---|---|---|---|
| Read latency | 753.4 ps | 1.448 ns | 1.92× worse |
| Write latency | 520.0 ps | 10.608 ns | 20.4× worse |
| Read energy | 561.2 pJ | 662.0 pJ | 1.18× worse |
| Write energy | 517.8 pJ | 454.1 pJ | 1.14× better |
| Leakage | 2.981 W | 369.5 mW | 8.07× better |
| Area | 5.944 mm² | 3.142 mm² | 1.89× better |
| Area efficiency | 83.44 % | 58.39 % | |
| Subarray | 64 × 256 | 512 × 512 | |

H-tree share of read energy: SRAM 502.1 pJ of 561.2; MRAM 298.4 of 662.0.
So array-only energy is 59.1 pJ against 363.7 pJ.

Cache level, including tag array:

| | SRAM | STT-MRAM |
|---|---|---|
| Total area | 6.393 mm² | 3.590 mm² |
| Hit latency | 0.850 ns | 1.589 ns |
| Write latency | 0.520 ns | 10.608 ns |
| Hit energy | 575 pJ | 760 pJ |
| Leakage | 3196.1 mW | 425.2 mW |

**Task 3 — TMR 2:1 → 3:1**

| | R_on/R_off | Read latency | Bitline latency | Senseamp latency | Area |
|---|---|---|---|---|---|
| 2:1 | 3 kΩ / 6 kΩ | 1.448 ns | 90.8 ps | 803.455 ps | 3.142 mm² |
| 3:1 | 4 kΩ / 12 kΩ | 1.453 ns | 96.0 ps | 803.455 ps | 3.132 mm² |

Nothing moves more than 0.4 %. Sense-amp latency is byte-identical — in
NVSim it is a technology constant, not derived from the sense margin.

**Task 4 — halve ResetCurrent**

| Run | Reset current | AccessCMOSWidth | Area | Efficiency | Write energy |
|---|---|---|---|---|---|
| I200_W6 | 200 µA | 6 F | 3.142 mm² | 58.39 % | 454.1 pJ |
| I100_W6 | 100 µA | 6 F | 3.142 mm² | 58.39 % | 388.5 pJ |
| I100_W3 | 100 µA | 3 F | 2.545 mm² | 72.10 % | 313.9 pJ |

## Notes

**The handout's cell file has a merged line.** It gives
`-SetMode: current-SetCurrent (uA): 200`. NVSim reads `SetMode` as the
whole string and never sees `SetCurrent`. Split into two lines.

**Area does not move on halving the current alone.** `CellArea (F^2): 54`
and `AccessCMOSWidth (F): 6` are pinned in the cell file, so NVSim uses
the stated geometry regardless. The `I100_W3` row scales the width with
the current, which is what makes the coupling visible.

**The handout's cell file omits five fields** the shipped
`sample_STTRAM.cell` has: `ReadVoltage`, `MinSenseVoltage`,
`VoltageDropAccessDevice`, `ResetEnergy`, `SetEnergy`. Adding
`ReadVoltage`/`MinSenseVoltage` does not change the Task 3 result —
sense-amp latency stays at 803.455 ps either way.

**The shipped cell also differs in values** from the handout's:
`CellAspectRatio` 0.54 vs 2.0, `ResetCurrent`/`SetCurrent` 80 vs 200 µA,
`ReadPower` 30 vs 145 µW, `AccessCMOSWidth` 8 vs 6 F. These results use
the handout's values.

**Use the data-array numbers, not the cache-level summary.** NVSim's
cache-level `Write Dynamic Energy` reads 0.531 nJ for both cells because
it is a tag-path figure.

**ECC mismatch with Part B.** CACTI has `-Add ECC "true"`; NVSim does not
add ECC by default.

## Files

| File | |
|---|---|
| `run.sh` | all four tasks |
| `stt.cell` | STT-MRAM cell, merged line fixed |
| `stt.cfg` | 2 MB / 8-way / 45 nm / 350 K |
