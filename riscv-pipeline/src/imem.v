// Instruction memory, 1024 words (4 KB), loaded by the testbench
module imem (
    input  [31:0] a,
    output [31:0] rd
);
    reg [31:0] RAM [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            RAM[i] = 32'h00000013;   // nop
    end
    assign rd = RAM[a[11:2]];
endmodule
