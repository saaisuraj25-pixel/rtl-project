// 2 flip-flop synchronizer
// Used to move the Gray code pointers into the other clock domain.
module sync_2ff #(parameter WIDTH = 5) (
    input                  clk,
    input                  rst_n,
    input      [WIDTH-1:0] d,
    output reg [WIDTH-1:0] q
);
    reg [WIDTH-1:0] q1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q1 <= 0;
            q  <= 0;
        end else begin
            q1 <= d;
            q  <= q1;
        end
    end
endmodule
