/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: writeback_stage.sv
 */



module writeback_stage (
    input logic clk,
    input logic rst,

    // Inputs from Memory Stage
    input logic [31:0]   source_data_in,           // Data for stores (not used here) or CSR writes
    input logic [31:0]   rd_data_in,               // Result from ALU or Load
    input instruction::t instruction_in,           // Decoded instruction
    input logic [31:0]   program_counter_in,       // PC of the current instruction
    input logic [31:0]   next_program_counter_in,  // PC calculated by Execute stage

    // Interrupt signals
    input logic external_interrupt_in,
    input logic timer_interrupt_in,

    // Outputs
    output forwarding::t forwarding_out,             // Data being written back (to RF and forwarding unit)

    // Pipeline control
    input  pipeline_status::forwards_t  status_forwards_in,       // Status from Memory Stage
    output pipeline_status::backwards_t status_backwards_out,     // Always READY for Writeback
    output logic [31:0]                 jump_address_backwards_out // Target address for jumps
);

    // ========================
    // Intermediate Values
    // ========================
    logic is_csr_instr;
    logic is_mret;
    logic has_rd;                   // Does the instruction potentially write to rd?
    logic should_writeback_rf;      // Should we actually write to the register file?
    logic should_trap;
    logic should_jump;
    logic should_ext_interrupt;
    logic should_tim_interrupt;
    logic is_exception;
    logic is_interrupt;
    logic is_fence_i;
    logic [31:0] csr_read_data;      // Value read from CSR
    logic [31:0] csr_write_data_calc;// Potential Value to write to CSR based *only* on instr type
    logic [31:0] final_rd_data;      // Final value for forwarding (either rd_data_in or csr_read_data)

    // Potential next state assuming CSR write occurs (before trap/mret override)
    logic [31:0] potential_mstatus_next;
    logic [31:0] potential_mie_next;
    // Final next state after considering trap/mret overrides
    logic [31:0] final_mstatus_next;
    logic [31:0] final_mie_next;


    // CSR Enables
    logic mstatus_en;
    logic mtvec_en;
    logic mie_en;
    logic mcycle_en;
    logic mcycleh_en;
    logic minstret_en;
    logic minstreth_en;
    logic mscratch_en;
    logic mepc_en;
    logic mcause_en;

    // CSR Data Inputs
    logic[31:0] mstatus_in;
    logic[31:0] mtvec_in;
    logic[31:0] mie_in;
    logic[31:0] mcycle_in;
    logic[31:0] mcycleh_in;
    logic[31:0] minstret_in;
    logic[31:0] minstreth_in;
    logic[31:0] mscratch_in;
    logic[31:0] mepc_in;
    logic[31:0] mcause_in;

    // CSR Valid Instr (for incrementing minstret)
    logic valid_instruction_completed;
    logic interrupt_pending;

    // CSR Outputs
    logic[31:0] mstatus_out;
    logic[31:0] mtvec_out;
    logic[31:0] mip_out;
    logic[31:0] mie_out;
    logic[31:0] mcycle_out;
    logic[31:0] mcycleh_out;
    logic[31:0] minstret_out;
    logic[31:0] minstreth_out;
    logic[31:0] mscratch_out;
    logic[31:0] mepc_out;
    logic[31:0] mcause_out;

    // ========================
    // Instantiate CSR File
    // ========================
    csr_file cf (
        .clk(clk), .rst(rst),
        .mstatus_en(mstatus_en), .mtvec_en(mtvec_en), .mie_en(mie_en), .mcycle_en(mcycle_en), .mcycleh_en(mcycleh_en),
        .minstret_en(minstret_en), .minstreth_en(minstreth_en), .mscratch_en(mscratch_en), .mepc_en(mepc_en), .mcause_en(mcause_en),
        .mstatus_in(mstatus_in), .mtvec_in(mtvec_in), .mie_in(mie_in), .mcycle_in(mcycle_in), .mcycleh_in(mcycleh_in),
        .minstret_in(minstret_in), .minstreth_in(minstreth_in), .mscratch_in(mscratch_in), .mepc_in(mepc_in), .mcause_in(mcause_in),
        .external_interrupt(external_interrupt_in), .timer_interrupt(timer_interrupt_in),
        .valid_instruction(valid_instruction_completed),
        .mstatus_out(mstatus_out), .mtvec_out(mtvec_out), .mip_out(mip_out), .mie_out(mie_out), .mcycle_out(mcycle_out), .mcycleh_out(mcycleh_out),
        .minstret_out(minstret_out), .minstreth_out(minstreth_out), .mscratch_out(mscratch_out), .mepc_out(mepc_out), .mcause_out(mcause_out)
    );
    
    // ========================
    // Interrupt Handling
    // ========================
    always_ff @(posedge clk) begin
        interrupt_pending <= 1'b0;
        if(rst) begin
            interrupt_pending <= 1'b0;
        end else begin
            if(is_interrupt) begin
                interrupt_pending <= 1'b1;
            end
        end
    end
    

    // ============================================
    // Combinational Logic Block 1: Identification, Potential CSR State, Interrupt Check
    // ============================================
    always_comb begin
        // --- Identify Instruction Type ---
        is_csr_instr = instruction_in.op inside {
            op::CSRRW, op::CSRRS, op::CSRRC,
            op::CSRRWI, op::CSRRSI, op::CSRRCI
        };
        is_mret = (instruction_in.op == op::MRET);
        is_fence_i = (instruction_in.op == op::FENCE_I);
        has_rd = instruction_in.op inside { /* ... same as before ... */
            op::ADD, op::ADDI, op::SUB,
            op::AND, op::ANDI, op::OR, op::ORI, op::XOR, op::XORI,
            op::SLL, op::SLLI, op::SRL, op::SRLI, op::SRA, op::SRAI,
            op::SLT, op::SLTI, op::SLTU, op::SLTIU,
            op::LUI, op::AUIPC,
            op::JAL, op::JALR,
            op::LB, op::LH, op::LW, op::LBU, op::LHU,
            op::CSRRW, op::CSRRS, op::CSRRC,
            op::CSRRWI, op::CSRRSI, op::CSRRCI
        };

        // --- Calculate Potential CSR Write Data ---
        csr_write_data_calc = 32'b0; // Default needed
        case (instruction_in.op)
            op::CSRRW:  csr_write_data_calc = source_data_in;
            op::CSRRS:  csr_write_data_calc = csr_read_data | source_data_in;
            op::CSRRC:  csr_write_data_calc = csr_read_data & ~source_data_in;
            op::CSRRWI: csr_write_data_calc = {27'b0, instruction_in.immediate[4:0]};
            op::CSRRSI: csr_write_data_calc = csr_read_data | {27'b0, instruction_in.immediate[4:0]};
            op::CSRRCI: csr_write_data_calc = csr_read_data & ~{27'b0, instruction_in.immediate[4:0]};
            default:    csr_write_data_calc = 32'b0;
        endcase

        // --- Determine Potential Next State of MSTATUS and MIE ---
        // (Assuming the CSR instruction executes without trap/mret override)
        potential_mstatus_next = mstatus_out;
        potential_mie_next     = mie_out;
        if (is_csr_instr && valid_instruction_completed) begin
            case (instruction_in.csr)
                csr::MSTATUS: potential_mstatus_next = csr_write_data_calc;
                csr::MIE:     potential_mie_next     = csr_write_data_calc;
                default: ; // Other CSRs don't affect interrupt check
            endcase
        end

        // --- Read Current CSR Value (needed for CSR ops and forwarding) ---
        case (instruction_in.csr)
             csr::MSTATUS:   csr_read_data = mstatus_out;
             csr::MTVEC:     csr_read_data = mtvec_out;
             csr::MIP:       csr_read_data = mip_out;
             csr::MIE:       csr_read_data = mie_out;
             csr::MCYCLE:    csr_read_data = mcycle_out;
             csr::MCYCLEH:   csr_read_data = mcycleh_out;
             csr::MINSTRET:  csr_read_data = minstret_out;
             csr::MINSTRETH: csr_read_data = minstreth_out;
             csr::MSCRATCH:  csr_read_data = mscratch_out;
             csr::MEPC:      csr_read_data = mepc_out;
             csr::MCAUSE:    csr_read_data = mcause_out;
             default:        csr_read_data = 32'b0;
        endcase

        should_ext_interrupt = mip_out[11] & potential_mie_next[11] & potential_mstatus_next[3];
        should_tim_interrupt = mip_out[7]  & potential_mie_next[7]  & potential_mstatus_next[3];
        is_interrupt = should_ext_interrupt | should_tim_interrupt;

        // --- Identify Exceptions ---
        is_exception = status_forwards_in inside { /* ... same as before ... */
            pipeline_status::FETCH_MISALIGNED, pipeline_status::FETCH_FAULT,
            pipeline_status::ILLEGAL_INSTRUCTION, pipeline_status::EBREAK,
            pipeline_status::LOAD_MISALIGNED, pipeline_status::LOAD_FAULT,
            pipeline_status::STORE_MISALIGNED, pipeline_status::STORE_FAULT,
            pipeline_status::ECALL
        };

        // --- Determine if Instruction Completes and if Trap/Jump Occurs ---
        valid_instruction_completed = (status_forwards_in == pipeline_status::VALID) || is_exception;
        should_trap = is_exception || (valid_instruction_completed & interrupt_pending);
        // Only jump if the instruction is valid/exception (not bubble) AND a jump condition is met
        should_jump = valid_instruction_completed && (should_trap || is_mret || is_fence_i);

        // --- Determine Final Next State of MSTATUS/MIE (applying overrides) ---
        final_mstatus_next = potential_mstatus_next;
        final_mie_next     = potential_mie_next; // Start with potential state
        if (should_trap) begin
            final_mstatus_next[7] = potential_mstatus_next[3]; // MPIE = MIE
            final_mstatus_next[3] = 1'b0;                      // MIE = 0
        end else if (is_mret) begin
            final_mstatus_next[3] = potential_mstatus_next[7]; // MIE = MPIE
            final_mstatus_next[7] = 1'b1;                      // MPIE = 1
        end // Otherwise, potential state is the final state

        // --- Determine if writeback to RF should happen ---
        should_writeback_rf = has_rd && (instruction_in.rd_address != 5'b0) && !is_exception && status_forwards_in == pipeline_status::VALID;

        // --- Determine final data for rd ---
        final_rd_data = (is_csr_instr) ? csr_read_data : rd_data_in;
    end

    // ===================================
    // Forwarding Output (Combinational)
    // ===================================
    assign forwarding_out = '{
        address:    should_writeback_rf ? instruction_in.rd_address : 5'b0,
        data:       final_rd_data,
        data_valid: should_writeback_rf
    };

    // =====================================
    // Combinational Logic Block 2: Set CSR Enables and Inputs based on Final Decision
    // =====================================
    always_comb begin
        // Default: No CSR writes enabled
        mstatus_en = 1'b0; mtvec_en = 1'b0; mie_en = 1'b0; mcycle_en = 1'b0; mcycleh_en = 1'b0;
        minstret_en = 1'b0; minstreth_en = 1'b0; mscratch_en = 1'b0; mepc_en = 1'b0; mcause_en = 1'b0;

        // Default CSR inputs
        mstatus_in = 32'b0; mtvec_in = 32'b0; mie_in = 32'b0; mcycle_in = 32'b0; mcycleh_in = 32'b0;
        minstret_in = 32'b0; minstreth_in = 32'b0; mscratch_in = 32'b0; mepc_in = 32'b0; mcause_in = 32'b0;

        // --- Set Enables and Inputs based on final action ---
        if (should_trap) begin
            // Update MCAUSE
            mcause_en = 1'b1;
            mcause_in[31] = is_interrupt; // MSB indicates interrupt (1) or exception (0)
            if (is_exception) begin
                case (status_forwards_in)
                    pipeline_status::FETCH_MISALIGNED: mcause_in[30:0] = 0;
                    pipeline_status::FETCH_FAULT:      mcause_in[30:0] = 1;
                    pipeline_status::ILLEGAL_INSTRUCTION: mcause_in[30:0] = 2;
                    pipeline_status::EBREAK:           mcause_in[30:0] = 3;
                    pipeline_status::LOAD_MISALIGNED:  mcause_in[30:0] = 4;
                    pipeline_status::LOAD_FAULT:       mcause_in[30:0] = 5;
                    pipeline_status::STORE_MISALIGNED: mcause_in[30:0] = 6;
                    pipeline_status::STORE_FAULT:      mcause_in[30:0] = 7;
                    pipeline_status::ECALL:            mcause_in[30:0] = 11;
                    default:                           mcause_in[30:0] = 2; // Default to illegal instruction
                endcase
            end else begin // Interrupt
                mcause_in[30:0] = should_ext_interrupt ? 11 : 7;
            end

            // Update MEPC
            mepc_en = 1'b1;
            mepc_in = is_exception ? program_counter_in : next_program_counter_in;
            mepc_in[1:0] = 2'b00;

            // Update MSTATUS
            mstatus_en = 1'b1;
            mstatus_in = final_mstatus_next; // Use the calculated final state

        end else if (is_mret) begin
            // Update MSTATUS
            mstatus_en = 1'b1;
            mstatus_in = final_mstatus_next; // Use the calculated final state

        end else if (is_csr_instr && valid_instruction_completed) begin
            // Apply the normal CSR write (using potential_ values implicitly via csr_write_data_calc)
            case (instruction_in.csr)
                csr::MSTATUS:   begin mstatus_en  = 1'b1; mstatus_in  = csr_write_data_calc; end
                csr::MTVEC:     begin mtvec_en    = 1'b1; mtvec_in    = csr_write_data_calc; mtvec_in[1:0] = 2'b00; end
                csr::MIE:       begin mie_en      = 1'b1; mie_in      = csr_write_data_calc; end
                csr::MCYCLE:    begin mcycle_en   = 1'b1; mcycle_in   = csr_write_data_calc; end
                csr::MCYCLEH:   begin mcycleh_en  = 1'b1; mcycleh_in  = csr_write_data_calc; end
                csr::MINSTRET:  begin minstret_en = 1'b1; minstret_in = csr_write_data_calc; end
                csr::MINSTRETH: begin minstreth_en= 1'b1; minstreth_in= csr_write_data_calc; end
                csr::MSCRATCH:  begin mscratch_en = 1'b1; mscratch_in = csr_write_data_calc; end
                csr::MEPC:      begin mepc_en     = 1'b1; mepc_in     = csr_write_data_calc; mepc_in[1:0] = 2'b00; end
                csr::MCAUSE:    begin mcause_en   = 1'b1; mcause_in   = csr_write_data_calc; end
                default:        ; // No effect for unimplemented CSRs
            endcase
        end
    end


    // ========================
    // Pipeline Control Output (Combinational)
    // ========================
    assign status_backwards_out = should_jump ? pipeline_status::JUMP : pipeline_status::READY;
    assign jump_address_backwards_out = should_trap  ? mtvec_out
                                        : is_mret    ? mepc_out
                                        : is_fence_i ? next_program_counter_in
                                        : 32'b0;

endmodule
