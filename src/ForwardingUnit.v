module ForwardingUnit (
    input  [4:0] idex_rs1,
    input  [4:0] idex_rs2,
    input  [4:0] exmem_rd,
    input  [4:0] memwb_rd,

    input  [6:0] exmem_op,
    input  [6:0] memwb_op,

    output reg [1:0] forwardA,
    output reg [1:0] forwardB
);

    localparam NO_FORWARD  = 2'b00;
    localparam FROM_MEM    = 2'b01;
    localparam FROM_WB_ALU = 2'b10;
    localparam FROM_WB_LD  = 2'b11;

    localparam LW    = 7'b000_0011;
    localparam ALUop = 7'b001_0011;

    initial begin
      forwardA = NO_FORWARD;
      forwardB = NO_FORWARD;
    end

    always @(*) begin
        forwardA = NO_FORWARD;
        forwardB = NO_FORWARD;

        // Lógica de Forwarding para o operando A (idex_rs1)
        if ((exmem_rd != 5'd0) && (exmem_rd == idex_rs1) && (exmem_op == ALUop)) begin
            // Prioridade 1: Encaminhamento do estágio EX/MEM
            forwardA = FROM_MEM;
        end else if ((memwb_rd != 5'd0) && (memwb_rd == idex_rs1)) begin
            // Prioridade 2: Encaminhamento do estágio MEM/WB
            if (memwb_op == ALUop) begin
                forwardA = FROM_WB_ALU;
            end else if (memwb_op == LW) begin
                forwardA = FROM_WB_LD;
            end
        end

        // Lógica de Forwarding para o operando B (idex_rs2)
        if ((exmem_rd != 5'd0) && (exmem_rd == idex_rs2) && (exmem_op == ALUop)) begin
            forwardB = FROM_MEM;
        end else if ((memwb_rd != 5'd0) && (memwb_rd == idex_rs2)) begin
            if (memwb_op == ALUop) begin
                forwardB = FROM_WB_ALU;
            end else if (memwb_op == LW) begin
                forwardB = FROM_WB_LD;
            end
        end
    end

endmodule
