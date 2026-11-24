// ALU
// ALUControl codes:
// 0000 add   0001 sub   0010 and   0011 or    0100 xor
// 0101 slt   0110 sltu  0111 sll   1000 srl   1001 sra
module alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  ALUControl,
    output reg [31:0] result
);
    always @(*) begin
        case (ALUControl)
            4'b0000: result = a + b;
            4'b0001: result = a - b;
            4'b0010: result = a & b;
            4'b0011: result = a | b;
            4'b0100: result = a ^ b;
            4'b0101: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            4'b0110: result = (a < b) ? 32'd1 : 32'd0;
            4'b0111: result = a << b[4:0];
            4'b1000: result = a >> b[4:0];
            4'b1001: result = $signed(a) >>> b[4:0];
            default: result = 32'd0;
        endcase
    end
endmodule
