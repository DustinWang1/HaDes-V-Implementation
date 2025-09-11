/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: decode_stage.sv
 */



module decode_stage (
    input logic clk,
    input logic rst,

    // Inputs
    input logic [31:0]  instruction_in,
    input logic [31:0]  program_counter_in,
    input forwarding::t exe_forwarding_in,
    input forwarding::t mem_forwarding_in,
    input forwarding::t wb_forwarding_in,

    // Output Registers
    output logic [31:0]   rs1_data_reg_out,
    output logic [31:0]   rs2_data_reg_out,
    output logic [31:0]   program_counter_reg_out,
    output instruction::t instruction_reg_out,

    // Pipeline control
    input  pipeline_status::forwards_t  status_forwards_in,
    output pipeline_status::forwards_t  status_forwards_out,
    input  pipeline_status::backwards_t status_backwards_in,
    output pipeline_status::backwards_t status_backwards_out,
    input  logic [31:0] jump_address_backwards_in,
    output logic [31:0] jump_address_backwards_out
);

    assign jump_address_backwards_out = jump_address_backwards_in;

    // Hierarchical intermediate signals
    instruction::t d_instr;
    logic [31:0] rf_rd1;
    logic [31:0] rf_rd2;

    // Module Structure Connections
    instruction_decoder instruction_decoder(
        .instruction_in(instruction_in),
        .instruction_out(d_instr)
    );

    register_file register_file (
        .clk(clk),
        .rst(rst),
        // read ports
        .read_address1(d_instr.rs1_address),
        .read_data1(rf_rd1),
        .read_address2(d_instr.rs2_address),
        .read_data2(rf_rd2),
        // write port
        .write_address(wb_forwarding_in.address),
        .write_data(wb_forwarding_in.data),
        .write_enable(wb_forwarding_in.data_valid)
    );

    //------------------//
    // Forwarding Unit  //
    //------------------//

    // The forwarding unit catches data dependencies and generates appropriate control signals
    // also provides the proper forwarded data if available and required

    logic [31:0] fu_rd1, fu_rd2;
    logic data_hazard;

    // For readability 
    logic [4:0] rs1_adr, rs2_adr;
    assign rs1_adr = d_instr.rs1_address;
    assign rs2_adr = d_instr.rs2_address;

    // Forwarding match detection
    logic exe_match_rs1, exe_match_rs2;
    logic mem_match_rs1, mem_match_rs2;
    logic wb_match_rs1, wb_match_rs2;

    // More specific matching flags
    assign exe_match_rs1 = (rs1_adr == exe_forwarding_in.address) && (rs1_adr != 0);
    assign exe_match_rs2 = (rs2_adr == exe_forwarding_in.address) && (rs2_adr != 0);
    assign mem_match_rs1 = (rs1_adr == mem_forwarding_in.address) && (rs1_adr != 0);
    assign mem_match_rs2 = (rs2_adr == mem_forwarding_in.address) && (rs2_adr != 0);
    assign wb_match_rs1 = (rs1_adr == wb_forwarding_in.address) && (rs1_adr != 0);
    assign wb_match_rs2 = (rs2_adr == wb_forwarding_in.address) && (rs2_adr != 0);

    // Control signal for output
    logic forward_rs1;
    logic forward_rs2;

    // Default values (from register file)
    always_comb begin
        // Default values 
        fu_rd1 = 32'b0;
        fu_rd2 = 32'b0;
        data_hazard = 1'b0;
        forward_rs1 = 1'b0;
        forward_rs2 = 1'b0;
        
        // EXE stage forwarding (highest priority)
        if (exe_match_rs1) begin
            if (exe_forwarding_in.data_valid) begin
                fu_rd1 = exe_forwarding_in.data;
                forward_rs1 = 1'b1;
            end else
                data_hazard = 1'b1;
        end else if (mem_match_rs1) begin
            if (mem_forwarding_in.data_valid) begin
                fu_rd1 = mem_forwarding_in.data;
                forward_rs1 = 1'b1;
            end else
                data_hazard = 1'b1;
        end else if (wb_match_rs1) begin
            if (wb_forwarding_in.data_valid) begin
                fu_rd1 = wb_forwarding_in.data;
                forward_rs1 = 1'b1;
            end else
                data_hazard = 1'b1;
        end
        
        if (exe_match_rs2) begin
            if (exe_forwarding_in.data_valid) begin
                fu_rd2 = exe_forwarding_in.data;
                forward_rs2 = 1'b1;
            end else
                data_hazard = 1'b1;
        end else if (mem_match_rs2) begin
            if (mem_forwarding_in.data_valid) begin
                fu_rd2 = mem_forwarding_in.data;
                forward_rs2 = 1'b1;
            end else
                data_hazard = 1'b1;
        end else if (wb_match_rs2) begin
            if (wb_forwarding_in.data_valid) begin
                fu_rd2 = wb_forwarding_in.data;
                forward_rs2 = 1'b1;
            end else
                data_hazard = 1'b1;
        end
    end

    // Output Logic
    logic should_issue;
    logic illegal_instr;
    logic ebreak;
    logic ecall;
    assign illegal_instr = d_instr.op == op::ILLEGAL;
    assign ebreak = d_instr.op == op::EBREAK;
    assign ecall = d_instr.op == op::ECALL;
    assign should_issue = (status_forwards_in == pipeline_status::VALID) && (status_backwards_out == pipeline_status::READY);

    always_ff @(posedge clk) begin
        if(rst) begin
            status_forwards_out <= pipeline_status::BUBBLE;
        end else begin
            if(status_backwards_in == pipeline_status::JUMP || data_hazard) 
                status_forwards_out <= pipeline_status::BUBBLE;
            else if(should_issue) begin
                instruction_reg_out <= d_instr;
                program_counter_reg_out <= program_counter_in;
                rs1_data_reg_out <= forward_rs1 ? fu_rd1 : rf_rd1;
                rs2_data_reg_out <= forward_rs2 ? fu_rd2 : rf_rd2;

                unique if(illegal_instr) begin
                    status_forwards_out <= pipeline_status::ILLEGAL_INSTRUCTION;
                end else if(ebreak) begin
                    status_forwards_out <= pipeline_status::EBREAK;
                end else if(ecall) begin
                    status_forwards_out <= pipeline_status::ECALL;
                end else begin 
                    status_forwards_out <= pipeline_status::VALID;
                end
            end else if(status_forwards_in == pipeline_status::FETCH_FAULT) 
                status_forwards_out <= pipeline_status::FETCH_FAULT;
        end
    end

    // Status Backwards Logic
    always_comb begin
        if(status_backwards_in == pipeline_status::JUMP) 
            status_backwards_out = pipeline_status::JUMP;
        else if(status_backwards_in == pipeline_status::STALL || data_hazard)
            status_backwards_out = pipeline_status::STALL;
        else // We're good to go
            status_backwards_out = pipeline_status::READY;
    end
endmodule
