// 5-stage pipelined RV32I processor
// Fetch -> Decode -> Execute -> Memory -> Writeback
// Signal names end with the stage they belong to (F, D, E, M, W),
// same naming as Harris & Harris "Digital Design and Computer Architecture: RISC-V Edition".
module riscv_pipeline (
    input         clk,
    input         reset,          // active high, synchronous

    // instruction memory
    output [31:0] PCF,
    input  [31:0] InstrF,

    // data memory
    output [31:0] DataAdrM,
    output [31:0] WriteDataM,
    output [3:0]  ByteEnM,
    output        MemWriteM,
    input  [31:0] ReadDataM,

    output reg    halted          // goes high when ebreak/ecall reaches Writeback
);
    // ---------------- hazard signals ----------------
    wire       StallF, StallD, FlushD, FlushE;
    wire [1:0] ForwardAE, ForwardBE;
    wire       PCSrcE;
    wire [31:0] PCTargetE;

    // =================== FETCH ===================
    reg  [31:0] PCF_r;
    wire [31:0] PCPlus4F;

    assign PCF      = PCF_r;
    assign PCPlus4F = PCF_r + 32'd4;

    always @(posedge clk) begin
        if (reset)
            PCF_r <= 32'd0;
        else if (PCSrcE)
            PCF_r <= PCTargetE;
        else if (!StallF)
            PCF_r <= PCPlus4F;
    end

    // IF/ID register
    reg [31:0] InstrD, PCD, PCPlus4D;
    always @(posedge clk) begin
        if (reset || FlushD) begin
            InstrD   <= 32'h00000013;    // nop
            PCD      <= 32'd0;
            PCPlus4D <= 32'd0;
        end else if (!StallD) begin
            InstrD   <= InstrF;
            PCD      <= PCF_r;
            PCPlus4D <= PCPlus4F;
        end
    end

    // =================== DECODE ===================
    wire [4:0] Rs1D = InstrD[19:15];
    wire [4:0] Rs2D = InstrD[24:20];
    wire [4:0] RdD  = InstrD[11:7];

    wire       RegWriteD, MemWriteD, BranchD, JumpD, JalrD, ALUSrcBD, HaltD;
    wire [1:0] ResultSrcD, ALUSrcAD;
    wire [2:0] ImmSrcD;
    wire [3:0] ALUControlD;
    wire [31:0] RD1D, RD2D, ImmExtD;

    // writeback signals (declared here because the register file uses them)
    reg        RegWriteW;
    reg  [4:0] RdW;
    wire [31:0] ResultW;

    control_unit cu (
        .op(InstrD[6:0]), .funct3(InstrD[14:12]), .funct7b5(InstrD[30]),
        .isEnv(InstrD[31:21] == 11'd0),
        .RegWrite(RegWriteD), .ResultSrc(ResultSrcD), .MemWrite(MemWriteD),
        .Branch(BranchD), .Jump(JumpD), .Jalr(JalrD),
        .ALUSrcA(ALUSrcAD), .ALUSrcB(ALUSrcBD), .ImmSrc(ImmSrcD),
        .ALUControl(ALUControlD), .Halt(HaltD)
    );

    regfile rf0 (
        .clk(clk), .we3(RegWriteW), .a1(Rs1D), .a2(Rs2D), .a3(RdW),
        .wd3(ResultW), .rd1(RD1D), .rd2(RD2D)
    );

    imm_gen ig (.instr(InstrD[31:7]), .ImmSrc(ImmSrcD), .ImmExt(ImmExtD));

    // ID/EX register
    reg        RegWriteE, MemWriteE, BranchE, JumpE, JalrE, ALUSrcBE, HaltE;
    reg [1:0]  ResultSrcE, ALUSrcAE;
    reg [3:0]  ALUControlE;
    reg [2:0]  funct3E;
    reg [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E;
    reg [4:0]  Rs1E, Rs2E, RdE;

    always @(posedge clk) begin
        if (reset || FlushE) begin
            RegWriteE <= 0; MemWriteE <= 0; BranchE <= 0; JumpE <= 0; JalrE <= 0;
            ALUSrcBE <= 0; HaltE <= 0; ResultSrcE <= 0; ALUSrcAE <= 0; ALUControlE <= 0;
            funct3E <= 0; RD1E <= 0; RD2E <= 0; ImmExtE <= 0; PCE <= 0; PCPlus4E <= 0;
            Rs1E <= 0; Rs2E <= 0; RdE <= 0;
        end else begin
            RegWriteE <= RegWriteD; MemWriteE <= MemWriteD; BranchE <= BranchD;
            JumpE <= JumpD; JalrE <= JalrD; ALUSrcBE <= ALUSrcBD; HaltE <= HaltD;
            ResultSrcE <= ResultSrcD; ALUSrcAE <= ALUSrcAD; ALUControlE <= ALUControlD;
            funct3E <= InstrD[14:12];
            RD1E <= RD1D; RD2E <= RD2D; ImmExtE <= ImmExtD; PCE <= PCD; PCPlus4E <= PCPlus4D;
            Rs1E <= Rs1D; Rs2E <= Rs2D; RdE <= RdD;
        end
    end

    // =================== EXECUTE ===================
    reg  [31:0] ALUResultM;           // from EX/MEM register (used for forwarding)
    reg  [31:0] fwdA, fwdB, SrcAE;
    wire [31:0] SrcBE, ALUResultE;
    reg         takeBranch;

    // forwarding muxes
    always @(*) begin
        case (ForwardAE)
            2'b10:   fwdA = ALUResultM;
            2'b01:   fwdA = ResultW;
            default: fwdA = RD1E;
        endcase
        case (ForwardBE)
            2'b10:   fwdB = ALUResultM;
            2'b01:   fwdB = ResultW;
            default: fwdB = RD2E;
        endcase
    end

    always @(*) begin
        case (ALUSrcAE)
            2'b01:   SrcAE = PCE;      // auipc
            2'b10:   SrcAE = 32'd0;    // lui
            default: SrcAE = fwdA;
        endcase
    end
    assign SrcBE = ALUSrcBE ? ImmExtE : fwdB;

    alu alu_e (.a(SrcAE), .b(SrcBE), .ALUControl(ALUControlE), .result(ALUResultE));

    // branch compare
    always @(*) begin
        case (funct3E)
            3'b000:  takeBranch = (fwdA == fwdB);                    // beq
            3'b001:  takeBranch = (fwdA != fwdB);                    // bne
            3'b100:  takeBranch = ($signed(fwdA) <  $signed(fwdB));  // blt
            3'b101:  takeBranch = ($signed(fwdA) >= $signed(fwdB));  // bge
            3'b110:  takeBranch = (fwdA <  fwdB);                    // bltu
            3'b111:  takeBranch = (fwdA >= fwdB);                    // bgeu
            default: takeBranch = 1'b0;
        endcase
    end

    assign PCSrcE    = (BranchE & takeBranch) | JumpE | JalrE;
    assign PCTargetE = JalrE ? {ALUResultE[31:1], 1'b0} : (PCE + ImmExtE);

    // EX/MEM register
    reg        RegWriteM, MemWriteM_r, HaltM;
    reg [1:0]  ResultSrcM;
    reg [2:0]  funct3M;
    reg [31:0] StoreDataM, PCPlus4M;
    reg [4:0]  RdM;

    always @(posedge clk) begin
        if (reset) begin
            RegWriteM <= 0; MemWriteM_r <= 0; HaltM <= 0; ResultSrcM <= 0; funct3M <= 0;
            ALUResultM <= 0; StoreDataM <= 0; PCPlus4M <= 0; RdM <= 0;
        end else begin
            RegWriteM <= RegWriteE; MemWriteM_r <= MemWriteE; HaltM <= HaltE;
            ResultSrcM <= ResultSrcE; funct3M <= funct3E;
            ALUResultM <= ALUResultE; StoreDataM <= fwdB; PCPlus4M <= PCPlus4E; RdM <= RdE;
        end
    end

    // =================== MEMORY ===================
    // stores: move the byte / halfword to the correct lane
    reg [31:0] WriteDataM_r;
    reg [3:0]  ByteEnM_r;
    always @(*) begin
        case (funct3M[1:0])
            2'b00: begin   // sb
                WriteDataM_r = {4{StoreDataM[7:0]}};
                ByteEnM_r    = 4'b0001 << ALUResultM[1:0];
            end
            2'b01: begin   // sh
                WriteDataM_r = {2{StoreDataM[15:0]}};
                ByteEnM_r    = ALUResultM[1] ? 4'b1100 : 4'b0011;
            end
            default: begin // sw
                WriteDataM_r = StoreDataM;
                ByteEnM_r    = 4'b1111;
            end
        endcase
    end

    assign DataAdrM   = ALUResultM;
    assign WriteDataM = WriteDataM_r;
    assign ByteEnM    = ByteEnM_r;
    assign MemWriteM  = MemWriteM_r;

    // loads: pick the byte / halfword and sign or zero extend
    wire [31:0] shifted = ReadDataM >> (8 * ALUResultM[1:0]);
    reg  [31:0] LoadDataM;
    always @(*) begin
        case (funct3M)
            3'b000:  LoadDataM = {{24{shifted[7]}},  shifted[7:0]};   // lb
            3'b001:  LoadDataM = {{16{shifted[15]}}, shifted[15:0]};  // lh
            3'b100:  LoadDataM = {24'd0, shifted[7:0]};               // lbu
            3'b101:  LoadDataM = {16'd0, shifted[15:0]};              // lhu
            default: LoadDataM = ReadDataM;                           // lw
        endcase
    end

    // MEM/WB register
    reg [1:0]  ResultSrcW;
    reg [31:0] ALUResultW, ReadDataW, PCPlus4W;
    reg        HaltW;

    always @(posedge clk) begin
        if (reset) begin
            RegWriteW <= 0; ResultSrcW <= 0; ALUResultW <= 0; ReadDataW <= 0;
            PCPlus4W <= 0; RdW <= 0; HaltW <= 0;
        end else begin
            RegWriteW <= RegWriteM; ResultSrcW <= ResultSrcM; ALUResultW <= ALUResultM;
            ReadDataW <= LoadDataM; PCPlus4W <= PCPlus4M; RdW <= RdM; HaltW <= HaltM;
        end
    end

    // =================== WRITEBACK ===================
    assign ResultW = (ResultSrcW == 2'b01) ? ReadDataW :
                     (ResultSrcW == 2'b10) ? PCPlus4W  : ALUResultW;

    always @(posedge clk) begin
        if (reset)
            halted <= 1'b0;
        else if (HaltW)
            halted <= 1'b1;
    end

    // =================== HAZARD UNIT ===================
    hazard_unit hu (
        .Rs1D(Rs1D), .Rs2D(Rs2D), .Rs1E(Rs1E), .Rs2E(Rs2E), .RdE(RdE),
        .RdM(RdM), .RdW(RdW), .RegWriteM(RegWriteM), .RegWriteW(RegWriteW),
        .ResultSrcE0(ResultSrcE[0]), .PCSrcE(PCSrcE),
        .ForwardAE(ForwardAE), .ForwardBE(ForwardBE),
        .StallF(StallF), .StallD(StallD), .FlushD(FlushD), .FlushE(FlushE)
    );
endmodule
