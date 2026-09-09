#!/usr/bin/env python3
"""Part B Task 4 - compare Lecture 4's 0.38*Rsh*Cw*L^2 against CACTI."""

# geometry from CACTI tech_params/45nm.dat: area_cell 146 F^2, aspect 1.46
b_h = (146 * 0.045**2 / 1.46) ** 0.5      # cell height, um
L   = 512 * b_h                           # bitline length, um (512 cells, Lecture 4)

# per-unit-length values
Rsh = 3.5e-8 / (45e-9 * 63e-9) / 1e6      # ohm/um, min-width local Cu 45x63 nm
Cw  = 0.35e-15 / b_h                      # F/um, from Lecture 4's 0.35 fF per cell

hand  = 0.38 * Rsh * Cw * L**2 * 1e12     # ps
cacti = 406.901                           # ps, from task1.log

print(f"hand   {hand:6.1f} ps")
print(f"CACTI  {cacti:6.1f} ps")
print(f"ratio  {cacti/hand:6.2f}x")
