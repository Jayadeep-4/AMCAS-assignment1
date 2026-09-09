#!/usr/bin/env bash
# =====================================================================
# AMCAS Part B - all four tasks, one command.
#
#   ./run.sh          all tasks
#   ./run.sh 2        one task only
#
# Needs: the cacti binary and cache.cfg in this directory.
# cache.cfg is never modified - each run works on a temp copy.
# =====================================================================

set -uo pipefail
[ -x ./cacti ]    || { echo "cacti binary not here. run: make -j"; exit 1; }
[ -f cache.cfg ]  || { echo "cache.cfg missing"; exit 1; }

WANT="${1:-all}"
mkdir -p out

# pull the reportable numbers out of a CACTI run
report () {
  awk '
    /^    Access time/                          {t=$4}
    /^    Cycle time/                           {c=$4}
    /^    Total dynamic read energy per access/ {e=$8}
    /^    Total leakage power of a bank/        {if(!l) l=$8}
    /^    Cache height x width/                 {a=$6*$8}
    /^    Best Ndwl/{dwl=$4} /^    Best Ndbl/{dbl=$4} /^    Best Nspd/{spd=$4}
    END{printf "%-9.4f %-9.4f %-9.1f %-9.1f %-8.3f %s/%s/%s\n",
        t, c, e*1000, l*4, a, dwl, dbl, spd}'
}

HDR="access_ns cycle_ns  read_pJ   leak_mW   area_mm2 Ndwl/Ndbl/Nspd"

# ---------------------------------------------------------------------
# Task 1 - baseline. Keep the full log: Task 4 reads the bitline delay
# out of it.
# ---------------------------------------------------------------------
if [ "$WANT" = "1" ] || [ "$WANT" = "all" ]; then
  echo "== Task 1: 2 MB baseline =="
  rm -f out.csv
  ./cacti -infile cache.cfg > out/task1.log 2>&1
  echo "          $HDR"
  printf "%-9s " "2MB"; report < out/task1.log
fi

# ---------------------------------------------------------------------
# Task 2 - capacity sweep, 256 kB -> 16 MB.
# ---------------------------------------------------------------------
if [ "$WANT" = "2" ] || [ "$WANT" = "all" ]; then
  echo
  echo "== Task 2: capacity sweep =="
  echo "size_KB   $HDR"
  echo "capacity_KB,log2_bytes,access_ns,cycle_ns,read_pJ,area_mm2" > out/task2.csv
  for S in 262144 524288 1048576 2097152 4194304 8388608 16777216; do
    sed "s|^-size (bytes) .*|-size (bytes) $S|" cache.cfg > out/s.cfg
    rm -f out.csv
    ./cacti -infile out/s.cfg > out/size_$S.log 2>&1
    printf "%-9s " "$((S/1024))"; report < out/size_$S.log
    awk -v s=$S '
      /^    Access time/{t=$4} /^    Cycle time/{c=$4}
      /^    Total dynamic read energy per access/{e=$8}
      /^    Cache height x width/{a=$6*$8}
      END{printf "%d,%d,%.4f,%.4f,%.1f,%.3f\n", s/1024, log(s)/log(2), t, c, e*1000, a}' \
      out/size_$S.log >> out/task2.csv
  done
  echo "  -> out/task2.csv"
fi

# ---------------------------------------------------------------------
# Task 3 - three objectives. ED^2P needs Optimize "ED^2"; the pure-delay
# and pure-area runs need "NONE", because the Optimize tag overrides the
# weight vector. -deviate is left exactly as shipped.
# ---------------------------------------------------------------------
if [ "$WANT" = "3" ] || [ "$WANT" = "all" ]; then
  echo
  echo "== Task 3: objectives =="
  echo "objective $HDR"
  for T in "delay:NONE:100:0:0:0:0" "area:NONE:0:0:0:0:100" "ed2:ED^2:0:0:0:100:0"; do
    n="${T%%:*}"; r="${T#*:}"; opt="${r%%:*}"; wv="${r#*:}"
    sed -e "s|^-Optimize ED or ED.*|-Optimize ED or ED^2 (ED, ED^2, NONE): \"$opt\"|" \
        -e "s|^-design objective .*|-design objective (weight delay, dynamic power, leakage power, cycle time, area) $wv|" \
        cache.cfg > out/o_$n.cfg
    rm -f out.csv
    ./cacti -infile out/o_$n.cfg > out/obj_$n.log 2>&1
    printf "%-9s " "$n"; report < out/obj_$n.log
  done
fi

# ---------------------------------------------------------------------
# Task 4 - bitline delay, hand check in task4_check.py
# ---------------------------------------------------------------------
if [ "$WANT" = "4" ] || [ "$WANT" = "all" ]; then
  echo
  echo "== Task 4: bitline delay =="
  [ -f out/task1.log ] || { echo "  run task 1 first"; exit 1; }
  grep -m1 "Bitline delay" out/task1.log | sed 's/^\s*/  CACTI  /'
  grep -m1 "Subarray Height" out/task1.log | sed 's/^\s*/  /'
  [ -f task4_check.py ] && { echo; python3 task4_check.py | sed 's/^/  /'; }
fi

rm -f out/s.cfg out.csv
echo
echo "logs in out/"
