/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: memory_stage.sv
 */


module memory_stage (
    input logic clk,
    input logic rst,

    // Memory interface
    wishbone_interface.master wb,

    // Inputs
    input logic [31:0]   source_data_in,
    input logic [31:0]   rd_data_in,
    input instruction::t instruction_in,
    input logic [31:0]   program_counter_in,
    input logic [31:0]   next_program_counter_in,

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

    // TODO: Delete the following line and implement this module.
    // ref_memory_stage golden(.*);

    // ============================
    // Internal Signals
    // ============================
    // Instruction identification
    logic should_handle_instr;
    logic is_store_instr;
    logic is_load_instr;

    // Wishbone parameters
    logic [3:0] wb_sel;
    logic [31:0] aligned_store_data;
    logic wb_we;
    
    // Error Flags
    logic load_misaligned;
    logic store_misaligned;

    //Output
    logic [31:0] formatted_miso;

    // ============================
    // Instruction identification
    // ============================
    assign should_handle_instr = instruction_in.op inside {op::LW, op::LH, op::LB, op::LHU, op::LBU, op::SB, op::SH, op::SW} && status_forwards_in == pipeline_status::VALID;
    assign is_load_instr = instruction_in.op inside {op::LW, op::LH, op::LB, op::LHU, op::LBU};
    assign is_store_instr = instruction_in.op inside {op::SB, op::SH, op::SW};
    assign wb_we = is_store_instr;     
    // ============================
    // Byte Selection
    // ============================
    always_comb begin
        wb_sel = 4'b0000;
        case(instruction_in.op) 
            op::LW, op::SW: begin
                wb_sel = 4'b1111;
            end
            op::LH, op::LHU, op::SH: begin
                if(rd_data_in[1] == 1'b0) begin
                    wb_sel = 4'b0011;
                end else begin
                    wb_sel = 4'b1100;
                end
            end
            op::LB, op::LBU, op::SB: begin
                case(rd_data_in[1:0])
                    2'b00: wb_sel = 4'b0001;  // Byte 0
                    2'b01: wb_sel = 4'b0010;  // Byte 1
                    2'b10: wb_sel = 4'b0100;  // Byte 2
                    2'b11: wb_sel = 4'b1000;  // Byte 3
                endcase
            end
            default: wb_sel = 4'b0000;
        endcase
    end

    // ============================
    // Store Data Alignment
    // ============================
    always_comb begin
        case(instruction_in.op)
            op::SW: begin
                aligned_store_data = source_data_in;  // Full word, no alignment needed
            end
            op::SH: begin
                // Replicate halfword to both positions
                if(rd_data_in[1] == 1'b0)
                    aligned_store_data = {16'b0, source_data_in[15:0]};
                else
                    aligned_store_data = {source_data_in[15:0], 16'b0};
            end
            op::SB: begin
                // Replicate byte to all 4 positions
                case(rd_data_in[1:0])
                    2'b00: aligned_store_data = {24'b0, source_data_in[7:0]};
                    2'b01: aligned_store_data = {16'b0, source_data_in[7:0], 8'b0};
                    2'b10: aligned_store_data = {8'b0, source_data_in[7:0], 16'b0};
                    2'b11: aligned_store_data = {source_data_in[7:0], 24'b0};
                endcase
            end
            default: aligned_store_data = source_data_in;
        endcase
    end

    // ============================
    // WB assignment
    // ============================
    assign wb.cyc  = should_handle_instr && !load_misaligned && !store_misaligned && status_backwards_in != pipeline_status::JUMP;
    assign wb.stb = should_handle_instr && !load_misaligned && !store_misaligned && status_backwards_in != pipeline_status::JUMP;

    assign wb.sel = wb_sel;
    assign wb.adr = rd_data_in >> 2;
    assign wb.dat_mosi = aligned_store_data;
    assign wb.we = wb_we;

    // =========================
    // misalignment checker
    // =========================
    always_comb begin
        load_misaligned = 1'b0;
        store_misaligned = 1'b0;
        
        case(instruction_in.op)
            op::LH, op::LHU: begin
                // Halfword must be 2-byte aligned (address[0] must be 0)
                if(rd_data_in[0] != 1'b0)
                    load_misaligned = 1'b1;
            end
            op::LW: begin
                // Word must be 4-byte aligned (address[1:0] must be 00)
                if(rd_data_in[1:0] != 2'b00)
                    load_misaligned = 1'b1;
            end
            op::SH: begin
                if(rd_data_in[0] != 1'b0)
                    store_misaligned = 1'b1;
            end
            op::SW: begin
                if(rd_data_in[1:0] != 2'b00)
                    store_misaligned = 1'b1;
            end
            default: begin
                store_misaligned = 1'b0;
                load_misaligned = 1'b0;
            end
        endcase
    end

    // ========================
    // Format dat_miso
    // ========================
    always_comb begin
        formatted_miso = 32'b0;
        if(wb.ack && is_load_instr) begin
            case(instruction_in.op)
                op::LW: formatted_miso = wb.dat_miso;
                op::LH: begin
                    if(rd_data_in[1] == 1'b0)
                        formatted_miso = {{16{wb.dat_miso[15]}}, wb.dat_miso[15:0]};
                    else
                        formatted_miso = {{16{wb.dat_miso[31]}}, wb.dat_miso[31:16]};
                end
                op::LB: begin
                    case(rd_data_in[1:0])
                        2'b00: formatted_miso = {{24{wb.dat_miso[7]}}, wb.dat_miso[7:0]};
                        2'b01: formatted_miso = {{24{wb.dat_miso[15]}}, wb.dat_miso[15:8]};
                        2'b10: formatted_miso = {{24{wb.dat_miso[23]}}, wb.dat_miso[23:16]};
                        2'b11: formatted_miso = {{24{wb.dat_miso[31]}}, wb.dat_miso[31:24]};
                    endcase
                end
                op::LHU: begin
                    if(rd_data_in[1] == 1'b0)
                        formatted_miso = {16'b0, wb.dat_miso[15:0]};
                    else
                        formatted_miso = {16'b0, wb.dat_miso[31:16]};
                end
                op::LBU: begin
                    case(rd_data_in[1:0])
                        2'b00: formatted_miso = {24'b0, wb.dat_miso[7:0]};
                        2'b01: formatted_miso = {24'b0, wb.dat_miso[15:8]};
                        2'b10: formatted_miso = {24'b0, wb.dat_miso[23:16]};
                        2'b11: formatted_miso = {24'b0, wb.dat_miso[31:24]};
                    endcase
                end
                default: formatted_miso = 32'b0; 
            endcase
        end
    end

    //==========================
    // Status Forwards
    //==========================
    always_ff @(posedge clk) begin
        if(rst) begin
            // 1. Reset - highest priority
            status_forwards_out <= pipeline_status::BUBBLE;
        end else if(status_backwards_in == pipeline_status::JUMP) begin
            // 2. Backward signals from later stages (JUMP flushes)
            status_forwards_out <= pipeline_status::BUBBLE;
        end else if(status_backwards_in == pipeline_status::STALL) begin
            // 2. Backward signals (STALL holds current state)
            // Don't change status_forwards_out
        end else if(load_misaligned && status_forwards_in == pipeline_status::VALID) begin
            // 3. Own errors - misalignment
            status_forwards_out <= pipeline_status::LOAD_MISALIGNED;
        end else if(store_misaligned && status_forwards_in == pipeline_status::VALID) begin
            // 3. Own errors - misalignment
            status_forwards_out <= pipeline_status::STORE_MISALIGNED;
        end else if(wb.err) begin
            // 3. Own errors - memory fault
            if(is_load_instr)
                status_forwards_out <= pipeline_status::LOAD_FAULT;
            else
                status_forwards_out <= pipeline_status::STORE_FAULT;
        end else if(status_forwards_in != pipeline_status::VALID) begin
            // 4. Errors from previous stages - pass through
            status_forwards_out <= status_forwards_in;
        end else if(wb.ack || !should_handle_instr) begin
            // 5. Valid output - either memory completed or pass-through
            status_forwards_out <= pipeline_status::VALID;
        end else begin
            // 6. Waiting on memory
            status_forwards_out <= pipeline_status::BUBBLE;
        end
    end

    // =========================
    // Status Backwards
    // =========================
    // Just assign jump address backwards 
    assign jump_address_backwards_out = jump_address_backwards_in;
    always_comb begin
        if(status_backwards_in == pipeline_status::JUMP) begin
            status_backwards_out = pipeline_status::JUMP;
        end else if(status_backwards_in == pipeline_status::STALL) begin
            status_backwards_out = pipeline_status::STALL;
        end else if(should_handle_instr && !wb.ack && !wb.err) begin
            status_backwards_out = pipeline_status::STALL;
        end else begin
            status_backwards_out = pipeline_status::READY;
        end
    end

    // =========================
    // Forwarding out
    // =========================
    always_comb begin
        forwarding_out.address = (status_forwards_in == pipeline_status::VALID) ? instruction_in.rd_address : 5'b0;
        forwarding_out.data_valid = 1'b0;
        forwarding_out.data = 32'b0;

        if(status_forwards_in == pipeline_status::VALID && instruction_in.rd_address != 5'b0) begin
            if(wb.ack && is_load_instr) begin
                forwarding_out.data = formatted_miso;  // The loaded data after extraction
                forwarding_out.data_valid = 1'b1;
            end else if(instruction_in.op inside {op::LUI, op::AUIPC, op::JAL, op::JALR, op::ADDI, op::SLTI, op::SLTIU, op::XORI, op::ORI, op::ANDI, op::SLLI, op::SRLI, op::SRAI, op::ADD, op::SUB, op::SLL, op::SLT, op::SLTU, op::XOR, op::SRL, op::SRA, op::OR, op::AND}) begin
                forwarding_out.data = rd_data_in;
                forwarding_out.data_valid = 1'b1;
            end
        end
    end

    // ========================
    // Program Counter
    // ========================
    always_ff @(posedge clk) begin
        if(rst) begin
            next_program_counter_reg_out <= 32'b0;
            program_counter_reg_out <= 32'b0;
        end else begin
            program_counter_reg_out <= program_counter_in;
            next_program_counter_reg_out <= next_program_counter_in;
        end
    end

    // =========================
    // Pipeline Registers
    // =========================
    always_ff @(posedge clk) begin
        if(rst) begin
            instruction_reg_out <= 'b0;
        end else if(status_forwards_in == pipeline_status::VALID && status_backwards_in == pipeline_status::READY) begin
            instruction_reg_out <= instruction_in;
            source_data_reg_out <= source_data_in;

            if(wb.ack && is_load_instr) begin
                rd_data_reg_out <= formatted_miso;
            end else begin
                rd_data_reg_out <= rd_data_in;
            end
        end
    end
endmodule
