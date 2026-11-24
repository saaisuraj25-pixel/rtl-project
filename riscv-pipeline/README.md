# 5-Stage Pipelined RISC-V Processor

A 5-stage pipelined processor (Fetch, Decode, Execute, Memory, Writeback) for the
RV32I base instruction set, written in Verilog. The structure and signal names
follow the pipelined processor in Harris & Harris.

## Supported instructions
All 37 RV32I base instructions:
- R-type: `add sub and or xor sll srl sra slt sltu`
- I-type: `addi andi ori xori slti sltiu slli srli srai`
- Loads / stores: `lb lh lw lbu lhu sb sh sw`
- Branches: `beq bne blt bge bltu bgeu`
- Jumps / upper immediate: `jal jalr lui auipc`

`ebreak` / `ecall` stop the simulation. `fence` is treated as a nop.

## Hazard handling
**Forwarding** - if an instruction in Execute needs a register that an older
instruction (in Memory or Writeback) is about to write, the value is forwarded
to the ALU input instead of using the old value from the register file.
The Memory stage has priority because it holds the newer value.

**Load-use stall** - a load only has its data after the Memory stage, so the
next instruction cannot get it by forwarding. In that case Fetch and Decode are
stalled for one cycle and a bubble (nop) is put into Execute.

**Branches and jumps** - they are resolved in Execute. If the branch is taken
(or for `jal`/`jalr`), the two instructions already fetched after it are
flushed, so a taken branch costs 2 cycles.

**Register file** is written on the falling edge of the clock so that Decode can
read a value written by Writeback in the same cycle.

## Files
```
src/riscv_pipeline.v   the 5 stages and pipeline registers
src/control_unit.v     instruction decoder
src/hazard_unit.v      forwarding, stall and flush
src/alu.v              ALU
src/imm_gen.v          immediate generator
src/regfile.v          register file
src/imem.v, dmem.v     instruction and data memory (4 KB each)
src/top.v              processor + memories
tb/tb_top.v            testbench with a single-cycle reference model
tests/*.hex            directed test programs (assembly written as comments)
scripts/gen_random.py  random program generator
scripts/run_tests.sh   runs all tests
```

## Testing
The testbench contains a simple **single-cycle reference model** of RV32I
(task `run_reference`). Every program is run on both the reference model and
the pipeline, and at the end all 32 registers and the whole data memory are
compared. Any difference is printed and the test fails.

**Directed tests** (`tests/`):
| Test | What it checks |
|---|---|
| test1_alu | all R-type and I-type ALU instructions, signed/unsigned compare, shifts |
| test2_forwarding | chains of dependent instructions, forwarding from MEM and WB |
| test3_load_use | load followed by a use of the loaded register (stall) |
| test4_load_store | lb/lh/lw/lbu/lhu/sb/sh/sw, sign and zero extension |
| test5_branches | all 6 branches taken and not taken, wrong-path instructions flushed |
| test6_jumps | lui, auipc, jal, jalr (function call and return) |
| test7_loops | sum of 1..10, Fibonacci, array store and sum |

**Random tests** - `gen_random.py` makes random programs (about 200 instructions)
using all instruction types. Branches and jumps only go forward so the program
always ends. Most instructions use registers x1-x8 so there are a lot of
back-to-back dependencies, which tests forwarding and stalls.

Result:
```
7 directed tests + 500 random tests: 507 passed, 0 failed
```

To check that the testbench really catches bugs, I broke the design on purpose
(removed the stall, removed the flush, gave WB forwarding priority over MEM,
wrote the register file on the rising edge). Each of these made tests fail.

## How to run
```
./scripts/run_tests.sh          # directed tests + 100 random tests
./scripts/run_tests.sh 500      # 500 random tests
```
To see the waveform of one test (Icarus Verilog):
```
iverilog -g2005 -o sim src/*.v tb/tb_top.v
vvp sim +prog=tests/test3_load_use.hex +vcd
gtkwave wave.vcd
```

## Possible improvements
- branch prediction (now every taken branch costs 2 cycles)
- run the official riscv-tests / riscv-arch-test suite
- CSRs and exceptions
- synthesize for an FPGA
