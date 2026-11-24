// Asynchronous FIFO (write and read use different clocks)
// Based on Clifford Cummings, "Simulation and Synthesis Techniques for
// Asynchronous FIFO Design", SNUG 2002.
//
// Depth = 2^ASIZE. rdata shows the oldest word whenever rempty = 0.
// Writing when full or reading when empty is ignored.
module async_fifo #(parameter DSIZE = 8, parameter ASIZE = 4) (
    input              wclk, wrst_n, winc,
    input  [DSIZE-1:0] wdata,
    output             wfull,
    input              rclk, rrst_n, rinc,
    output [DSIZE-1:0] rdata,
    output             rempty
);
    wire [ASIZE-1:0] waddr, raddr;
    wire [ASIZE:0]   wptr, rptr, wq2_rptr, rq2_wptr;

    fifo_mem #(DSIZE, ASIZE) mem (
        .wclk(wclk), .wen(winc & ~wfull), .waddr(waddr), .wdata(wdata),
        .raddr(raddr), .rdata(rdata)
    );

    // read pointer -> write clock domain
    sync_2ff #(ASIZE+1) sync_r2w (.clk(wclk), .rst_n(wrst_n), .d(rptr), .q(wq2_rptr));
    // write pointer -> read clock domain
    sync_2ff #(ASIZE+1) sync_w2r (.clk(rclk), .rst_n(rrst_n), .d(wptr), .q(rq2_wptr));

    wptr_full #(ASIZE) wfull_logic (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wq2_rptr(wq2_rptr),
        .waddr(waddr), .wptr(wptr), .wfull(wfull)
    );

    rptr_empty #(ASIZE) rempty_logic (
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rq2_wptr(rq2_wptr),
        .raddr(raddr), .rptr(rptr), .rempty(rempty)
    );
endmodule
