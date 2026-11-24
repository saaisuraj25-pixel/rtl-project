// Register file: 32 x 32 bit, 2 read ports, 1 write port.
// Written on the falling edge so an instruction in Decode can read a value
// written by Writeback in the same cycle (same trick as Harris & Harris).
module regfile (
    input         clk,
    input         we3,
    input  [4:0]  a1, a2, a3,
    input  [31:0] wd3,
    output [31:0] rd1, rd2
);
    reg [31:0] rf [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            rf[i] = 32'd0;
    end

    always @(negedge clk) begin
        if (we3 && a3 != 5'd0)
            rf[a3] <= wd3;
    end

    assign rd1 = (a1 == 5'd0) ? 32'd0 : rf[a1];
    assign rd2 = (a2 == 5'd0) ? 32'd0 : rf[a2];
endmodule
