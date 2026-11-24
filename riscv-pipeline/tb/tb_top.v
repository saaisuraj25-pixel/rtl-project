// Testbench for the pipelined processor.
//
// The same program is run on two models:
//   1. a simple single-cycle reference CPU written below (task run_reference)
//   2. the pipelined processor (DUT)
// At the end all 32 registers and the whole data memory are compared.
//
// Usage (plusargs):
//   +prog=file.hex     program to run (required)
//   +data=file.hex     initial data memory (optional)
//   +vcd               dump waveform to wave.vcd
`timescale 1ns/1ps

module tb_top;
    reg clk = 0;
    reg reset = 1;
    wire halted;

    top dut (.clk(clk), .reset(reset), .halted(halted));

    always #5 clk = ~clk;

    // ---------------- reference model state ----------------
    reg [31:0] ref_reg [0:31];
    reg [31:0] ref_mem [0:1023];
    reg [31:0] prog    [0:1023];

    reg [1023:0] progfile, datafile;
    integer i, errors, cycles, stalls, flushes, ref_count;

    // ---------------- single-cycle reference CPU ----------------
    task run_reference;
        reg [31:0] pc, instr, a, b, imm_i, imm_s, imm_b, imm_u, imm_j, addr, word, val;
        reg [6:0]  op;
        reg [2:0]  f3;
        reg [4:0]  rd, rs1, rs2;
        reg        done;
        integer    n;
        begin
            for (n = 0; n < 32; n = n + 1) ref_reg[n] = 0;
            pc = 0; done = 0; n = 0;
            while (!done && n < 100000) begin
                instr = prog[pc[11:2]];
                op  = instr[6:0];  f3 = instr[14:12];
                rd  = instr[11:7]; rs1 = instr[19:15]; rs2 = instr[24:20];
                a = ref_reg[rs1];  b = ref_reg[rs2];
                imm_i = {{20{instr[31]}}, instr[31:20]};
                imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
                imm_u = {instr[31:12], 12'b0};
                imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
                val = 0;
                n = n + 1;

                case (op)
                    7'b0110111: begin val = imm_u;      pc = pc + 4; end               // lui
                    7'b0010111: begin val = pc + imm_u; pc = pc + 4; end               // auipc
                    7'b1101111: begin val = pc + 4;     pc = pc + imm_j; end           // jal
                    7'b1100111: begin val = pc + 4;     pc = (a + imm_i) & ~32'd1; end // jalr
                    7'b1100011: begin                                                  // branches
                        case (f3)
                            3'b000: pc = (a == b) ? pc + imm_b : pc + 4;
                            3'b001: pc = (a != b) ? pc + imm_b : pc + 4;
                            3'b100: pc = ($signed(a) <  $signed(b)) ? pc + imm_b : pc + 4;
                            3'b101: pc = ($signed(a) >= $signed(b)) ? pc + imm_b : pc + 4;
                            3'b110: pc = (a <  b) ? pc + imm_b : pc + 4;
                            3'b111: pc = (a >= b) ? pc + imm_b : pc + 4;
                            default: pc = pc + 4;
                        endcase
                    end
                    7'b0000011: begin                                                  // loads
                        addr = a + imm_i;
                        word = ref_mem[addr[11:2]] >> (8 * addr[1:0]);
                        case (f3)
                            3'b000: val = {{24{word[7]}},  word[7:0]};
                            3'b001: val = {{16{word[15]}}, word[15:0]};
                            3'b100: val = {24'd0, word[7:0]};
                            3'b101: val = {16'd0, word[15:0]};
                            default: val = ref_mem[addr[11:2]];
                        endcase
                        pc = pc + 4;
                    end
                    7'b0100011: begin                                                  // stores
                        addr = a + imm_s;
                        word = ref_mem[addr[11:2]];
                        case (f3)
                            3'b000: case (addr[1:0])
                                        2'd0: word[7:0]   = b[7:0];
                                        2'd1: word[15:8]  = b[7:0];
                                        2'd2: word[23:16] = b[7:0];
                                        2'd3: word[31:24] = b[7:0];
                                    endcase
                            3'b001: if (addr[1]) word[31:16] = b[15:0];
                                    else         word[15:0]  = b[15:0];
                            default: word = b;
                        endcase
                        ref_mem[addr[11:2]] = word;
                        pc = pc + 4;
                    end
                    7'b0010011, 7'b0110011: begin                                      // ALU
                        if (op == 7'b0010011) b = imm_i;
                        case (f3)
                            3'b000: val = (op == 7'b0110011 && instr[30]) ? a - b : a + b;
                            3'b001: val = a << b[4:0];
                            3'b010: val = ($signed(a) < $signed(b)) ? 1 : 0;
                            3'b011: val = (a < b) ? 1 : 0;
                            3'b100: val = a ^ b;
                            3'b101: begin
                                // careful: inside ?: the result would become unsigned
                                // and >>> would not sign extend, so use if/else
                                if (instr[30]) val = $signed(a) >>> b[4:0];
                                else           val = a >> b[4:0];
                            end
                            3'b110: val = a | b;
                            3'b111: val = a & b;
                        endcase
                        pc = pc + 4;
                    end
                    7'b1110011: begin                                                  // ecall / ebreak
                        if (f3 == 0 && instr[31:21] == 0) done = 1;
                        pc = pc + 4;
                    end
                    default: pc = pc + 4;                                              // fence -> nop
                endcase

                // only these write rd
                if (rd != 0 && (op == 7'b0110111 || op == 7'b0010111 || op == 7'b1101111 ||
                                op == 7'b1100111 || op == 7'b0000011 || op == 7'b0010011 ||
                                op == 7'b0110011))
                    ref_reg[rd] = val;
            end
            ref_count = n;
            if (!done) $display("WARNING: reference model did not reach ebreak");
        end
    endtask

    // ---------------- counters ----------------
    always @(posedge clk) begin
        if (!reset && !halted) begin
            cycles = cycles + 1;
            if (dut.cpu.StallF) stalls  = stalls + 1;
            if (dut.cpu.PCSrcE) flushes = flushes + 1;
        end
    end

    // ---------------- main ----------------
    initial begin
        errors = 0; cycles = 0; stalls = 0; flushes = 0;

        if ($test$plusargs("vcd")) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_top);
        end

        if (!$value$plusargs("prog=%s", progfile)) begin
            $display("ERROR: give a program with +prog=file.hex");
            $finish;
        end

        for (i = 0; i < 1024; i = i + 1) begin
            prog[i] = 32'h00000013;
            ref_mem[i] = 0;
        end
        $readmemh(progfile, prog);
        $readmemh(progfile, dut.imem0.RAM);
        if ($value$plusargs("data=%s", datafile)) begin
            $readmemh(datafile, ref_mem);
            $readmemh(datafile, dut.dmem0.RAM);
        end

        run_reference;

        // run the pipeline
        repeat (3) @(posedge clk);
        #1 reset = 0;
        while (!halted && cycles < 200000) @(posedge clk);
        repeat (2) @(posedge clk);

        if (!halted) begin
            $display("ERROR: timeout, ebreak never reached");
            errors = errors + 1;
        end

        // compare registers
        for (i = 0; i < 32; i = i + 1) begin
            if (dut.cpu.rf0.rf[i] !== ref_reg[i]) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("MISMATCH x%0d: pipeline=%h reference=%h", i, dut.cpu.rf0.rf[i], ref_reg[i]);
            end
        end
        // compare data memory
        for (i = 0; i < 1024; i = i + 1) begin
            if (dut.dmem0.RAM[i] !== ref_mem[i]) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("MISMATCH mem[0x%h]: pipeline=%h reference=%h", i * 4, dut.dmem0.RAM[i], ref_mem[i]);
            end
        end

        if (errors == 0)
            $display("PASS  instructions=%0d cycles=%0d stalls=%0d branches_taken=%0d", ref_count, cycles, stalls, flushes);
        else
            $display("FAIL  errors=%0d", errors);
        $finish;
    end
endmodule
