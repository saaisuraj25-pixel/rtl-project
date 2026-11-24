#!/bin/bash
# Runs all directed tests and N random tests.
#   ./scripts/run_tests.sh          (100 random tests)
#   ./scripts/run_tests.sh 500
# Uses Icarus Verilog if it is installed, otherwise Verilator.
cd "$(dirname "$0")/.."
N=${1:-100}
mkdir -p build
SRC="src/alu.v src/imm_gen.v src/regfile.v src/control_unit.v src/hazard_unit.v src/riscv_pipeline.v src/imem.v src/dmem.v src/top.v tb/tb_top.v"

if command -v iverilog > /dev/null; then
    iverilog -g2005 -o build/sim $SRC || exit 1
    SIM="vvp -n build/sim"
else
    VERILATOR=verilator
    if ! command -v verilator > /dev/null; then
        export VERILATOR_ROOT=$(python3 -c "import verilator, os; print(os.path.dirname(verilator.__file__))")
        VERILATOR=$VERILATOR_ROOT/bin/verilator
    fi
    $VERILATOR --binary --timing -Wno-fatal -Wno-lint -Wno-style -CFLAGS -fcoroutines \
        --top-module tb_top -Mdir build/obj -o sim $SRC > build/build.log 2>&1 || { cat build/build.log; exit 1; }
    SIM="build/obj/sim"
fi

pass=0; fail=0
for t in tests/*.hex; do
    out=$($SIM +prog=$t | grep -E "PASS|FAIL|MISMATCH|ERROR")
    echo "$(basename $t .hex): $out"
    if echo "$out" | grep -q "^PASS"; then pass=$((pass+1)); else fail=$((fail+1)); fi
done

for s in $(seq 1 $N); do
    python3 scripts/gen_random.py $s build/rand.hex build/rand_data.hex
    out=$($SIM +prog=build/rand.hex +data=build/rand_data.hex | grep -E "PASS|FAIL|MISMATCH|ERROR")
    if echo "$out" | grep -q "^PASS"; then pass=$((pass+1)); else fail=$((fail+1)); echo "random seed $s: $out"; fi
done
echo "random tests: $N"
echo "TOTAL passed=$pass failed=$fail"
[ $fail -eq 0 ]
