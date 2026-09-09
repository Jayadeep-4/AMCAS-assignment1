# Part B — CACTI: 2 MB SRAM L2 at 45 nm

Sizes a 2 MB 8-way L2 and explores how the array organisation responds to
the design objective. Covers all four tasks of Assignment 1 Part B.

## Requirements

CACTI 7 from github.com/HewlettPackard/cacti, built with `make -j`.
Built clean on gcc 13 with no source patches (the build emits warnings
about `-gstabs+` and unused variables — harmless).

Put `run.sh`, `plot.py`, `task4_check.py` and `cache.cfg` next to the
`cacti` binary.

## Running

```bash
chmod +x run.sh
./run.sh          # all four tasks
./run.sh 2        # one task only
python3 plot.py   # Task 2 figure
```

`cache.cfg` is never modified — each run works on a temp copy in `out/`.

## Config

Only the parameters the assignment lists were changed from the shipped
`cache.cfg`: size 2097152, block 64, associativity 8, 1 read-write port,
4 UCA banks, technology 0.045, temperature 350 K, cache type, itrs-hp
data cell and periphery, ED^2, objective 0:0:0:100:0.

Everything else left at the shipped default, including
`-Wire signaling "Global_30"` (uncommented as shipped) and
`-Add ECC "true"`.

## Files

| File | What it is |
|---|---|
| `run.sh` | runs all four tasks |
| `cache.cfg` | the config, with our changes |
| `task4_check.py` | Lecture 4 hand check vs CACTI |
| `plot.py` | Task 2 figure |
| `out/task2.csv` | sweep data |
| `figures/task2_access_vs_capacity.png` | Task 2 plot |

## Results

**Task 1 — baseline**

| Metric | Value |
|---|---|
| Access time | 2.9018 ns |
| Dynamic read energy | 792.9 pJ |
| Leakage | 2250.5 mW (4 banks × 562.63 mW/bank) |
| Area | 11.474 mm² |

Data array 4/2/1, tag array 2/2/2.

**Task 2 — capacity sweep**

| Capacity | Access (ns) | Ndwl/Ndbl/Nspd |
|---|---|---|
| 256 kB | 2.4171 | 4/2/1 |
| 512 kB | 2.4845 | 4/2/1 |
| 1 MB | 2.6338 | 4/2/1 |
| 2 MB | 2.9018 | 4/2/1 |
| 4 MB | 3.5308 | 4/2/1 |
| 8 MB | 4.4727 | 4/4/1 |
| 16 MB | 6.3624 | 2/8/1 |

**Task 3 — objectives**

| Run | `-design objective` | `-Optimize` | Ndwl/Ndbl/Nspd | Access | Area |
|---|---|---|---|---|---|
| Pure delay | 100:0:0:0:0 | NONE | 4/2/1 | 2.8923 ns | 10.970 mm² |
| Pure area | 0:0:0:0:100 | NONE | 2/2/1 | 3.3552 ns | 9.245 mm² |
| ED²P | (ignored) | ED^2 | 4/2/1 | 2.9018 ns | 11.474 mm² |

**Task 4 — bitline delay**

CACTI 406.9 ps, hand calculation 193.7 ps, discrepancy **2.10×**.

## Notes

**`-Optimize` overrides `-design objective`.** The comment in `cache.cfg`
says so. With `"ED^2"` active the weight vector is ignored, so Task 3's
pure-delay and pure-area runs need `"NONE"`. Verified: `ED^2` with the
baseline weight vector gives Ndwl 4, `NONE` with the same vector gives 16.

**Leave `-deviate` as shipped.** Changing it to `1000:...` tightens the
last four fields from 100000 and moves the ED² access time from 2.90 ns
to 6.37 ns.

**Leakage is per bank.** Multiply by 4. Energy is per 64-byte line; per
32-bit word it is 49.6 pJ, which matches Horowitz's 50 pJ figure from
Lecture 1 slide 27.

**Task 2: one gate delay per doubling is not visible.** The increment
grows from 3 to 86 gate delays across the sweep, and the per-doubling
ratio approaches √2 — access time scales with the array's linear
dimension, not logarithmically. `Ndwl` stays at 4 across six doublings,
so CACTI lengthens existing wordlines rather than adding subarrays,
leaving wire delay to dominate.

**Task 3: pure delay and ED²P give the same triple.** They differ one
level down in `Ndsam L2` (2 vs 1). At 2 MB the delay² term dominates the
ED² product, so ED²P settles on the delay-optimal array and optimises the
periphery instead, trading 9.5 ps of access time for 106 pJ.

**Task 4 assumption.** Wire resistance is taken as 12.3 Ω/µm from
ρ = 3.5×10⁻⁸ Ω·m over a 45 × 63 nm cross-section. Cell geometry is read
from CACTI's own `tech_params/45nm.dat` (146 F², aspect 1.46 → 0.45 µm
cell height). C_BL comes out at 179.2 fF, against the 180 fF used in the
Part A netlist.

**Cross-check.** Back out the cell size: data array 10.271 mm² at 54.33 %
array efficiency gives 0.333 µm²/bit, against Intel's published 45 nm 6T
cell of 0.346 µm² — within 4 %.
