#!/usr/bin/env bash
# ============================================================================
# run_synth.sh - synthesise every top level with Yosys (generic Xilinx 7-series
#                flow: synth_xilinx) and collect resource + logic-depth numbers.
#
#   ./synth/run_synth.sh            -> synth/logs/*.log, docs/synth.csv
#
# Notes
#  * Memories are initialised from sw/build/vector_add*.hex (contents do not
#    change resource counts).
#  * The performance counters drive no output pins, so synthesis removes them;
#    the numbers are for the memory organisation + core only.
#  * No place-and-route: 'depth' is the longest register-to-register
#    combinational path counted in mapped cells (LUT/MUXF/CARRY4, Yosys
#    'ltp' with flip-flops and distributed-RAM cells cut out). It is a
#    relative timing indicator between the designs, not an Fmax.
# ============================================================================
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGS="$ROOT/synth/logs"
mkdir -p "$LOGS"
B="$ROOT/sw/build"
CORE="pc addr_decoder rw_control io_regs regfile alu imm_gen control_unit cpu_core"

synth() {   # name top "files" "chparam args"
    local name=$1 top=$2 files=$3 params=$4 src=""
    for f in $CORE $files; do src="$src \"$ROOT/rtl/$f.v\""; done
    yosys -q -l "$LOGS/$name.log" -p "
        read_verilog -defer -I \"$ROOT/rtl\" $src
        chparam $params $top
        synth_xilinx -top $top -flatten
        tee -o \"$LOGS/$name.stat\" stat
        tee -o \"$LOGS/$name.ltp\" ltp -noff t:* t:FD* %d t:RAM* %d w:* %u
    " > /dev/null
    echo "synthesised $name"
}

synth harvard      harvard_top    "imem dmem perf_counters harvard_top" \
      "-set IMEM_INIT \"$B/vector_add.hex\" -set DMEM_INIT \"$B/vector_add_data.hex\""
synth vonneumann   vonneumann_top "unified_mem perf_counters vonneumann_top" \
      "-set CODE_INIT \"$B/vector_add.hex\" -set DATA_INIT \"$B/vector_add_data.hex\""
H="main_mem mem_arbiter l1_cache hier_perf"
synth split        modharvard_top "$H modharvard_top" \
      "-set CODE_INIT \"$B/vector_add.hex\" -set DATA_INIT \"$B/vector_add_data.hex\""
synth unified      unicache_top   "$H unicache_top" \
      "-set CODE_INIT \"$B/vector_add.hex\" -set DATA_INIT \"$B/vector_add_data.hex\""
synth l1_cache_256B l1_cache      "l1_cache" "-set SETS 16 -set LINE_WORDS 4"

python3 "$ROOT/synth/parse_synth.py" "$LOGS" "$ROOT/docs/synth.csv"
