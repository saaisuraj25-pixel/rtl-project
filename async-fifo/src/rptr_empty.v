// Read pointer and empty flag (read clock domain)
// Empty = next read pointer equals the synchronized write pointer.
module rptr_empty #(parameter ASIZE = 4) (
    input                  rclk,
    input                  rrst_n,
    input                  rinc,
    input      [ASIZE:0]   rq2_wptr,    // write pointer synchronized to rclk
    output     [ASIZE-1:0] raddr,
    output reg [ASIZE:0]   rptr,        // Gray code read pointer
    output reg             rempty
);
    reg  [ASIZE:0] rbin;
    wire [ASIZE:0] rbin_next, rgray_next;

    assign rbin_next  = rbin + (rinc & ~rempty);
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= 0;
            rptr   <= 0;
            rempty <= 1'b1;
        end else begin
            rbin   <= rbin_next;
            rptr   <= rgray_next;
            rempty <= (rgray_next == rq2_wptr);
        end
    end

    assign raddr = rbin[ASIZE-1:0];
endmodule
