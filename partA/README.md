# Part A — ngspice: 6T SRAM read margin

Reads a 6T SRAM cell at 45 nm and measures the bitline read margin.
Covers all four tasks of Assignment 1 Part A.

## Requirements

```bash
sudo apt install ngspice
```

Tested with ngspice 42 (Ubuntu 24.04+). Older versions may not support
`alterparam`, used in the Task 3 sweep.

`45nm_bulk.txt` (PTM 45 nm bulk BSIM4, from ptm.asu.edu) is included so
results are reproducible without any downloads.

## Running

```bash
chmod +x run.sh
./run.sh          # all four tasks, plots to out/*.svg
./run.sh 2        # one task only
VIEW=1 ./run.sh 1 # interactive ngspice plot window
```

`run.sh` generates a fresh netlist per task, because the access
transistor width and `.temp` both change between tasks.

## Files

| File | What it is |
|---|---|
| `run.sh` | generates and runs all four tasks |
| `45nm_bulk.txt` | PTM 45 nm bulk BSIM4 model card |
| `figures/task1.svg` | Task 1 — v(q), v(qb), nominal cell |
| `figures/task2.svg` | Task 2 — v(q), v(qb), wide access devices |
| `figures/task3a.svg` | Task 3 — ΔV vs V_DD, 1.1 → 0.6 V |
| `figures/task3b.svg` | Task 3 — extended to 0.25 V, finds the 25 mV crossing |
| `figures/task4.svg` | Task 4 — v(q), v(qb) at 85 °C |

`out/` is generated at runtime and gitignored.

## Circuit

45 nm, V_DD = 1.1 V, Q = 0 and QB = 1 stored. Bitlines precharged to
V_DD on 180 fF. Wordline rises at 1.05 ns; ΔV(BL,BLB) measured at 2.0 ns.

Cell ratio W(MN1)/W(MA1) = 0.20/0.16 = **1.25**, below the ≥1.5 normally
required for read stability — deliberately marginal.

DC trip point of the q→qb inverter: **434 mV**. Read disturb is judged
against this.

## Results

| Task | Condition | ΔV @ 2 ns | qmax | q @ 3.9 ns |
|---|---|---|---|---|
| 1 | 0.16 µm, 27 °C | 540.8 mV | 270.3 mV | 31.8 mV |
| 2 | 0.24 µm, 27 °C | 498.6 mV | 475.1 mV | 22.5 mV |
| 2 | 0.24 µm, 85 °C, 400 fF | 77.3 mV | 586.0 mV | 291.3 mV |
| 4 | 0.16 µm, 85 °C | 514.8 mV | 300.1 mV | 38.6 mV |

Task 3 — the 25 mV sense-amp offset is crossed at **V_DD = 0.32 V**
(measured at 2.0 ns).

## Notes

**The 69 mV in Lecture 1 is a DRAM number**, from 1T1C charge sharing
with the bitline at V_DD/2. The 6T read precharges to full V_DD and
discharges with a real current, so 540 mV vs 69 mV is expected.

**Task 2's failure only shows on a realistic bitline.** At 180 fF the
cell recovers. At 400 fF and 85 °C, q sits at 291 mV after 4 ns — the
read destroys the stored value.

**Task 3 needs the nominal cell.** Left at Task 2's 0.24 µm access
devices, the sweep comes out non-monotonic because read disturb chokes
the discharge current at high V_DD.

**Ignore the first 0.4 ns of any plot.** `uic` skips the DC operating
point, so the transient starts unconverged (v(qb) reads up to 1.99 V). It
settles well before the wordline rises at 1.05 ns, so all measurements
are valid.

Results are stable to seven significant figures under `reltol=1e-5,
abstol=1e-18`. The netlist is symmetric, so it carries no device
mismatch — the 0.32 V crossing is a nominal figure.
