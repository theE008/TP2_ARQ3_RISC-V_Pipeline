module HazardDetectionUnit (
    input [4:0] idex_rs1,
    input [4:0] idex_rs2,
    input [4:0] exmem_rd,

    input [6:0] idex_op,
    input [6:0] exmem_op,

    output reg stall
);

    localparam LW    = 7'b000_0011;
    localparam SW    = 7'b010_0011;
    localparam BEQ   = 7'b110_0011;
    localparam ALUop = 7'b001_0011;

    initial begin
        stall = 1'b0;
    end

    always @(*) begin
        stall = 1'b0;

        // Load-use hazard:
        // Se a instrução no EX/MEM é um LW e seu registrador de destino não for x0
        if ((exmem_op == LW) && (exmem_rd != 5'd0)) begin
            // Verifica se a instrução atual no ID/EX REALMENTE lê os operandos
            // rs1 é lido por: LW, SW, ALUop(addi), BEQ
            if ((exmem_rd == idex_rs1) && ((idex_op == LW) || (idex_op == SW) || (idex_op == ALUop) || (idex_op == BEQ))) begin
                stall = 1'b1;
            end
            // rs2 é lido por: SW, BEQ (ALUop/addi e LW usam imediatos no lugar do rs2)
            else if ((exmem_rd == idex_rs2) && ((idex_op == SW) || (idex_op == BEQ))) begin
                stall = 1'b1;
            end
        end
    end

endmodule
