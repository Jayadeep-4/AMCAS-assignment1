#!/usr/bin/env bash
# =====================================================================
# AMCAS Part C - NVSim, all four tasks.
#
#   ./run.sh          all tasks
#   ./run.sh 2        one task only
#
# Needs: the nvsim binary, stt.cell, stt.cfg, and NVSim's SRAM.cell
# in this directory.
#
# Build note: NVSim needs -std=c++11 on modern gcc, otherwise
# BankWithHtree.cpp fails with "reference to 'data' is ambiguous"
# (collides with std::data from C++17). Fix:
#   sed -i 's/^CXXFLAGS := -Wall/CXXFLAGS := -Wall -std=c++11/' Makefile
# =====================================================================

set -uo pipefail
[ -x ./nvsim ]   || { echo "nvsim binary not here"; exit 1; }
[ -f stt.cfg ]   || { echo "stt.cfg missing"; exit 1; }
[ -f stt.cell ]  || { echo "stt.cell missing"; exit 1; }

WANT="${1:-all}"
mkdir -p out

# data-array results, where the bitcell difference actually shows.
# The cache-level "Write Dynamic Energy" is a tag-path figure and comes
# out identical for both cells, so it is useless for comparison.
dataarray () {
  awk '/CACHE DATA ARRAY/{d=1} /CACHE TAG ARRAY/{d=0} d' "$1" \
  | grep -E "^ -  Read Latency|^ - Write Latency|^ -  Read Dynamic Energy|^ - Write Dynamic Energy|^ - Leakage Power =|Total Area =|Area Efficiency|Subarray Size" \
  | sed 's/.*= *//; s/.*: *//' | tr '\n' '|'
}

show () {  # $1 label, $2 logfile
  printf "%-14s " "$1"
  dataarray "$2" | awk -F'|' '{printf "sub %-20s area %-10s eff %-8s rd %-10s wr %-10s Erd %-11s Ewr %-11s leak %s\n",$1,$2,$3,$4,$5,$6,$7,$8}'
}

run_cell () {  # $1 tag, $2 cellfile
  sed "s|^-MemoryCellInputFile: .*|-MemoryCellInputFile: $2|" stt.cfg > out/$1.cfg
  ./nvsim out/$1.cfg > out/$1.log 2>&1
}

# ---------------------------------------------------------------------
# Task 1 - STT-MRAM vs SRAM, same tool, same config, only the cell
# changes. This is a fairer control than CACTI vs NVSim, because the
# wire model, optimiser and periphery search are held fixed.
# ---------------------------------------------------------------------
if [ "$WANT" = "1" ] || [ "$WANT" = "all" ]; then
  echo "== Task 1: STT-MRAM vs SRAM (NVSim, controlled) =="
  run_cell sram SRAM.cell
  run_cell stt  stt.cell
  show "SRAM"     out/sram.log
  show "STT-MRAM" out/stt.log
  echo
  echo "  cache level (incl. tag array):"
  for f in sram stt; do
    printf "  %-10s " "$f"
    grep -E "^ - Total Area|^ - Cache Hit Latency|^ - Cache Write Latency|^ - Cache Hit Dynamic|^ - Cache Total Leakage" out/$f.log \
      | head -5 | sed 's/.*= *//' | tr '\n' ' '; echo
  done
fi

# ---------------------------------------------------------------------
# Task 3 - TMR 2:1 -> 3:1
# ---------------------------------------------------------------------
if [ "$WANT" = "3" ] || [ "$WANT" = "all" ]; then
  echo
  echo "== Task 3: TMR ratio =="
  for R in "tmr2:3000:6000" "tmr3:4000:12000"; do
    n="${R%%:*}"; r="${R#*:}"; on="${r%%:*}"; off="${r#*:}"
    sed -e "s|^-ResistanceOn (ohm): .*|-ResistanceOn (ohm): $on|" \
        -e "s|^-ResistanceOff (ohm): .*|-ResistanceOff (ohm): $off|" stt.cell > out/$n.cell
    run_cell $n out/$n.cell
    show "$n ${on}/${off}" out/$n.log
  done
  echo "  sense-amp latency (does it respond to TMR?):"
  for n in tmr2 tmr3; do
    printf "  %-6s " "$n"
    awk '/CACHE DATA ARRAY/{d=1} /CACHE TAG ARRAY/{d=0} d' out/$n.log \
      | grep -E "Bitline Latency|Senseamp Latency" | sed 's/.*= *//' | tr '\n' ' '; echo
  done
fi

# ---------------------------------------------------------------------
# Task 4 - halve ResetCurrent. Run twice: once with AccessCMOSWidth
# pinned at 6 F as the handout gives it, once scaled with the current.
# ---------------------------------------------------------------------
if [ "$WANT" = "4" ] || [ "$WANT" = "all" ]; then
  echo
  echo "== Task 4: reset current -> access transistor -> cell area =="
  for P in "I200_W6:200:6" "I100_W6:100:6" "I100_W3:100:3"; do
    n="${P%%:*}"; r="${P#*:}"; ic="${r%%:*}"; w="${r#*:}"
    sed -e "s|^-ResetCurrent (uA): .*|-ResetCurrent (uA): $ic|" \
        -e "s|^-SetCurrent (uA): .*|-SetCurrent (uA): $ic|" \
        -e "s|^-AccessCMOSWidth (F): .*|-AccessCMOSWidth (F): $w|" stt.cell > out/$n.cell
    run_cell $n out/$n.cell
    show "$n" out/$n.log
  done
  echo "  I100_W6 vs I200_W6: area unchanged -> CellArea is pinned in the .cell file"
  echo "  I100_W3 vs I200_W6: area drops     -> the coupling, once width can follow"
fi

echo
echo "logs in out/"
