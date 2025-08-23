/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: cpu.sv
 */



module cpu (
    input logic clk,
    input logic rst,

    wishbone_interface.master memory_fetch_port,
    wishbone_interface.master memory_mem_port,

    input logic external_interrupt_in,
    input logic timer_interrupt_in
);

    // INTERMEDIATE OUTPUT LOGIC

    // Fetch
    logic [31:0] f_instruction_reg_out;
    logic [31:0] f_program_counter_reg_out;
    pipeline_status::forwards_t  f_status_forwards_out; 

    // Decode
    instruction::t d_instruction_reg_out;
    logic [31:0] d_program_counter_reg_out;
    logic [31:0] d_rs1_data_reg_out;
    logic [31:0] d_rs2_data_reg_out;
    pipeline_status::forwards_t  d_status_forwards_out;
    pipeline_status::backwards_t d_status_backwards_out;
    logic [31:0] d_jump_address_backwards_out;

    // Execute
    logic [31:0]   e_source_data_reg_out;
    logic [31:0]   e_rd_data_reg_out;
    instruction::t e_instruction_reg_out;
    logic [31:0]   e_program_counter_reg_out;
    logic [31:0]   e_next_program_counter_reg_out;
    forwarding::t  e_forwarding_out;
    pipeline_status::forwards_t  e_status_forwards_out;
    pipeline_status::backwards_t e_status_backwards_out;
    logic [31:0] e_jump_address_backwards_out;

    // Memory
    logic [31:0]   m_source_data_reg_out;
    logic [31:0]   m_rd_data_reg_out;
    instruction::t m_instruction_reg_out;
    logic [31:0]   m_program_counter_reg_out;
    logic [31:0]   m_next_program_counter_reg_out;
    forwarding::t  m_forwarding_out;
    pipeline_status::forwards_t  m_status_forwards_out;
    pipeline_status::backwards_t m_status_backwards_out;
    logic [31:0] m_jump_address_backwards_out;

    // Writeback
    forwarding::t w_forwarding_out;
    pipeline_status::backwards_t w_status_backwards_out;
    logic [31:0] w_jump_address_backwards_out;

    fetch_stage fetch_stage (
        .clk(clk),
        .rst(rst),

        // Memory interface
        .wb(memory_fetch_port),

        // Inputs
        .status_backwards_in(d_status_backwards_out),
        .jump_address_backwards_in(d_jump_address_backwards_out),

        // Outputs
        .instruction_reg_out(f_instruction_reg_out),
        .program_counter_reg_out(f_program_counter_reg_out),
        .status_forwards_out(f_status_forwards_out)
    );

    decode_stage decode_stage (
        .clk(clk),
        .rst(rst),

        // Inputs
        .instruction_in(f_instruction_reg_out),
        .program_counter_in(f_program_counter_reg_out),
        .exe_forwarding_in(e_forwarding_out),
        .mem_forwarding_in(m_forwarding_out),
        .wb_forwarding_in(w_forwarding_out),
        .status_forwards_in(f_status_forwards_out),
        .status_backwards_in(e_status_backwards_out),
        .jump_address_backwards_in(e_jump_address_backwards_out),

        // Outputs
        .instruction_reg_out(d_instruction_reg_out),
        .program_counter_reg_out(d_program_counter_reg_out),
        .rs1_data_reg_out(d_rs1_data_reg_out),
        .rs2_data_reg_out(d_rs2_data_reg_out),
        .status_forwards_out(d_status_forwards_out),
        .status_backwards_out(d_status_backwards_out),
        .jump_address_backwards_out(d_jump_address_backwards_out)
    );

    execute_stage execute_stage (
        .clk(clk),
        .rst(rst),

        // Inputs
        .rs1_data_in(d_rs1_data_reg_out),
        .rs2_data_in(d_rs2_data_reg_out),
        .instruction_in(d_instruction_reg_out),
        .program_counter_in(d_program_counter_reg_out),
        .status_forwards_in(d_status_forwards_out),
        .status_backwards_in(m_status_backwards_out),
        .jump_address_backwards_in(m_jump_address_backwards_out),

        // Outputs
        .source_data_reg_out(e_source_data_reg_out),
        .rd_data_reg_out(e_rd_data_reg_out),
        .instruction_reg_out(e_instruction_reg_out),
        .program_counter_reg_out(e_program_counter_reg_out),
        .next_program_counter_reg_out(e_next_program_counter_reg_out),
        .forwarding_out(e_forwarding_out),
        .status_forwards_out(e_status_forwards_out),
        .status_backwards_out(e_status_backwards_out),
        .jump_address_backwards_out(e_jump_address_backwards_out)
    );

    memory_stage memory_stage (
        .clk(clk),
        .rst(rst),
        .wb(memory_mem_port),

        // Inputs
        .source_data_in(e_source_data_reg_out),
        .rd_data_in(e_rd_data_reg_out),
        .instruction_in(e_instruction_reg_out),
        .program_counter_in(e_program_counter_reg_out),
        .next_program_counter_in(e_next_program_counter_reg_out),
        .status_forwards_in(e_status_forwards_out),
        .status_backwards_in(w_status_backwards_out),
        .jump_address_backwards_in(w_jump_address_backwards_out),

        // Outputs
        .source_data_reg_out(m_source_data_reg_out),
        .rd_data_reg_out(m_rd_data_reg_out),
        .instruction_reg_out(m_instruction_reg_out),
        .program_counter_reg_out(m_program_counter_reg_out),
        .next_program_counter_reg_out(m_next_program_counter_reg_out),
        .forwarding_out(m_forwarding_out),
        .status_forwards_out(m_status_forwards_out),
        .status_backwards_out(m_status_backwards_out),
        .jump_address_backwards_out(m_jump_address_backwards_out)
    );

    writeback_stage writeback_stage(
        .clk(clk),
        .rst(rst),

        // Inputs
        .source_data_in(m_source_data_reg_out),
        .rd_data_in(m_rd_data_reg_out),
        .instruction_in(m_instruction_reg_out),
        .program_counter_in(m_program_counter_reg_out),
        .next_program_counter_in(m_next_program_counter_reg_out),
        .external_interrupt_in(external_interrupt_in),
        .timer_interrupt_in(timer_interrupt_in),
        .status_forwards_in(m_status_forwards_out),

        //Outputs
        .forwarding_out(w_forwarding_out),
        .status_backwards_out(w_status_backwards_out),
        .jump_address_backwards_out(w_jump_address_backwards_out)
    );

endmodule
