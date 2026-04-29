`timescale 1ns/1ps

// =============================================================================
// Testbench Adicional — Pipeline RISC-V
// Testa cenários específicos além do programa principal do professor:
//   - Test 1: Forwarding em cadeia ALU → ALU (FROM_MEM)
//   - Test 2: Hazard load-use isolado (stall obrigatório)
//   - Test 3: Branch não tomado (BEQ com operandos diferentes)
//   - Test 4: Forwarding do estágio WB (instrução 2 ciclos atrás)
// =============================================================================

module tb_extra_tests;

    reg clock;
    reg reset;

    wire halt;

    integer i;

    RISCVCPU cpu (
        .clock(clock),
        .reset(reset),
        .halt(halt)
    );

    // -------------------------------------------------------------------------
    // Clock: período de 10ns
    // -------------------------------------------------------------------------
    initial begin
        clock = 1'b0;
        forever #5 clock = ~clock;
    end

    // -------------------------------------------------------------------------
    // Dump para GTKWave
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("wave_extra.vcd");
        $dumpvars(0, tb_extra_tests);
    end

    // -------------------------------------------------------------------------
    // Execução sequencial dos 4 testes
    // -------------------------------------------------------------------------
    initial begin
        run_test1_alu_forwarding_chain();
        run_test2_load_use_stall();
        run_test3_branch_not_taken();
        run_test4_wb_forwarding();
        $display("\n=== TODOS OS TESTES EXTRAS CONCLUIDOS ===\n");
        $finish;
    end

    // =========================================================================
    // Utilitários compartilhados
    // =========================================================================

    task reset_cpu;
        begin
            reset = 1'b1;
            #20;
            reset = 1'b0;
        end
    endtask

    task clear_memories;
        begin
            for (i = 0; i < 1024; i = i + 1) begin
                cpu.IMemory[i] = 32'h0000_0013; // nop
                cpu.DMemory[i] = 32'd0;
            end
        end
    endtask

    task print_stats;
        input [8*40-1:0] program_name;
        real cpi;
        begin
            cpi = 0.0;
            if (cpu.stats.instr_count != 0) begin
                cpi = $itor(cpu.stats.cycle_count) / $itor(cpu.stats.instr_count);
            end
            $display("\n============================================");
            $display("Teste        : %0s", program_name);
            $display("Cycles       : %0d", cpu.stats.cycle_count);
            $display("Instructions : %0d", cpu.stats.instr_count);
            $display("Stalls       : %0d", cpu.stats.stall_count);
            $display("Bypasses     : %0d", cpu.stats.bypass_count);
            $display("Branches     : %0d", cpu.stats.branch_taken_count);
            $display("Flushes      : %0d", cpu.stats.flush_count);
            $display("CPI          : %0.2f", cpi);
            $display("============================================\n");
        end
    endtask

    task print_state_nonzero;
        begin
            $display("-- REGISTRADORES (nao-zero) --");
            for (i = 0; i < 32; i = i + 1) begin
                if (cpu.Regs[i] != 0)
                    $display("  x%0d = %0d (0x%08h)", i, cpu.Regs[i], cpu.Regs[i]);
            end
            $display("-- MEMORIA DE DADOS (nao-zero) --");
            for (i = 0; i < 32; i = i + 1) begin
                if (cpu.DMemory[i] != 0)
                    $display("  mem[%0d] = %0d (0x%08h)", i, cpu.DMemory[i], cpu.DMemory[i]);
            end
        end
    endtask

    // =========================================================================
    // TEST 1 — Forwarding em cadeia ALU → ALU
    // =========================================================================
    // Objetivo: verificar o forwarding FROM_MEM em instruções consecutivas.
    // Cada instrução depende diretamente do resultado da anterior (cadeia RAW).
    //
    // Programa:
    //   addi x1, x0, 10   # x1 = 10
    //   addi x2, x1,  5   # x2 = x1 + 5 = 15  → forwarding FROM_MEM (x1 em EX/MEM)
    //   addi x3, x2,  3   # x3 = x2 + 3 = 18  → forwarding FROM_MEM (x2 em EX/MEM)
    //   halt
    //
    // Esperado: x1=10, x2=15, x3=18
    //           Stalls=0, Bypasses=2 (dois encaminhamentos FROM_MEM)
    // =========================================================================

    task run_test1_alu_forwarding_chain;
        begin
            clear_memories();
            load_test1();
            reset_cpu();
            while (!halt) @(posedge clock);
            print_stats("test1_alu_forwarding_chain");
            check_test1();
            print_state_nonzero();
        end
    endtask

    task load_test1;
        begin
            // addi x1, x0, 10  → 0x00A00093
            cpu.IMemory[0] = 32'h00A00093;
            // addi x2, x1, 5   → 0x00508113
            cpu.IMemory[1] = 32'h00508113;
            // addi x3, x2, 3   → 0x00310193
            cpu.IMemory[2] = 32'h00310193;
            // halt              → 0x0000000B
            cpu.IMemory[3] = 32'h0000000B;
        end
    endtask

    task check_test1;
        integer errors;
        begin
            errors = 0;
            $display("============================");
            $display("CHECK TEST 1");
            $display("============================");
            if (cpu.Regs[1] !== 32'd10) begin
                $display("FAIL: x1 esperado 10, obtido %0d", cpu.Regs[1]);
                errors = errors + 1;
            end
            if (cpu.Regs[2] !== 32'd15) begin
                $display("FAIL: x2 esperado 15, obtido %0d", cpu.Regs[2]);
                errors = errors + 1;
            end
            if (cpu.Regs[3] !== 32'd18) begin
                $display("FAIL: x3 esperado 18, obtido %0d", cpu.Regs[3]);
                errors = errors + 1;
            end
            if (errors == 0)
                $display("PASS: todos os resultados corretos.");
            else
                $display("FAIL: %0d erro(s) encontrado(s).", errors);
            $display("============================\n");
        end
    endtask

    // =========================================================================
    // TEST 2 — Hazard Load-Use isolado
    // =========================================================================
    // Objetivo: verificar que a HazardDetectionUnit insere exatamente 1 stall
    // quando uma instrução LW é seguida imediatamente por uma instrução que
    // usa o registrador carregado. O forwarding sozinho não resolve esse caso.
    //
    // Programa:
    //   lw   x1, 0(x0)    # x1 = mem[0] = 7
    //   addi x2, x1, 3    # HAZARD load-use → stall + x2 = x1 + 3 = 10
    //   halt
    //
    // Esperado: x1=7, x2=10
    //           Stalls=1, Bypasses>=1 (forwarding FROM_WB_LD após o stall)
    // =========================================================================

    task run_test2_load_use_stall;
        begin
            clear_memories();
            load_test2();
            reset_cpu();
            while (!halt) @(posedge clock);
            print_stats("test2_load_use_stall");
            check_test2();
            print_state_nonzero();
        end
    endtask

    task load_test2;
        begin
            cpu.DMemory[0] = 32'd7;

            // lw   x1, 0(x0)  → 0x00002083
            cpu.IMemory[0] = 32'h00002083;
            // addi x2, x1, 3  → 0x00308113
            cpu.IMemory[1] = 32'h00308113;
            // halt             → 0x0000000B
            cpu.IMemory[2] = 32'h0000000B;
        end
    endtask

    task check_test2;
        integer errors;
        begin
            errors = 0;
            $display("============================");
            $display("CHECK TEST 2");
            $display("============================");
            if (cpu.Regs[1] !== 32'd7) begin
                $display("FAIL: x1 esperado 7, obtido %0d", cpu.Regs[1]);
                errors = errors + 1;
            end
            if (cpu.Regs[2] !== 32'd10) begin
                $display("FAIL: x2 esperado 10, obtido %0d", cpu.Regs[2]);
                errors = errors + 1;
            end
            if (errors == 0)
                $display("PASS: todos os resultados corretos.");
            else
                $display("FAIL: %0d erro(s) encontrado(s).", errors);
            $display("============================\n");
        end
    endtask

    // =========================================================================
    // TEST 3 — Branch NÃO tomado
    // =========================================================================
    // Objetivo: verificar que quando os operandos do BEQ são diferentes, o
    // branch NÃO é tomado, nenhum flush ocorre, e a instrução seguinte ao
    // branch executa normalmente.
    //
    // Programa:
    //   addi x1, x0,  5   # x1 = 5
    //   addi x2, x0, 10   # x2 = 10
    //   beq  x1, x2, label # x1 != x2 → branch NÃO tomado, sem flush
    //   addi x3, x0,  1   # x3 = 1 → DEVE executar (branch não tomado)
    //   label:
    //   addi x4, x0,  2   # x4 = 2 → DEVE executar
    //   halt
    //
    // Esperado: x1=5, x2=10, x3=1, x4=2
    //           Branches=0, Flushes=0
    // =========================================================================

    task run_test3_branch_not_taken;
        begin
            clear_memories();
            load_test3();
            reset_cpu();
            while (!halt) @(posedge clock);
            print_stats("test3_branch_not_taken");
            check_test3();
            print_state_nonzero();
        end
    endtask

    task load_test3;
        begin
            // addi x1, x0, 5   → 0x00500093
            cpu.IMemory[0] = 32'h00500093;
            // addi x2, x0, 10  → 0x00A00113
            cpu.IMemory[1] = 32'h00A00113;
            // beq x1, x2, +8   → PC=8, label em PC=16, offset=8
            // Encoding B-type: imm=8 → imm[12]=0,imm[11]=0,imm[10:5]=000000,imm[4:1]=0100
            // 0_000000_00010_00001_000_0100_0_1100011 = 0x00208463
            cpu.IMemory[2] = 32'h00208463;
            // addi x3, x0, 1   → 0x00100193  (deve executar)
            cpu.IMemory[3] = 32'h00100193;
            // label:
            // addi x4, x0, 2   → 0x00200213  (deve executar)
            cpu.IMemory[4] = 32'h00200213;
            // halt              → 0x0000000B
            cpu.IMemory[5] = 32'h0000000B;
        end
    endtask

    task check_test3;
        integer errors;
        begin
            errors = 0;
            $display("============================");
            $display("CHECK TEST 3");
            $display("============================");
            if (cpu.Regs[1] !== 32'd5) begin
                $display("FAIL: x1 esperado 5, obtido %0d", cpu.Regs[1]);
                errors = errors + 1;
            end
            if (cpu.Regs[2] !== 32'd10) begin
                $display("FAIL: x2 esperado 10, obtido %0d", cpu.Regs[2]);
                errors = errors + 1;
            end
            if (cpu.Regs[3] !== 32'd1) begin
                $display("FAIL: x3 esperado 1, obtido %0d (instrucao apos branch nao executou)", cpu.Regs[3]);
                errors = errors + 1;
            end
            if (cpu.Regs[4] !== 32'd2) begin
                $display("FAIL: x4 esperado 2, obtido %0d", cpu.Regs[4]);
                errors = errors + 1;
            end
            if (errors == 0)
                $display("PASS: todos os resultados corretos.");
            else
                $display("FAIL: %0d erro(s) encontrado(s).", errors);
            $display("============================\n");
        end
    endtask

    // =========================================================================
    // TEST 4 — Forwarding do estágio WB (FROM_WB_ALU)
    // =========================================================================
    // Objetivo: verificar o forwarding quando há 1 instrução de distância entre
    // a produtora e a consumidora (resultado disponível no estágio MEM/WB).
    // Nesse caso, o valor já saiu do estágio EX/MEM, portanto o forwarding
    // vem de MEM/WB, não de EX/MEM.
    //
    // Programa:
    //   addi x1, x0, 20   # x1 = 20
    //   addi x2, x0,  3   # x2 = 3  (filler — sem dependência, afasta x1 um ciclo)
    //   addi x3, x1,  7   # x3 = x1 + 7 = 27 → forwarding FROM_WB_ALU
    //   halt
    //
    // Esperado: x1=20, x2=3, x3=27
    //           Stalls=0, Bypasses>=1 (FROM_WB_ALU ativo para x1)
    // =========================================================================

    task run_test4_wb_forwarding;
        begin
            clear_memories();
            load_test4();
            reset_cpu();
            while (!halt) @(posedge clock);
            print_stats("test4_wb_forwarding");
            check_test4();
            print_state_nonzero();
        end
    endtask

    task load_test4;
        begin
            // addi x1, x0, 20  → imm=20=0x14 → 0x01400093
            cpu.IMemory[0] = 32'h01400093;
            // addi x2, x0, 3   → 0x00300113
            cpu.IMemory[1] = 32'h00300113;
            // addi x3, x1, 7   → imm=7, rs1=1, rd=3 → 0x00708193
            cpu.IMemory[2] = 32'h00708193;
            // halt              → 0x0000000B
            cpu.IMemory[3] = 32'h0000000B;
        end
    endtask

    task check_test4;
        integer errors;
        begin
            errors = 0;
            $display("============================");
            $display("CHECK TEST 4");
            $display("============================");
            if (cpu.Regs[1] !== 32'd20) begin
                $display("FAIL: x1 esperado 20, obtido %0d", cpu.Regs[1]);
                errors = errors + 1;
            end
            if (cpu.Regs[2] !== 32'd3) begin
                $display("FAIL: x2 esperado 3, obtido %0d", cpu.Regs[2]);
                errors = errors + 1;
            end
            if (cpu.Regs[3] !== 32'd27) begin
                $display("FAIL: x3 esperado 27, obtido %0d", cpu.Regs[3]);
                errors = errors + 1;
            end
            if (errors == 0)
                $display("PASS: todos os resultados corretos.");
            else
                $display("FAIL: %0d erro(s) encontrado(s).", errors);
            $display("============================\n");
        end
    endtask

endmodule
