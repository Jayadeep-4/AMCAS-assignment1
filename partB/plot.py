#!/usr/bin/env python3
"""Part B Task 2 plot. Run ./run.sh first."""
import csv
import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt

rows = list(csv.DictReader(open("out/task2.csv")))
x   = [int(r["log2_bytes"]) for r in rows]
y   = [float(r["access_ns"]) for r in rows]
lab = [f'{int(r["capacity_KB"])//1024}MB' if int(r["capacity_KB"]) >= 1024
       else f'{r["capacity_KB"]}kB' for r in rows]

FO4 = 0.022                                  # ns, one gate delay at 45 nm
ref = [y[0] + FO4 * (v - x[0]) for v in x]

fig, ax = plt.subplots(figsize=(7, 4.5))
ax.plot(x, y, "o-", lw=1.8, label="CACTI access time")
ax.plot(x, ref, "s--", lw=1.4, color="gray",
        label=f"one gate delay per doubling ({FO4*1000:.0f} ps)")
for a, b, t in zip(x, y, lab):
    ax.annotate(t, (a, b), textcoords="offset points",
                xytext=(0, 8), ha="center", fontsize=8)

ax.set_xlabel(r"$\log_2$(capacity in bytes)")
ax.set_ylabel("access time (ns)")
ax.set_title("45 nm, 8-way, 64 B lines, 4 banks")
ax.set_xticks(x)
ax.grid(alpha=0.3)
ax.legend(fontsize=9)
fig.tight_layout()
fig.savefig("figures/task2_access_vs_capacity.png", dpi=160)
print("wrote figures/task2_access_vs_capacity.png")
plt.show()
