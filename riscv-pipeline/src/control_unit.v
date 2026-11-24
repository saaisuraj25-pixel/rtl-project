// Control unit (decoder) for RV32I
//
// ResultSrc : 00 ALU result, 01 data memory, 10 PC+4 (jal/jalr)
// ALUSrcA   : 00 rs1, 01 PC (auipc), 10 zero (lui)
// ALUSrcB   : 0 rs2, 1 immediate
// fence and CSR instructions are treated as nop.
// ecall / ebreak set Halt (used by the testbench to stop the simulation).
module control_unit (
    input  [6:0] op,
    input  [2:0] funct3,
    input        funct7b5,     // instr[30]
    input        isEnv,        // instr[31:20] is 0 or 1 (ecall / ebreak)
    output reg       RegWrite,
    output reg [1:0] ResultSrc,
    output reg       MemWrite,
    output reg       Branch,
    output reg       Jump,
    output reg       Jalr,
    output reg [1:0] ALUSrcA,
    output reg       ALUSrcB,
    output reg [2:0] ImmSrc,
    output reg [3:0] ALUControl,
    output reg       Halt
);
    // ALU operation from funct3 (used by R-type and I-type ALU instructions)
    reg [3:0] aluFromFunct3;
    always @(*) begin
        case (funct3)
            3'b000: aluFromFunct3 = 4'b0000;                       // add
            3'b001: aluFromFunct3 = 4'b0111;                       // sll
            3'b010: aluFromFunct3 = 4'b0101;                       // slt
            3'b011: aluFromFunct3 = 4'b0110;                       // sltu
            3'b100: aluFromFunct3 = 4'b0100;                       // xor
            3'b101: aluFromFunct3 = funct7b5 ? 4'b1001 : 4'b1000;  // sra / srl
            3'b110: aluFromFunct3 = 4'b0011;                       // or
            default: aluFromFunct3 = 4'b0010;                      // and
        endcase
    end

    always @(*) begin
        // default: nop
        RegWrite   = 1'b0;
        ResultSrc  = 2'b00;
        MemWrite   = 1'b0;
        Branch     = 1'b0;
        Jump       = 1'b0;
        Jalr       = 1'b0;
        ALUSrcA    = 2'b00;
        ALUSrcB    = 1'b0;
        ImmSrc     = 3'b000;
        ALUControl = 4'b0000;
        Halt       = 1'b0;

        case (op)
            7'b0110011: begin // R-type
                RegWrite = 1'b1;
                if (funct3 == 3'b000)
                    ALUControl = funct7b5 ? 4'b0001 : 4'b0000;  // sub / add
                else
                    ALUControl = aluFromFunct3;
            end
            7'b0010011: begin // I-type ALU
                RegWrite   = 1'b1;
                ALUSrcB    = 1'b1;
                ALUControl = aluFromFunct3;   // addi never subtracts (bit 30 is part of imm)
            end
            7'b0000011: begin // loads
                RegWrite  = 1'b1;
                ResultSrc = 2'b01;
                ALUSrcB   = 1'b1;
            end
            7'b0100011: begin // stores
                MemWrite = 1'b1;
                ALUSrcB  = 1'b1;
                ImmSrc   = 3'b001;
            end
            7'b1100011: begin // branches
                Branch = 1'b1;
                ImmSrc = 3'b010;
            end
            7'b0110111: begin // lui
                RegWrite = 1'b1;
                ALUSrcA  = 2'b10;
                ALUSrcB  = 1'b1;
                ImmSrc   = 3'b011;
            end
            7'b0010111: begin // auipc
                RegWrite = 1'b1;
                ALUSrcA  = 2'b01;
                ALUSrcB  = 1'b1;
                ImmSrc   = 3'b011;
            end
            7'b1101111: begin // jal
                RegWrite  = 1'b1;
                ResultSrc = 2'b10;
                Jump      = 1'b1;
                ImmSrc    = 3'b100;
            end
            7'b1100111: begin // jalr  (target = rs1 + imm, done in the ALU)
                RegWrite  = 1'b1;
                ResultSrc = 2'b10;
                Jalr      = 1'b1;
                ALUSrcB   = 1'b1;
            end
            7'b1110011: begin // ecall / ebreak
                if (funct3 == 3'b000 && isEnv)
                    Halt = 1'b1;
            end
            default: ;        // fence etc. -> nop
        endcase
    end
endmodule
