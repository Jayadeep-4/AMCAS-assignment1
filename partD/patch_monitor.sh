#!/usr/bin/env bash
# =====================================================================
# Part D step 1 - insert a CommMonitor on gem5's L2 memory-side port.
#
#   cd ~/AMCAS/gem5
#   ./patch_monitor.sh on     # add the monitor
#   ./patch_monitor.sh off    # restore stock
#
# The handout says "the CommMonitor on gem5's L2 memory-side port
# produces exactly this format". There is no flag for it, so the
# connection in configs/common/CacheConfig.py has to be rewritten:
#
#   before:  system.l2.mem_side = system.membus.cpu_side_ports
#   after:   L2 -> CommMonitor -> membus, with a MemTraceProbe attached
#
# Enable at runtime with:  --l2-trace-file=l2miss.trc.gz
# (env var L2_TRACE_FILE, read by the patched code)
# =====================================================================

set -uo pipefail
CC=configs/common/CacheConfig.py
[ -f "$CC" ] || { echo "run this from ~/AMCAS/gem5"; exit 1; }
[ -f "$CC.orig" ] || cp "$CC" "$CC.orig"

OLD='        system.l2.mem_side = system.membus.cpu_side_ports'

NEW='        # --- Part D: CommMonitor on the L2 memory-side port ---
        # Captures the L2 miss stream for Ramulator. Enabled by setting
        # the L2_TRACE_FILE environment variable.
        import os

        _trace = os.environ.get("L2_TRACE_FILE", "")
        if _trace:
            system.l2_monitor = CommMonitor()
            system.l2_monitor.trace = MemTraceProbe(
                trace_file=_trace, trace_compress=True
            )
            system.l2.mem_side = system.l2_monitor.cpu_side_port
            system.l2_monitor.mem_side_port = system.membus.cpu_side_ports
            print(f"Part D: L2 CommMonitor tracing to {_trace}")
        else:
            system.l2.mem_side = system.membus.cpu_side_ports'

case "${1:-}" in
  on)
    cp "$CC.orig" "$CC"
    python3 - "$CC" <<PY
import sys
p = sys.argv[1]
s = open(p).read()
old = '''$OLD'''
new = '''$NEW'''
if old not in s:
    sys.exit("FATAL: could not find the L2 mem_side line in " + p)
open(p, "w").write(s.replace(old, new, 1))
print("patched", p)
PY
    grep -n "l2_monitor" "$CC" | head -3
    ;;
  off)
    cp "$CC.orig" "$CC"
    echo "restored stock $CC"
    grep -n "system.l2.mem_side" "$CC"
    ;;
  *)
    echo "usage: $0 on|off"; exit 1 ;;
esac
