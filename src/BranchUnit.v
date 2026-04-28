module BranchUnit (
    input  [31:0] pc_ex,
    input  [31:0] rs1_value,
    input  [31:0] rs2_value,
    input  [31:0] instruction,

    output reg        branch_taken,
    output reg [31:0] branch_target
);

    localparam BEQ = 7'b110_0011;

    wire [6:0] opcode;
    assign opcode = instruction[6:0];
    wire [31:0] branch_imm;

    assign branch_imm = {
        {20{instruction[31]}},
        instruction[7],
        instruction[30:25],
        instruction[11:8],
        1'b0
    };

    always @(*) begin
        // Valores padrão: branch não tomado, PC segue o fluxo normal (PC + 4)
        branch_taken  = 1'b0;
        branch_target = pc_ex + 32'd4;

        // Verifica se a instrução atual é um BEQ
        if (opcode == BEQ) begin
            // Compara os operandos rs1 e rs2
            if (rs1_value == rs2_value) begin
                // Se forem iguais, o branch é tomado
                branch_taken  = 1'b1;
                // O novo endereço é o PC da instrução atual (no estágio EX) + o imediato calculado
                branch_target = pc_ex + branch_imm;
            end
        end
    end

endmodule
