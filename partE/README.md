# Part E — gem5: does the program run faster?

Two GAPBS kernels on three L2 configurations and two CPU models.
Tasks 1–3; Task 4 is the written argument.

## Requirements

gem5 25.1.0.1, `scons build/X86/gem5.opt -j$(nproc)`. Builds on gcc 15.2
(warns that only v11–14.2 are supported; harmless).

GAPBS, **statically linked** — SE mode emulates syscalls rather than
booting Linux, so a dynamic binary dies in the loader:

```bash
git clone https://github.com/sbeamer/gapbs && cd gapbs
make CXX_FLAGS="-std=c++11 -O3 -Wall -static"
file bfs        # must say "statically linked"
```

**Pre-build the graphs outside gem5** — required, see Notes:

```bash
./converter -g 18 -b kron18.sg       # 32.5 MB, unweighted, bfs
./converter -g 18 -w -b kron18.wsg   # 63.0 MB, weighted, sssp
```

`-w` is a flag, not a filename, despite the help text reading `-w <file>`.
sssp rejects `.sg` with `.sg not allowed for weighted graphs`, exit 251.

## Running

```bash
chmod +x run_partE.sh
nohup ./run_partE.sh > partE.log 2>&1 &
tail -f partE.log
```

Nine runs, about 3–4 hours. Writes `summary.csv`.

## The two numbers carried in from Parts B and C

| | Source | Value | Cycles @ 2 GHz |
|---|---|---|---|
| SRAM L2 hit latency | CACTI, Part B | 2.9018 ns | 6 |
| MRAM L2 hit latency | NVSim, Part C | 1.589 ns | 4 |
| Iso-area capacity | NVSim areas, 6.393 / 3.590 mm² | 1.78× | 4 MB |

`--l2-hit-latency` **is not a valid `se.py` option**, despite appearing in
both the assignment and Interlude slide 27. Verified:
`se.py --help | grep -i latency` returns nothing. The latency is set in
`configs/common/Caches.py` lines 73–75 (`tag_latency`, `data_latency`,
`response_latency`), which `run_partE.sh` edits and restores per run.

gem5's default `--cpu-clock` is `2GHz` (`configs/common/Options.py`), so
one cycle is 0.5 ns.

The handout's 8 MB / 14 cycle configuration is also run, because its
assumed "4× larger, ~2× slower" does not match our measurements (1.78×
larger, 1.5× faster).

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
| O3 | bfs | 1.179× | 1.369× |
| O3 | sssp | 1.171× | 1.007× |
| TimingSimple | bfs | 1.156× | 1.274× |

O3 → TimingSimple slowdown: 3.094× at 2 MB / 6 cyc, 3.326× at 8 MB / 14 cyc.

## Notes

**Pre-building the graph is required, not an optimisation.** With `-g 18`
GAPBS generates the Kronecker graph inside the simulation:

| | `-g 18` | `-f kron18.sg` |
|---|---|---|
| Setup | 3.72 s | 0.00145 s |
| Traversal share of program | 0.4 % | 97 % |

Our first attempt fast-forwarded 500 M instructions and still landed
entirely inside graph generation: 15,791 L2 accesses and a 100 % miss
rate. With a pre-built graph the same window gives 1.94 M L2 accesses and
a 62.9 % miss rate. No fast-forward is then needed; the whole program is
73 ms simulated.

**After a CPU switch, O3 stats live under `system.switch_cpus`**, not
`system.cpu`, which reads `nan`. Only relevant if you use
`--fast-forward`; the final runs do not.

**Trial counts differ by kernel.** bfs `-n 5`, sssp `-n 3`, because a sssp
trial is ~7× longer (123 ms against 17 ms). Trial times were consistent
with no cold-start outlier, so the first trial was not discarded.

## Files

| File | |
|---|---|
| `run_partE.sh` | all nine runs, edits and restores `Caches.py` |
| `summary.csv` | extracted results |
