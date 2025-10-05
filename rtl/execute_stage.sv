/* Copyright (c) 2024 Tobias Scheipel: David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: execute_stage.sv
 */

typedef enum logic [3:0] {ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR, ALU_SLL, ALU_SRL, ALU_SRA} ALU_Operations; 
typedef enum logic {COMP_SLT, COMP_SLTU} Comparison_Operations;

module execute_stage (
    input logic clk,
    input logic rst,

    // Inputs
    input logic [31:0]   rs1_data_in,
    input logic [31:0]   rs2_data_in,
    input instruction::t instruction_in,
    input logic [31:0]   program_counter_in,

    // Outputs
    output logic [31:0]   source_data_reg_out,
    output logic [31:0]   rd_data_reg_out,
    output instruction::t instruction_reg_out,
    output logic [31:0]   program_counter_reg_out, 
    output logic [31:0]   next_program_counter_reg_out, 
    output forwarding::t  forwarding_out, 

    // Pipeline control
    input  pipeline_status::forwards_t  status_forwards_in,
    output pipeline_status::forwards_t  status_forwards_out, 
    input  pipeline_status::backwards_t status_backwards_in,
    output pipeline_status::backwards_t status_backwards_out, 
    input  logic [31:0] jump_address_backwards_in,
    output logic [31:0] jump_address_backwards_out 
);
    // ref_execute_stage golden(.*);
    
    // =================================
    // Internal Signals 
    // =================================

    //ALU Signals
    logic [31:0] ALU_in1;
    logic [31:0] ALU_in2;
    logic [31:0] ALU_output;
    ALU_Operations ALU_op_type;

    //Comparison Signals
    logic branch_taken;
    logic should_set;

    // Address calculations
    logic [31:0] jump_target;

    // Instruction Classification
    logic is_jump_instr;
    logic is_branch_instr;
    logic produces_result;

    // ================================
    // Instruction Classification
    // ================================
    always_comb begin
        is_jump_instr = (instruction_in.op == op::JAL) || (instruction_in.op == op::JALR);
        is_branch_instr = (instruction_in.op == op::BEQ) || (instruction_in.op == op::BNE) || (instruction_in.op == op::BLT) || (instruction_in.op == op::BLTU) || (instruction_in.op == op::BGE) || (instruction_in.op == op::BGEU);
        produces_result = (instruction_in.op inside {op::AUIPC, op::LUI, op::JAL, op::JALR, op::ADDI, op::XORI, op::ORI, op::ANDI, op::SLTI, op::SLTIU, op::SLLI, op::SRLI, op::SRAI, op::ADD, op::SUB, op::AND, op::OR, op::XOR, op::SLL, op::SRL, op::SRA, op::SLT, op::SLTU});
    end

    // ==============================
    // ALU Input Selection
    // ==============================
    always_comb begin
        ALU_in1 = 32'b0;
        ALU_in2 = 32'b0;
        
        case(instruction_in.op)
            // PC-relative operations
            op::AUIPC, op::JAL, op::BEQ, op::BNE, op::BLT, op::BLTU, op::BGE, op::BGEU: begin
                ALU_in1 = program_counter_in;
                ALU_in2 = instruction_in.immediate;
            end            
            // Register-immediate operations
            op::ADDI, op::XORI, op::ORI, op::ANDI, op::SLLI, op::SRLI, op::SRAI:  begin
                ALU_in1 = rs1_data_in;
                ALU_in2 = instruction_in.immediate;
            end
            
            // Register-register operations
            op::ADD, op::SUB, op::AND, op::OR, op::XOR, op::SLL, op::SRL, op::SRA: begin
                ALU_in1 = rs1_data_in;
                ALU_in2 = rs2_data_in;
            end
            
            // Load and Store
            op::LB, op::LH, op::LW, op::LBU, op::LHU, op::SB, op::SH, op::SW: begin
                ALU_in1 = rs1_data_in;
                ALU_in2 = instruction_in.immediate;
            end
            // Special cases
            op::JALR: begin
                ALU_in1 = rs1_data_in;
                ALU_in2 = instruction_in.immediate;
            end
            default: begin
                ALU_in1 = 32'b0;
                ALU_in2 = 32'b0;
            end
        endcase
    end

    // ==============================
    // ALU Operation Selection
    // ==============================
    always_comb begin
        case(instruction_in.op)
            // Addition operations
            op::AUIPC, op::JAL, op::JALR,
            op::BEQ, op::BNE, op::BLT, op::BGE, op::BLTU, op::BGEU,  // branches use ADD for target
            op::LB, op::LH, op::LW, op::LBU, op::LHU,                // loads use ADD for address
            op::SB, op::SH, op::SW,                                   // stores use ADD for address
            op::ADDI, op::ADD: begin
                ALU_op_type = ALU_ADD;
            end
            // Subtraction
            op::SUB: begin
                ALU_op_type = ALU_SUB;
            end
            // Logical operations
            op::ANDI, op::AND: begin
                ALU_op_type = ALU_AND;
            end
            op::ORI, op::OR: begin
                ALU_op_type = ALU_OR;
            end
            op::XORI, op::XOR: begin
                ALU_op_type = ALU_XOR;
            end
            // Shift operations
            op::SLLI, op::SLL: begin
                ALU_op_type = ALU_SLL;
            end
            op::SRLI, op::SRL: begin
                ALU_op_type = ALU_SRL;
            end
            op::SRAI, op::SRA: begin
                ALU_op_type = ALU_SRA;
            end
            // LUI doesn't use ALU (immediate goes directly to rd)
            op::LUI: begin
                ALU_op_type = ALU_ADD; // Doesn't matter, not used
            end
            // Comparison operations (SLT/SLTU handled separately)
            op::SLTI, op::SLT, op::SLTIU, op::SLTU: begin
                ALU_op_type = ALU_ADD; // Doesn't matter, comparator used instead
            end
            default: begin
                ALU_op_type = ALU_ADD;
            end
        endcase
    end

    always_comb begin
        case(ALU_op_type)
            ALU_ADD: ALU_output = ALU_in1 + ALU_in2;
            ALU_SUB: ALU_output = ALU_in1 - ALU_in2;
            ALU_AND: ALU_output = ALU_in1 & ALU_in2;
            ALU_OR: ALU_output = ALU_in1 | ALU_in2;
            ALU_XOR: ALU_output = ALU_in1 ^ ALU_in2;
            ALU_SLL: ALU_output = ALU_in1 << ALU_in2[4:0];
            ALU_SRL: ALU_output = ALU_in1 >> ALU_in2[4:0];
            ALU_SRA: ALU_output = $signed(ALU_in1) >>> ALU_in2[4:0];
            default: ALU_output = 32'b0;
        endcase
    end

    // ========================================
    // Combinational: Branch and Set Less Than Decision
    // ========================================
    always_comb begin
        branch_taken = 1'b0;
        should_set = 1'b0;
        
        case(instruction_in.op)
            op::BEQ:  branch_taken = (rs1_data_in == rs2_data_in);
            op::BNE:  branch_taken = (rs1_data_in != rs2_data_in);
            op::BLT:  branch_taken = ($signed(rs1_data_in) < $signed(rs2_data_in));
            op::BLTU: branch_taken = (rs1_data_in < rs2_data_in);
            op::BGE: branch_taken = ($signed(rs1_data_in) >= $signed(rs2_data_in));
            op::BGEU: branch_taken = (rs1_data_in >= rs2_data_in);
            op::SLT: should_set = ($signed(rs1_data_in) < $signed(rs2_data_in));
            op::SLTU: should_set = (rs1_data_in < rs2_data_in);
            op::SLTI: should_set = ($signed(rs1_data_in) < $signed(instruction_in.immediate));
            op::SLTIU: should_set = (rs1_data_in < instruction_in.immediate);
            default: begin end
        endcase
    end
    
    // ========================================
    // Combinational: Jump Target
    // ========================================
    always_comb begin
        jump_target = ALU_output;  // Default for most cases
        
        // Special handling for JALR (clear LSB)
        if (instruction_in.op == op::JALR) begin
            jump_target = ALU_output & ~32'h1;
        end
    end

    // ========================================
    // Combinational: Jump Address Backwards
    // ========================================
    always_comb begin
        if(status_backwards_in == pipeline_status::JUMP) begin
            jump_address_backwards_out = jump_address_backwards_in;
        end else if(is_jump_instr || (is_branch_instr && branch_taken)) begin
            jump_address_backwards_out = jump_target;
        end else begin
        jump_address_backwards_out = 32'b0;
        end
    end
    
    // ========================================
    // Combinational: Forwarding
    // ========================================   
    always_comb begin
        forwarding_out.address = (status_forwards_in == pipeline_status::VALID) ? instruction_in.rd_address : 5'b0;
        forwarding_out.data = (instruction_in.op == op::LUI) ? instruction_in.immediate :
                            (instruction_in.op inside {op::JAL, op::JALR}) ? program_counter_in + 4 :
                            (instruction_in.op inside {op::SLT, op::SLTU, op::SLTI, op::SLTIU}) ? (should_set) ? 32'b1 : 32'b0 :
                            ALU_output;
        forwarding_out.data_valid = produces_result && (status_forwards_in == pipeline_status::VALID);
    end

    // ========================================
    // Combinational: Backwards Status
    // ========================================
    always_comb begin
        if (status_backwards_in == pipeline_status::JUMP) begin
            status_backwards_out = pipeline_status::JUMP;
        end else if (status_backwards_in == pipeline_status::STALL) begin
            status_backwards_out = pipeline_status::STALL;
        end else if ((is_jump_instr || (is_branch_instr && branch_taken)) && status_forwards_in == pipeline_status::VALID) begin
            status_backwards_out = pipeline_status::JUMP;
        end else begin
            status_backwards_out = pipeline_status::READY;
        end
    end

    // ========================================
    // Sequential: Status Forwards
    // ========================================
    always_ff @(posedge clk) begin
        if (rst) begin
            status_forwards_out <= pipeline_status::BUBBLE;
        end else if (status_backwards_in == pipeline_status::JUMP) begin
            status_forwards_out <= pipeline_status::BUBBLE;
        end else if (status_backwards_in == pipeline_status::READY && 
                    status_forwards_in == pipeline_status::VALID) begin
            // Check for misaligned jump target
            if ((is_jump_instr || (is_branch_instr && branch_taken)) && 
                jump_target[1:0] != 2'b00) begin
                status_forwards_out <= pipeline_status::FETCH_MISALIGNED;
            end else begin
                status_forwards_out <= pipeline_status::VALID;
            end
        end else if (status_forwards_in != pipeline_status::VALID) begin
            // Pass through errors from decode stage
            status_forwards_out <= status_forwards_in;
        end else if (status_backwards_in == pipeline_status::STALL && status_forwards_in != pipeline_status::VALID) begin
            status_forwards_out <= pipeline_status::BUBBLE;
        end else begin
            // Stalled - maintain previous status
            // (status_forwards_out keeps its value)
        end
    end
    
    // ========================================
    // Sequential: Register Outputs
    // ========================================
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset all outputs
            rd_data_reg_out <= 32'b0;
            source_data_reg_out <= 32'b0;
            next_program_counter_reg_out <= 32'b0;
            instruction_reg_out <= '0;
            program_counter_reg_out <= 32'b0;
        end else if (status_backwards_in == pipeline_status::READY && 
                   status_forwards_in == pipeline_status::VALID) begin
            // Update outputs
            instruction_reg_out <= instruction_in;
            program_counter_reg_out <= program_counter_in;
            
            // Determine rd_data
            case(instruction_in.op)
                op::LUI: rd_data_reg_out <= instruction_in.immediate;
                op::JAL, op::JALR: rd_data_reg_out <= program_counter_in + 4;
                op::SLT, op::SLTI, op::SLTU, op::SLTIU: rd_data_reg_out <= should_set ? 32'b1 : 32'b0;
                // ALU operations
                default: rd_data_reg_out <= ALU_output;
            endcase
            
            //Handle source data out
            case(instruction_in.op)
                // Store operations: pass rs2_data to memory stage
                op::SB, op::SH, op::SW: begin
                    source_data_reg_out <= rs2_data_in;
                end
                
                // CSR operations: pass rs1_data (or immediate) to writeback
                op::CSRRW, op::CSRRS, op::CSRRC: begin
                    source_data_reg_out <= rs1_data_in;
                end
                
                op::CSRRWI, op::CSRRSI, op::CSRRCI: begin
                    source_data_reg_out <= instruction_in.immediate;
                end
                
                default: begin
                    source_data_reg_out <= 32'b0;
                end
            endcase

            // Next PC
            if (is_jump_instr || (is_branch_instr && branch_taken)) begin
                next_program_counter_reg_out <= jump_target;
            end else begin
                next_program_counter_reg_out <= program_counter_in + 4;
            end
            end else if(status_forwards_in != pipeline_status::BUBBLE) begin
                program_counter_reg_out <= program_counter_in;
            end
    end
endmodule
