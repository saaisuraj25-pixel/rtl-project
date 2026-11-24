#!/bin/bash
# Runs the FIFO testbench for depth 4, 16 and 64 with a few seeds.
# Uses Icarus Verilog if it is installed, otherwise Verilator.
cd "$(dirname "$0")/.."
mkdir -p build
SRC="src/sync_2ff.v src/fifo_mem.v src/wptr_full.v src/rptr_empty.v src/async_fifo.v tb/tb_async_fifo.v"
SEEDS=${SEEDS:-"1 2 3"}
fail=0

for asize in 2 4 6; do
    if command -v iverilog > /dev/null; then
        iverilog -g2005 -P tb_async_fifo.ASIZE=$asize -o build/sim_$asize $SRC || exit 1
        SIM="vvp -n build/sim_$asize"
    else
        VERILATOR=verilator
        if ! command -v verilator > /dev/null; then
            export VERILATOR_ROOT=$(python3 -c "import verilator, os; print(os.path.dirname(verilator.__file__))")
            VERILATOR=$VERILATOR_ROOT/bin/verilator
        fi
        $VERILATOR --binary --timing -Wno-fatal -Wno-lint -Wno-style -CFLAGS -fcoroutines \
            -GASIZE=$asize --top-module tb_async_fifo -Mdir build/obj_$asize -o sim $SRC \
            > build/build_$asize.log 2>&1 || { cat build/build_$asize.log; exit 1; }
        SIM="build/obj_$asize/sim"
    fi
    for s in $SEEDS; do
        $SIM +seed=$s > build/log_depth$((1<<asize))_seed$s.txt
        echo "depth $((1<<asize)) seed $s: $(grep -E "^(PASS|FAIL)" build/log_depth$((1<<asize))_seed$s.txt)"
        grep -q "^PASS" build/log_depth$((1<<asize))_seed$s.txt || fail=1
    done
done
exit $fail
