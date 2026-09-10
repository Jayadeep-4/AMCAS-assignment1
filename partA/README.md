# Part A — ngspice: 6T SRAM read margin

Reads a 6T SRAM cell at 45 nm and measures the bitline read margin.
Tasks 1–4.

## Requirements

```bash
sudo apt install ngspice
```

Tested on ngspice 42. Older versions may lack `alterparam`, used in the
Task 3 sweep.

`45nm_bulk.txt` (PTM 45 nm bulk BSIM4, ptm.asu.edu) is included so the
results reproduce without downloads.

## Running

```bash
chmod +x run.sh
./run.sh            # all four tasks, plots to out/*.svg
./run.sh 2          # one task
VIEW=1 ./run.sh 1   # interactive ngspice plot window
```

A fresh netlist is generated per task, because the access transistor width
and `.temp` both change between tasks.

## Circuit

45 nm, V_DD = 1.1 V, Q = 0 / QB = 1 stored, bitlines precharged to V_DD on
180 fF, wordline rises at 1.05 ns, ΔV(BL,BLB) measured at 2.0 ns.

Cell ratio W(MN1)/W(MA1) = 0.20/0.16 = 1.25.

## Results

DC trip point of the q→qb inverter: **434 mV**.

| Task | Condition | ΔV @ 2 ns | qmax | q @ 3.9 ns |
|---|---|---|---|---|
| 1 | 0.16 µm, 27 °C | 540.8 mV | 270.3 mV | 31.8 mV |
| 2 | 0.24 µm, 27 °C | 498.6 mV | 475.1 mV | 22.5 mV |
| 2 | 0.24 µm, 85 °C, 400 fF | 77.3 mV | 586.0 mV | 291.3 mV |
| 4 | 0.16 µm, 85 °C | 514.8 mV | 300.1 mV | 38.6 mV |

Task 3: the 25 mV sense-amp offset is crossed at **V_DD = 0.32 V**,
measured at 2 ns. Sweep data in `out/`.

## Notes

**Ignore the first 0.4 ns of any plot.** `uic` skips the DC operating
point, so the transient starts unconverged and v(qb) briefly reads up to
1.99 V. It settles before the wordline rises at 1.05 ns, so all
measurements are valid.

**The 400 fF row is an addition**, not in the handout. At the handout's
180 fF the cell always recovers and Task 2's expected failure never
appears.

**No device mismatch.** The netlist is symmetric, so the 0.32 V crossing
is a nominal figure.

Results are stable to seven significant figures under `reltol=1e-5,
abstol=1e-18`.

## Files

| File | |
|---|---|
| `run.sh` | generates and runs all four tasks |
| `45nm_bulk.txt` | PTM 45 nm bulk BSIM4 model card |
| `figures/*.svg` | task1, task2, task3a, task3b, task4 |

`out/` is generated at runtime and gitignored.
