#!/usr/bin/env bash
# =====================================================================
# AMCAS Part E - gem5. Runs unattended.
#
#   cd ~/AMCAS/gem5
#   chmod +x run_partE.sh
#   nohup ./run_partE.sh > partE.log 2>&1 &
#   tail -f partE.log        # to watch
#
# Safe to close the terminal after launching with nohup.
#
# Covers Task 1 (4 runs), Task 3 (2 runs), plus the handout's own
# 8MB/14-cycle assumption for comparison (2 runs). ~3-4 hours.
#
# Writes results/summary.csv and results/summary.txt at the end.
# =====================================================================

set -uo pipefail

GEM5=./build/X86/gem5.opt
SE=configs/deprecated/example/se.py
CACHES=configs/common/Caches.py
GAPBS="$HOME/AMCAS/gapbs"
SG="$GAPBS/kron18.sg"
WSG="$GAPBS/kron18.wsg"

[ -x "$GEM5" ] || { echo "gem5.opt not found - run from ~/AMCAS/gem5"; exit 1; }
[ -f "$SG" ]   || { echo "$SG missing - run: cd $GAPBS && ./converter -g 18 -b kron18.sg"; exit 1; }
[ -f "$WSG" ]  || { echo "$WSG missing - run: cd $GAPBS && ./converter -g 18 -w -b kron18.wsg"; exit 1; }

mkdir -p results
[ -f "$CACHES.orig" ] || cp "$CACHES" "$CACHES.orig"

# --- set the three L2 latency fields (lines 73-75 of Caches.py) ---
set_latency () {
  cp "$CACHES.orig" "$CACHES"
  sed -i "73s/tag_latency = 20/tag_latency = $1/"           "$CACHES"
  sed -i "74s/data_latency = 20/data_latency = $1/"         "$CACHES"
  sed -i "75s/response_latency = 20/response_latency = $1/" "$CACHES"
  local got
  got=$(sed -n '73,75p' "$CACHES" | grep -c "= $1")
  [ "$got" = "3" ] || { echo "FATAL: latency edit failed (wanted 3 lines = $1, got $got)"; exit 1; }
  echo "    L2 latency set to $1 cycles"
}

# --- one gem5 run ---
# $1 tag  $2 kernel  $3 l2 size  $4 latency cycles  $5 cpu type  $6 trials
run () {
  local tag="$1" kern="$2" size="$3" lat="$4" cpu="$5" n="$6"
  local graph="$SG"; [ "$kern" = "sssp" ] && graph="$WSG"

  echo "=== $tag :: $kern $size ${lat}cyc $cpu -n$n  ($(date +%H:%M:%S)) ==="
  set_latency "$lat"

  "$GEM5" --outdir="results/$tag" "$SE" \
    --cpu-type="$cpu" --caches --l2cache \
    --l1d_size=32kB --l1i_size=32kB \
    --l2_size="$size" --l2_assoc=8 \
    --mem-type=DDR4_2400_8x8 --mem-size=4GB \
    --cmd="$GAPBS/$kern" \
    --options="-f $graph -n $n" \
    > "results/$tag.out" 2>&1

  if grep -q "Exit code is" "results/$tag.out"; then
    echo "    FAILED - see results/$tag.out"
  else
    echo "    ok  $(grep -m1 '^simSeconds' results/$tag/stats.txt 2>/dev/null | awk '{print "simSeconds="$2}')"
  fi
  # record what was configured, so the CSV cannot drift from reality
  echo "$tag,$kern,$size,$lat,$cpu,$n" >> results/manifest.csv
}

rm -f results/manifest.csv
echo "tag,kernel,l2_size,latency_cyc,cpu,trials" > results/manifest.csv

echo "#####################################################"
echo "# Part E started $(date)"
echo "# SRAM  = 2MB,  6 cycles (CACTI 2.9018 ns @ 2 GHz)"
echo "# MRAM  = 4MB,  4 cycles (NVSim 1.589 ns, 1.78x area)"
echo "# HANDOUT = 8MB, 14 cycles (their 4x / 2x assumption)"
echo "#####################################################"

# ---------------------------------------------------------------------
# Task 1 - both configs, both kernels
# ---------------------------------------------------------------------
run sram_bfs   bfs  2MB  6  O3CPU 5
run mram_bfs   bfs  4MB  4  O3CPU 5
run sram_sssp  sssp 2MB  6  O3CPU 3
run mram_sssp  sssp 4MB  4  O3CPU 3

# ---------------------------------------------------------------------
# Task 3 - TimingSimple. Run both configs on bfs, since which one
# "wins" Task 2 is not known until the runs above are read.
# ---------------------------------------------------------------------
run ts_sram_bfs bfs 2MB  6  TimingSimpleCPU 5
run ts_mram_bfs bfs 4MB  4  TimingSimpleCPU 5

# ---------------------------------------------------------------------
# The handout's own assumption, for the Task 4 discussion
# ---------------------------------------------------------------------
run ho_bfs   bfs  8MB 14 O3CPU 5
run ho_sssp  sssp 8MB 14 O3CPU 3

cp "$CACHES.orig" "$CACHES"
echo "Caches.py restored to stock"

# ---------------------------------------------------------------------
# Collect
# ---------------------------------------------------------------------
{
  echo "tag,kernel,l2_size,latency_cyc,cpu,trials,simSeconds,simInsts,ipc,l2_accesses,l2_missRate,l2_hits"
  tail -n +2 results/manifest.csv | while IFS=, read -r tag kern size lat cpu n; do
    s="results/$tag/stats.txt"
    if [ -f "$s" ]; then
      awk -v p="$tag,$kern,$size,$lat,$cpu,$n" '
        /^simSeconds/{ss=$2} /^simInsts/{si=$2}
        /^system\.cpu\.ipc /{ipc=$2} /^system\.switch_cpus\.ipc /{ipc=$2}
        /^system\.l2\.overallAccesses::total/{a=$2}
        /^system\.l2\.overallMissRate::total/{m=$2}
        /^system\.l2\.overallHits::total/{h=$2}
        END{printf "%s,%s,%s,%s,%s,%s,%s\n",p,ss,si,ipc,a,m,h}' "$s"
    else
      echo "$tag,$kern,$size,$lat,$cpu,$n,MISSING,,,,,"
    fi
  done
} > results/summary.csv

column -s, -t < results/summary.csv > results/summary.txt 2>/dev/null \
  || cp results/summary.csv results/summary.txt

echo
echo "#####################################################"
echo "# Part E finished $(date)"
echo "#####################################################"
cat results/summary.txt
