#!/usr/bin/env bash
# =====================================================================
# AMCAS Part A - four tasks, one command.
#
#   ./run.sh          run all four, save plots as SVG
#   ./run.sh 2        run only task 2
#   VIEW=1 ./run.sh 1 run task 1 and open the plot window
#
# Needs: ngspice and 45nm_bulk.txt in this directory. Nothing else.
#
# Why a script: the access transistor width and .temp both change
# between tasks. Editing them by hand in one netlist is how you end up
# running task 3 on the task 2 cell.
# =====================================================================

set -uo pipefail
[ -f 45nm_bulk.txt ] || { echo "45nm_bulk.txt missing"; exit 1; }

WANT="${1:-all}"
mkdir -p out

# ---- device section: $1 = access width, $2 = temp ----
devices () {
cat << EOF
* AMCAS Part A - 6T read - W_access=$1  T=$2 C
.include 45nm_bulk.txt
.temp $2
.param VDD=1.1
.param VBL='VDD'
Vdd vdd 0 'VDD'
Vwl wl  0 PWL(0 0 1n 0 1.05n 'VDD')
MP1 qb q  vdd vdd pmos W=0.15u L=0.045u
MN1 qb q  0   0   nmos W=0.20u L=0.045u
MP2 q  qb vdd vdd pmos W=0.15u L=0.045u
MN2 q  qb 0   0   nmos W=0.20u L=0.045u
MA1 bl  wl q  0 nmos W=$1 L=0.045u
MA2 blb wl qb 0 nmos W=$1 L=0.045u
Cbl  bl  0 180f IC='VBL'
Cblb blb 0 180f IC='VBL'
.ic v(q)=0 v(qb)='VDD'
EOF
}

# ---- transient tasks (1, 2, 4) ----
# $1 = task tag, $2 = access width, $3 = temp
transient_task () {
  local tag="$1" wacc="$2" temp="$3"
  { devices "$wacc" "$temp"
    cat << EOF
.control
  tran 5p 4n uic
  let dv_vec = v(blb) - v(bl)
  meas tran dv     FIND dv_vec AT=2n
  meas tran qmax   MAX  v(q)  FROM=1n TO=4n
  meas tran qbmin  MIN  v(qb) FROM=1.05n TO=4n
  meas tran qend   FIND v(q)  AT=3.9n
  wrdata out/${tag}.dat v(bl) v(blb) v(q) v(qb)
EOF
    if [ "${VIEW:-0}" = "1" ]; then
      echo "  plot v(q) v(qb)"
    else
      echo "  set hcopydevtype = svg"
      echo "  hardcopy out/${tag}.svg v(q) v(qb)"
    fi
    echo ".endc"
    echo ".end"
  } > "out/${tag}.cir"

  echo "=== $tag  (W_acc=$wacc, T=$temp C) ==="
  if [ "${VIEW:-0}" = "1" ]; then
    ngspice "out/${tag}.cir"
  else
    ngspice -b "out/${tag}.cir" 2>&1 | grep -E "^(dv|qmax|qbmin|qend)" | sed 's/^/  /'
  fi
}

# ---- sweep task (3) ----
# $1 = tag, $2 = start V, $3 = step V, $4 = number of points
sweep_task () {
  local tag="$1" start="$2" step="$3" n="$4"
  { devices 0.16u 27
    cat << EOF
.control
  let vdd_results = vector($n)
  let dv_results  = vector($n)
  let i = 0
  while i < $n
    let vv = $start - $step*i
    alterparam VDD = \$&vv
    reset
    tran 5p 4n uic
    let dv_vec = v(blb) - v(bl)
    meas tran dv_temp FIND dv_vec AT=2n
    let vdd_results[i] = \$&vv
    let dv_results[i]  = \$&dv_temp
    let i = i + 1
  end
  print vdd_results
  print dv_results
EOF
    if [ "${VIEW:-0}" = "1" ]; then
      echo "  plot dv_results vs vdd_results"
    else
      echo "  set hcopydevtype = svg"
      echo "  hardcopy out/${tag}.svg dv_results vs vdd_results"
    fi
    echo ".endc"
    echo ".end"
  } > "out/${tag}.cir"

  echo "=== $tag  (VDD $start V, step $step V, $n points) ==="
  if [ "${VIEW:-0}" = "1" ]; then
    ngspice "out/${tag}.cir"
  else
    # pair up the two printed vectors into VDD / dV columns
    ngspice -b "out/${tag}.cir" 2>&1 \
      | awk '/^Index +vdd_results/{m=1;next} /^Index +dv_results/{m=2;next}
             /^[0-9]+\t/{ if(m==1) v[++a]=$2; else if(m==2) d[++b]=$2 }
             END{ printf "  %-8s %s\n","VDD_V","dV_mV";
                  for(k=1;k<=a;k++) printf "  %-8.3f %8.3f%s\n", v[k], d[k]*1000,
                                     (d[k]*1000<25 ? "   <-- below 25 mV" : "") }'
  fi
}

# ---------------------------------------------------------------------
case "$WANT" in
  1|all) transient_task task1 0.16u 27 ;;
esac
case "$WANT" in
  2|all) transient_task task2 0.24u 27 ;;
esac
case "$WANT" in
  3|all) sweep_task task3a 1.10 0.05 11     # assignment range
         sweep_task task3b 0.60 0.01 36 ;;  # extended, finds the crossing
esac
case "$WANT" in
  4|all) transient_task task4 0.16u 85 ;;
esac

[ "${VIEW:-0}" = "1" ] || { echo; echo "plots: out/*.svg   waveforms: out/*.dat"; }
