// FIFO memory: written with wclk, read without a clock
module fifo_mem #(parameter DSIZE = 8, parameter ASIZE = 4) (
    input              wclk,
    input              wen,
    input  [ASIZE-1:0] waddr,
    input  [DSIZE-1:0] wdata,
    input  [ASIZE-1:0] raddr,
    output [DSIZE-1:0] rdata
);
    reg [DSIZE-1:0] mem [0:(1<<ASIZE)-1];

    always @(posedge wclk) begin
        if (wen)
            mem[waddr] <= wdata;
    end

    assign rdata = mem[raddr];
endmodule
