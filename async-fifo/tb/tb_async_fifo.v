// Testbench for async_fifo
//
// A model of the FIFO (array + count) is kept in the testbench.
// Every write that the FIFO accepts is added to the model, and every read
// must give the oldest value in the model.
//
// Tests:
//   1. fill the FIFO until full (and keep trying to write)
//   2. empty it until empty (and keep trying to read)
//   3. random traffic with fixed clock ratios (write faster, read faster, equal)
//   4. random traffic with random read/write clock periods
//
// +seed=N changes the random numbers, +vcd dumps a waveform.
`timescale 1ns/1ps

module tb_async_fifo;
    parameter DSIZE = 16;
    parameter ASIZE = 4;
    parameter DEPTH = 1 << ASIZE;

    reg              wclk = 0, rclk = 0;
    reg              wrst_n = 0, rrst_n = 0;
    reg              winc = 0, rinc = 0;
    reg  [DSIZE-1:0] wdata = 0;
    wire [DSIZE-1:0] rdata;
    wire             wfull, rempty;

    async_fifo #(DSIZE, ASIZE) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty)
    );

    // clock half periods can be changed during the test
    real whalf = 5.0, rhalf = 5.0;
    always #(whalf) wclk = ~wclk;
    always #(rhalf) rclk = ~rclk;

    // ---------------- model ----------------
    reg [DSIZE-1:0] model [0:65535];
    integer head, tail;           // read from head, write at tail
    integer errors, writes, reads, wblocked, rblocked, total_writes;
    integer wrate, rrate;         // chance (0-100) to try a write / read each cycle
    integer seed;

    // drive inputs on the falling edge
    always @(negedge wclk) begin
        winc  <= (($random(seed) & 32'h7fffffff) % 100) < wrate;
        wdata <= $random(seed);
    end
    always @(negedge rclk) begin
        rinc  <= (($random(seed) & 32'h7fffffff) % 100) < rrate;
    end

    // check on the rising edge
    always @(posedge wclk) begin
        if (wrst_n) begin
            if (tail - head == DEPTH && !wfull) begin
                errors = errors + 1;
                $display("ERROR at %0t: FIFO has %0d words but wfull = 0", $time, DEPTH);
            end
            if (winc) begin
                if (wfull) begin
                    wblocked = wblocked + 1;
                end else begin
                    if (tail - head >= DEPTH) begin
                        errors = errors + 1;
                        $display("ERROR at %0t: overflow (write accepted when full)", $time);
                    end
                    model[tail % 65536] = wdata;
                    tail = tail + 1;
                    writes = writes + 1;
                end
            end
        end
    end

    always @(posedge rclk) begin
        if (rrst_n) begin
            if (tail == head && !rempty) begin
                errors = errors + 1;
                $display("ERROR at %0t: FIFO is empty but rempty = 0", $time);
            end
            if (rinc) begin
                if (rempty) begin
                    rblocked = rblocked + 1;
                end else if (tail == head) begin
                    errors = errors + 1;
                    $display("ERROR at %0t: underflow (read accepted when empty)", $time);
                end else begin
                    if (rdata !== model[head % 65536]) begin
                        errors = errors + 1;
                        if (errors < 20)
                            $display("ERROR at %0t: read %h, expected %h", $time, rdata, model[head % 65536]);
                    end
                    head = head + 1;
                    reads = reads + 1;
                end
            end
        end
    end

    // ---------------- tasks ----------------
    task do_reset;
        begin
            wrate = 0; rrate = 0;
            wrst_n = 0; rrst_n = 0;
            #100;
            head = 0; tail = 0;
            writes = 0; reads = 0; wblocked = 0; rblocked = 0;
            @(negedge wclk) wrst_n = 1;
            @(negedge rclk) rrst_n = 1;
        end
    endtask

    // read until the FIFO and the model are both empty
    task drain;
        integer k;
        begin
            wrate = 0; rrate = 100;
            k = 0;
            while ((tail != head || !rempty) && k < 100000) begin
                @(posedge rclk);
                k = k + 1;
            end
            repeat (5) @(posedge rclk);   // extra reads while empty
            rrate = 0;
            if (tail != head) begin
                errors = errors + 1;
                $display("ERROR: could not read everything back");
            end
        end
    endtask

    // random traffic until n words are written, then read everything
    task run_traffic;
        input [8*16-1:0] name;
        input real wperiod, rperiod;
        input integer wr, rr, n;
        integer k;
        begin
            whalf = wperiod / 2.0; rhalf = rperiod / 2.0;
            do_reset;
            wrate = wr; rrate = rr;
            k = 0;
            while (writes < n && k < 1000000) begin
                @(posedge wclk);
                k = k + 1;
            end
            drain;
            if (writes != reads) begin
                errors = errors + 1;
                $display("ERROR: %0s wrote %0d but read %0d", name, writes, reads);
            end
            total_writes = total_writes + writes;
            $display("%-16s wclk=%6.2fns rclk=%6.2fns  writes=%0d reads=%0d write_blocked=%0d read_blocked=%0d errors=%0d",
                     name, wperiod, rperiod, writes, reads, wblocked, rblocked, errors);
        end
    endtask

    // ---------------- main ----------------
    integer t;
    real wp, rp;

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        if ($test$plusargs("vcd")) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_async_fifo);
        end
        errors = 0; total_writes = 0;
        $display("async FIFO test, depth = %0d, seed = %0d", DEPTH, seed);

        // test 1 + 2: fill until full, then drain until empty
        whalf = 5.0; rhalf = 6.5;
        do_reset;
        wrate = 100;
        repeat (3 * DEPTH) @(posedge wclk);
        wrate = 0;
        @(posedge wclk);
        if (writes != DEPTH || !wfull) begin
            errors = errors + 1;
            $display("ERROR: fill test wrote %0d words (expected %0d), wfull = %b", writes, DEPTH, wfull);
        end
        drain;
        if (reads != DEPTH || !rempty) begin
            errors = errors + 1;
            $display("ERROR: drain test read %0d words (expected %0d)", reads, DEPTH);
        end
        total_writes = total_writes + writes;
        $display("fill_and_drain   writes=%0d reads=%0d write_blocked=%0d read_blocked=%0d errors=%0d",
                 writes, reads, wblocked, rblocked, errors);

        // test 3: fixed clock ratios
        run_traffic("same_clock",   10.0, 10.0,  70,  70, 1000);
        run_traffic("write_faster", 10.0, 37.0,  90,  90, 1000);
        run_traffic("read_faster",  37.0, 10.0,  90,  90, 1000);
        run_traffic("write_16x",     3.0, 50.0, 100, 100,  500);
        run_traffic("read_16x",     50.0,  3.0, 100, 100,  500);
        run_traffic("full_speed",    7.0, 13.0, 100, 100, 1000);

        // test 4: random clock periods (2 ns to 60 ns) and random rates
        for (t = 0; t < 10; t = t + 1) begin
            wp = 2.0 + (($random(seed) & 32'h7fffffff) % 5800) / 100.0;
            rp = 2.0 + (($random(seed) & 32'h7fffffff) % 5800) / 100.0;
            run_traffic("random_clocks", wp, rp,
                        20 + ($random(seed) & 32'h7fffffff) % 81,
                        20 + ($random(seed) & 32'h7fffffff) % 81, 500);
        end

        if (errors == 0)
            $display("PASS  total words checked = %0d", total_writes);
        else
            $display("FAIL  errors = %0d", errors);
        $finish;
    end
endmodule
