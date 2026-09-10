#!/usr/bin/env bash
# =====================================================================
# AMCAS Part D - DRAMsim3, all four tasks.
#
#   cd ~/AMCAS/DRAMsim3
#   ./run_partD.sh ~/AMCAS/gem5/l2miss.trace
#
# Why DRAMsim3 and not Ramulator 2.0: the handout's interface
# (./ramulator2 -f ddr4.yaml) no longer exists. Ramulator 2.1 builds a
# Python module instead, and in that API the address-mapper and
# channel-count settings Tasks 3 and 4 need had no observable effect -
# all traffic landed on one channel whatever the setting. DRAMsim3
# exposes both as plain INI fields and responds to both. The assignment
# lists DRAMsim3 as the sanctioned alternative.
#
# Build:  git clone https://github.com/umd-memsys/DRAMsim3
#         cd DRAMsim3 && make -j$(nproc)
# =====================================================================

set -uo pipefail

TRACE="${1:-}"
[ -n "$TRACE" ] || { echo "usage: $0 <dramsim3-format trace>"; exit 1; }
[ -f "$TRACE" ] || { echo "trace not found: $TRACE"; exit 1; }
[ -x ./dramsim3main.out ] || { echo "run from the DRAMsim3 dir after 'make -j'"; exit 1; }

BASE=configs/DDR4_8Gb_x8_3200.ini
[ -f "$BASE" ] || { echo "$BASE missing"; exit 1; }

CYCLES="${CYCLES:-2000000}"
mkdir -p out

# $1 tag  $2 channels  $3 address_mapping  $4 row_buf_policy
run () {
  local tag="$1" ch="$2" am="$3" rp="$4"
  sed -e "s/^channels = .*/channels = $ch/" \
      -e "s/^address_mapping = .*/address_mapping = $am/" \
      -e "s/^row_buf_policy = .*/row_buf_policy = $rp/" \
      "$BASE" > "out/$tag.ini"
  rm -rf "out/$tag" && mkdir -p "out/$tag"
  ./dramsim3main.out "out/$tag.ini" -t "$TRACE" -o "out/$tag" -c "$CYCLES" \
      > "out/$tag.log" 2>&1

  printf "  %-26s ch=%s %-13s %-10s " "$tag" "$ch" "$am" "$rp"
  python3 - "out/$tag/dramsim3.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("no stats:", e); raise SystemExit
chans = list(d.values())
rd  = sum(c.get("num_reads_done", 0)  for c in chans)
wr  = sum(c.get("num_writes_done", 0) for c in chans)
rh  = sum(c.get("num_read_row_hits", 0) + c.get("num_write_row_hits", 0)
          for c in chans)
cyc = max(c.get("num_cycles", 0) for c in chans)
# average_read_latency is per channel; weight by that channel's reads
num = sum((c.get("average_read_latency") or 0) * c.get("num_reads_done", 0)
          for c in chans)
lat = num / rd if rd else 0.0
tot = rd + wr
print(f"rd={rd:<8} wr={wr:<7} rowhit={rh/tot if tot else 0:>6.2%} "
      f"avg_rd_lat={lat:>8.2f} cycles={cyc}")
PY
}

echo "trace: $TRACE   (simulating $CYCLES cycles)"
echo
echo "== Task 1: baseline =="
run baseline 1 rochrababgco OPEN_PAGE

echo
echo "== Task 2: row-buffer locality =="
echo "  DRAMsim3's command queue is FR-FCFS by construction, with no FCFS"
echo "  switch. CLOSE_PAGE removes row reuse between accesses, which is"
echo "  the effect the task asks you to quantify."
run open_page  1 rochrababgco OPEN_PAGE
run close_page 1 rochrababgco CLOSE_PAGE

echo
echo "== Task 3: address mapping, row bits below bank bits =="
echo "  The mapping is six 2-char fields, MSB first:"
echo "    rochrababgco = ro ch ra ba bg co   (row highest)"
echo "    chrabgbaroco = ch ra bg ba ro co   (row below bank)"
run row_above_bank 1 rochrababgco OPEN_PAGE
run row_below_bank 1 chrabgbaroco OPEN_PAGE

echo
echo "== Task 4: double the channel count =="
run ch1 1 rochrababgco OPEN_PAGE
run ch2 2 rochrababgco OPEN_PAGE

cat <<'EOF'

Reading the output
------------------
rd/wr        requests completed inside the simulated cycle budget
rowhit       row-buffer hit rate over completed requests
avg_rd_lat   average read latency, memory cycles

Timing constants for the Task 2 write-up, from the config:
  tRCD = 22   tRP = 22   tRAS = 52   tCK = 0.625 ns
A row miss costs tRP to close the open row plus tRCD to activate the new
one, so 44 cycles on top of the column access - which is what the
latency delta should reconcile against.

If rd is far below the trace length, raise the budget:  CYCLES=8000000 ./run_partD.sh ...
EOF
