// Hazard unit
//
// Forwarding (to the ALU inputs in Execute):
//   10 -> forward ALUResultM (instruction in Memory stage)
//   01 -> forward ResultW    (instruction in Writeback stage)
//   Memory stage has priority because it is the newer value.
//
// Load-use stall: if the instruction in Execute is a load and the instruction
// in Decode needs its result, stall Fetch and Decode for one cycle and put a
// bubble in Execute.
//
// Control hazard: branches and jumps are resolved in Execute. If the PC is
// changed (PCSrcE), the two instructions fetched after it are flushed.
module hazard_unit (
    input  [4:0] Rs1D, Rs2D,
    input  [4:0] Rs1E, Rs2E, RdE,
    input  [4:0] RdM, RdW,
    input        RegWriteM, RegWriteW,
    input        ResultSrcE0,      // 1 when the instruction in Execute is a load
    input        PCSrcE,
    output reg [1:0] ForwardAE, ForwardBE,
    output       StallF, StallD,
    output       FlushD, FlushE
);
    wire lwStall;

    always @(*) begin
        if (RegWriteM && RdM != 5'd0 && RdM == Rs1E)
            ForwardAE = 2'b10;
        else if (RegWriteW && RdW != 5'd0 && RdW == Rs1E)
            ForwardAE = 2'b01;
        else
            ForwardAE = 2'b00;

        if (RegWriteM && RdM != 5'd0 && RdM == Rs2E)
            ForwardBE = 2'b10;
        else if (RegWriteW && RdW != 5'd0 && RdW == Rs2E)
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
    end

    assign lwStall = ResultSrcE0 && RdE != 5'd0 && (RdE == Rs1D || RdE == Rs2D);

    assign StallF = lwStall;
    assign StallD = lwStall;
    assign FlushD = PCSrcE;
    assign FlushE = lwStall | PCSrcE;
endmodule
