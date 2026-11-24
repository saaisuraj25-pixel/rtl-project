// Write pointer and full flag (write clock domain)
//
// The pointers have one extra bit (ASIZE+1 bits). If the write pointer has
// wrapped one more time than the read pointer, the MSBs are different.
// Full  = pointers equal except the MSB.
// In Gray code this means the top 2 bits are inverted and the rest are equal.
module wptr_full #(parameter ASIZE = 4) (
    input                  wclk,
    input                  wrst_n,
    input                  winc,
    input      [ASIZE:0]   wq2_rptr,    // read pointer synchronized to wclk
    output     [ASIZE-1:0] waddr,
    output reg [ASIZE:0]   wptr,        // Gray code write pointer
    output reg             wfull
);
    reg  [ASIZE:0] wbin;
    wire [ASIZE:0] wbin_next, wgray_next;
    wire           wfull_next;

    assign wbin_next  = wbin + (winc & ~wfull);
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;      // binary to Gray
    assign wfull_next = (wgray_next == {~wq2_rptr[ASIZE:ASIZE-1], wq2_rptr[ASIZE-2:0]});

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= 0;
            wptr  <= 0;
            wfull <= 1'b0;
        end else begin
            wbin  <= wbin_next;
            wptr  <= wgray_next;
            wfull <= wfull_next;
        end
    end

    assign waddr = wbin[ASIZE-1:0];
endmodule
