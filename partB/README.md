# Part B — CACTI: 2 MB SRAM L2 at 45 nm

Sizes a 2 MB 8-way L2 and sweeps capacity and design objective.
Tasks 1–4.

## Requirements

CACTI 7 from github.com/HewlettPackard/cacti, `make -j`. Builds clean on
gcc 13 and 15 with no patches (many warnings, no errors).

Put `run.sh`, `plot.py`, `task4_check.py` and `cache.cfg` next to the
`cacti` binary.

## Running

```bash
chmod +x run.sh
./run.sh            # all four tasks
./run.sh 2          # one task
python3 plot.py     # Task 2 figure
```

`cache.cfg` is never modified — each run works on a temp copy in `out/`.

## Config

Only the parameters the assignment lists were changed from the shipped
`cache.cfg`: size 2097152, block 64, associativity 8, 1 read-write port,
4 UCA banks, technology 0.045, temperature 350 K, cache type, itrs-hp data
cell and periphery, ED^2, objective 0:0:0:100:0.

Everything else left at the shipped default, including
`-Wire signaling "Global_30"` (uncommented as shipped) and
`-Add ECC "true"`.

## Results

**Task 1**

| Metric | Value |
|---|---|
| Access time | 2.9018 ns |
| Cycle time | 2.6523 ns |
| Dynamic read energy | 792.9 pJ |
| Leakage | 2250.5 mW (4 banks × 562.63 mW/bank) |
| Area | 11.474 mm² (2.21344 × 5.18388) |

Data array 4/2/1, tag array 2/2/2. Data array 10.271 mm² at 54.33 % array
efficiency.

**Task 2 — capacity sweep** (full data in `task2.csv`)

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
| pure delay | 100:0:0:0:0 | NONE | 4/2/1 | 2.8923 ns | 10.970 mm² |
| pure area | 0:0:0:0:100 | NONE | 2/2/1 | 3.3552 ns | 9.245 mm² |
| ED²P | (ignored) | ED^2 | 4/2/1 | 2.9018 ns | 11.474 mm² |
| pure cycle time | 0:0:0:100:0 | NONE | 16/2/1 | 3.3019 ns | 12.976 mm² |

**Task 4 — bitline delay**

CACTI 406.9 ps, hand calculation 193.7 ps, **2.10×**. Data-array bitline
length 230.4 µm (512 cells × 0.450 µm cell height, from
`tech_params/45nm.dat`: 146 F², aspect 1.46). C_BL = 179.2 fF at Lecture
4's 0.35 fF per cell. R_BL assumed 12.3 Ω/µm from ρ = 3.5×10⁻⁸ Ω·m over a
45 × 63 nm cross-section. `task4_check.py` reproduces it.

## Notes

**`-Optimize` overrides `-design objective`** — the comment in `cache.cfg`
says so. With `"ED^2"` active the weight vector is ignored, so Task 3's
pure-delay and pure-area runs need `"NONE"`. Verified: `ED^2` with the
baseline weight vector gives Ndwl 4, `NONE` with the same vector gives 16.

**Leave `-deviate` as shipped.** Changing it to `1000:...` tightens the
last four fields from 100000 and moves the ED² access time from 2.90 ns to
6.37 ns.

**Leakage is reported per bank.** Multiply by 4. Energy is per 64-byte
line; per 32-bit word it is 49.6 pJ.

## Files

| File | |
|---|---|
| `run.sh` | all four tasks |
| `cache.cfg` | the config |
| `task4_check.py` | Lecture 4 hand check |
| `plot.py` | Task 2 figure |
| `task2.csv` | sweep data |
| `figures/task2_access_vs_capacity.png` | Task 2 plot |
