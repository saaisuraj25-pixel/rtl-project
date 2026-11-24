// Data memory, 1024 words (4 KB), byte enables for sb / sh.
// Only address bits [11:2] are used, misaligned accesses are not supported.
module dmem (
    input         clk,
    input         we,
    input  [3:0]  be,
    input  [31:0] a,
    input  [31:0] wd,
    output [31:0] rd
);
    reg [31:0] RAM [0:1023];
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            RAM[i] = 32'd0;
    end

    assign rd = RAM[a[11:2]];

    always @(posedge clk) begin
        if (we) begin
            if (be[0]) RAM[a[11:2]][7:0]   <= wd[7:0];
            if (be[1]) RAM[a[11:2]][15:8]  <= wd[15:8];
            if (be[2]) RAM[a[11:2]][23:16] <= wd[23:16];
            if (be[3]) RAM[a[11:2]][31:24] <= wd[31:24];
        end
    end
endmodule
