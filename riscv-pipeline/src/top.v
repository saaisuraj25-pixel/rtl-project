// Processor + instruction memory + data memory
module top (
    input  clk,
    input  reset,
    output halted
);
    wire [31:0] PCF, InstrF, DataAdrM, WriteDataM, ReadDataM;
    wire [3:0]  ByteEnM;
    wire        MemWriteM;

    riscv_pipeline cpu (
        .clk(clk), .reset(reset), .PCF(PCF), .InstrF(InstrF),
        .DataAdrM(DataAdrM), .WriteDataM(WriteDataM), .ByteEnM(ByteEnM),
        .MemWriteM(MemWriteM), .ReadDataM(ReadDataM), .halted(halted)
    );

    imem imem0 (.a(PCF), .rd(InstrF));
    dmem dmem0 (.clk(clk), .we(MemWriteM), .be(ByteEnM), .a(DataAdrM),
                .wd(WriteDataM), .rd(ReadDataM));
endmodule
