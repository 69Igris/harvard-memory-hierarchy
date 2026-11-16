#!/usr/bin/env bash
# ============================================================================
# run_all.sh - assemble every program, simulate it on BOTH memory
#              organisations, self-check, and collect the PERF results.
# Requires: python3, iverilog/vvp
# Usage   : cd sim && ./run_all.sh
# ============================================================================
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/sw/build"
OUT="$ROOT/sim/out"
mkdir -p "$BUILD" "$OUT"

RTL="$ROOT/rtl/pc.v $ROOT/rtl/imem.v $ROOT/rtl/dmem.v $ROOT/rtl/addr_decoder.v \
     $ROOT/rtl/rw_control.v $ROOT/rtl/io_regs.v $ROOT/rtl/regfile.v $ROOT/rtl/alu.v \
     $ROOT/rtl/imm_gen.v $ROOT/rtl/control_unit.v $ROOT/rtl/cpu_core.v \
     $ROOT/rtl/perf_counters.v $ROOT/rtl/harvard_top.v $ROOT/rtl/unified_mem.v \
     $ROOT/rtl/vonneumann_top.v"

# ---- unit test: address decoder + read/write control
iverilog -g2012 -I "$ROOT/rtl" -o "$OUT/tb_decoder.vvp" \
    "$ROOT/tb/tb_addr_decoder.v" "$ROOT/rtl/addr_decoder.v" "$ROOT/rtl/rw_control.v"
vvp -n "$OUT/tb_decoder.vvp" | tee "$OUT/tb_decoder.log" | grep -E "PASS|FAIL"

: > "$OUT/perf.log"
for src in "$ROOT"/sw/programs/*.s; do
    name=$(basename "$src" .s)
    python3 "$ROOT/sw/rv32_asm.py" "$src" "$BUILD" > /dev/null
    for arch in HARVARD VONNEUMANN; do
        tag=$(echo $arch | tr 'A-Z' 'a-z')
        iverilog -g2012 -D$arch -I "$ROOT/rtl" -o "$OUT/${name}_${tag}.vvp" \
            -Ptb_top.PROG="\"$BUILD/$name.hex\"" \
            -Ptb_top.DATA="\"$BUILD/${name}_data.hex\"" \
            -Ptb_top.EXPECT="\"$BUILD/${name}_expect.hex\"" \
            -Ptb_top.NAME="\"$name\"" \
            -Ptb_top.VCD="\"$OUT/${name}_${tag}.vcd\"" \
            "$ROOT/tb/tb_top.v" $RTL
        vvp -n "$OUT/${name}_${tag}.vvp" > "$OUT/${name}_${tag}.log"
        grep -E "^(PASS|FAIL|PERF|  mismatch)" "$OUT/${name}_${tag}.log" | tee -a "$OUT/perf.log"
    done
done

python3 "$ROOT/sim/summarize.py" "$OUT/perf.log" "$BUILD" "$ROOT/docs/results.csv"
