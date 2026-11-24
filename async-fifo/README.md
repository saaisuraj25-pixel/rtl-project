# Asynchronous FIFO

A FIFO where the write side and the read side run on different, unrelated
clocks. Used for clock domain crossing (CDC). Written in Verilog, based on
Clifford Cummings' SNUG 2002 paper.

## How it works
- **Memory**: written with `wclk`, read with `raddr` (no clock).
- **Pointers**: the read and write pointers have one extra bit. When the write
  pointer wraps around one more time than the read pointer, the extra (MSB)
  bits are different. So:
  - **empty** = both pointers equal
  - **full** = pointers equal except the MSB
- **Gray code**: the pointers are sent to the other clock domain in Gray code.
  Only one bit changes per increment, so even if the other clock samples it
  during a change, it gets either the old or the new value, never a wrong
  value in between.
- **2 flip-flop synchronizers** move each pointer into the other clock domain
  to reduce the chance of metastability.
- In Gray code, "equal except the MSB" means the **top two bits are inverted**
  and the rest are equal. That is what the full check in `wptr_full.v` does.
- `wfull` and `rempty` are registers and are calculated from the next pointer
  value. Because of the synchronizer delay they can stay set a little longer
  than needed, but never too short, so the FIFO cannot overflow or underflow.

## Files
```
src/async_fifo.v      top level
src/wptr_full.v       write pointer + full flag
src/rptr_empty.v      read pointer + empty flag
src/sync_2ff.v        2 flip-flop synchronizer
src/fifo_mem.v        memory
tb/tb_async_fifo.v    testbench
scripts/run_tests.sh  runs depth 4, 16 and 64 with seeds 1-3
```

## Testing
The testbench keeps its own model of the FIFO (an array with head/tail
counters). Every accepted write goes into the model and every accepted read
must return the oldest value in the model. It also checks:
- no write is accepted when the FIFO is full (overflow)
- no read is accepted when the FIFO is empty (underflow)
- `wfull` is 1 whenever the FIFO really has DEPTH words
- `rempty` is 1 whenever the FIFO really is empty

Tests:
1. **Fill and drain** - keep writing until full (exactly DEPTH words must go in),
   then keep reading until empty (exactly DEPTH words must come out)
2. **Fixed clock ratios** - same clock, write 3.7x faster, read 3.7x faster,
   write ~16x faster, read ~16x faster, 7 ns vs 13 ns
3. **Random clock ratios** - 10 runs with random write and read clock periods
   between 2 ns and 60 ns and random write/read rates

Result (depth 4, 16 and 64, seeds 1, 2, 3): all 9 runs pass, about 10,000 words
checked per run. Example output (depth 16):
```
fill_and_drain   writes=16 reads=16 write_blocked=31 read_blocked=5 errors=0
    write_faster wclk= 10.00ns rclk= 37.00ns  writes=1000 reads=1000 write_blocked=2662 read_blocked=9 errors=0
     read_faster wclk= 37.00ns rclk= 10.00ns  writes=1001 reads=1001 write_blocked=0 read_blocked=2707 errors=0
   random_clocks wclk= 32.23ns rclk= 17.83ns  writes=501 reads=501 write_blocked=217 read_blocked=6 errors=0
PASS  total words checked = 10025
```

I also checked that the testbench catches bugs by breaking the design on purpose
(full flag comparing only the MSB, writing when full, rempty reset to 0, read
pointer moving when empty). All of them made the test fail.

Note: simulation cannot show metastability, so it cannot prove the
synchronizers are needed. That needs real hardware or CDC tools.

## How to run
```
./scripts/run_tests.sh
```
Waveform (Icarus Verilog):
```
iverilog -g2005 -o sim src/*.v tb/tb_async_fifo.v
vvp sim +seed=1 +vcd
gtkwave wave.vcd
```

## Possible improvements
- reset synchronizers
- almost full / almost empty flags
- formal check of no overflow / underflow
