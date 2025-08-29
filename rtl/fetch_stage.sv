/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: fetch_stage.sv
 */



module fetch_stage (
    input logic clk,
    input logic rst,

    // Memory interface
    wishbone_interface.master wb,

    //  Output data
    output logic [31:0] instruction_reg_out,
    output logic [31:0] program_counter_reg_out,

    // Pipeline control
    output pipeline_status::forwards_t  status_forwards_out,
    input  pipeline_status::backwards_t status_backwards_in,
    input  logic [31:0] jump_address_backwards_in
);
   /*
    Inputs:
    - clk: Clock signal
    - rst: Reset signal
    - wb: Wishbone master interface for memory access
    - status_backwards_in: Pipeline control signal from the next stage
    - jump_address_backwards_in: Address to jump to if a branch is taken

    Outputs: 
    - instruction_reg_out: Fetched instruction
    - program_counter_reg_out: Current program counter value
    - status_forwards_out: Pipeline control signal to the next stage

    Internal Signals:
    - fault_pend: Indicates if a memory fault is pending
    - req_pend: Indicates if a memory request is pending
    - buf_valid: Indicates if the instruction buffer is valid
    - buf_instr: Holds the buffered instruction
    - buf_pc: Holds the buffered program counter

    Intent Flags:
    - flush: (status_backwards_in == JUMP)
    - ready_i: (status_backwards_in == READY)
    - present_valid: buf_valid && !flush && !fault_pending
    - fire: present_valid && ready_i
    - complete: wb.ack || wb.err
    - fault_set: wb.err
    - fault_clear: fault_pend && ready_i
    - issue_req: !req_pend && !buf_valid && !flush && !fault_pend
    - refill: wb.ack
    - cancel: flush
   */ 

    // Internal signals
    logic fault_pend;
    logic req_pend;
    logic buf_valid;
    logic [31:0] buf_instr;
    logic [31:0] buf_pc;

    // Intent Flags
    logic flush;
    logic ready_i;
    logic present_valid;
    logic fire;
    logic complete;
    logic fault_set;
    logic fault_clear;
    logic issue_req;
    logic refill;
    logic cancel;

    assign instruction_reg_out       = buf_instr;
    assign program_counter_reg_out   = buf_pc;

    // Wishbone interface assignments
    assign wb.cyc      = issue_req ? 1'b1 : 1'b0;
    assign wb.stb      = issue_req ? 1'b1 : 1'b0;
    assign wb.we       = 1'b0; // Always read in fetch stage
    assign wb.adr      = issue_req ? (buf_pc >> 2) : 32'b0;
    assign wb.sel      = issue_req ? 4'b1111 : 4'b0000;
    assign wb.dat_mosi = 32'b0; // Not used for read
    
    // Intent flags
    always_comb begin
        flush          = (status_backwards_in == pipeline_status::JUMP);
        ready_i        = (status_backwards_in == pipeline_status::READY);
        present_valid  = buf_valid && !flush && !fault_pend;
        fire           = present_valid && ready_i;
        complete       = wb.ack || wb.err;
        fault_set      = wb.err;
        fault_clear    = fault_pend && ready_i;
        issue_req      = !req_pend && !buf_valid && !flush && !fault_pend;
        refill         = wb.ack;
        cancel         = flush;
    end

    // Next State Logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fault_pend <= 1'b0;
            req_pend   <= 1'b0;
            buf_valid  <= 1'b0;
            buf_instr  <= 32'b0;
            buf_pc     <= constants::RESET_ADDRESS;
        end else begin
            // Fault pending logic
            if (fault_set) begin
                fault_pend <= 1'b1;
            end else if (fault_clear) begin
                fault_pend <= 1'b0;
            end
            // Flush Logic
            if (cancel) begin
                req_pend  <= 1'b0;
                buf_valid <= 1'b0;
                buf_pc    <= jump_address_backwards_in;
            end else begin
                // Request pending logic
                if (issue_req) begin
                    req_pend <= 1'b1;
                end else if (complete) begin
                    req_pend <= 1'b0;
                end
                // Buffer valid logic
                if (refill) begin
                    // refill only occurs if buf_valid is not set
                    buf_valid <= 1'b1;
                    buf_instr <= wb.dat_r;
                end else if (fire) begin
                    // refill and fire cannot occur in the same cycle because of buf_valid check
                    buf_valid <= 1'b0;
                    buf_pc    <= buf_pc + 32'd4;
                end
            end
        end
    end

    //Output Logic
    always_comb begin
        if (fault_pend)
            status_forwards_out = pipeline_status::FETCH_FAULT;
        else if (cancel)
            status_forwards_out = pipeline_status::BUBBLE;
        else if (present_valid)
            status_forwards_out = pipeline_status::VALID;
    end
   

endmodule
