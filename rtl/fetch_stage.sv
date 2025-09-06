/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: fetch_stage.sv
 */

module fetch_stage (
    input  logic clk,
    input  logic rst,

    // Wishbone (word-addressed master)
    wishbone_interface.master wb,

    // Outputs to the next stage
    output logic [31:0] instruction_reg_out,
    output logic [31:0] program_counter_reg_out,
    output pipeline_status::forwards_t status_forwards_out,

    // Backwards control from next stage
    input  pipeline_status::backwards_t status_backwards_in,
    input  logic [31:0]                 jump_address_backwards_in
);

    // ------------------------------------------------------------
    // Prefetch buffer (2 entries): {pc, instr, fault, valid}
    // ------------------------------------------------------------
    logic [31:0] fifo_pc0,    fifo_pc1;
    logic [31:0] fifo_instr0, fifo_instr1;
    logic        v0, v1;       // valid flags
    logic        f0, f1;       // fault flags (set on wb.err)

    logic fifo_empty, fifo_one, fifo_full;
    assign fifo_empty = (v0 == 1'b0);
    assign fifo_one   = (v0 == 1'b1) && (v1 == 1'b0);
    assign fifo_full  = (v0 == 1'b1) && (v1 == 1'b1);

    // Program counter for next request (byte address)
    logic [31:0] next_pc;

    // Wishbone control
    logic wb_cyc_r, wb_stb_r;
    logic req_pend;  // exactly one request outstanding when 1

    // Constant wishbone fields for fetch (read-only, full word)
    assign wb.we       = 1'b0;
    assign wb.sel      = 4'b1111;
    assign wb.dat_mosi = 32'h0000_0000;
    // Word-addressed bus: adr is next_pc[31:2]
    assign wb.adr      = next_pc >> 2;

    // Drive interface
    assign wb.cyc = wb_cyc_r;
    assign wb.stb = wb_stb_r;

    // ------------------------------------------------------------
    // Helper combinational intent for this cycle
    // ------------------------------------------------------------
    logic issue_now;     // we present a word to the next stage this cycle
    logic can_accept;    // prefetch buffer has/will have space to accept a WB response this cycle

    assign issue_now = (status_backwards_in == pipeline_status::READY) && v0;

    // If we issue_now, a full FIFO will free one slot
    assign can_accept = (!fifo_full) || issue_now;

    // ------------------------------------------------------------
    // Main sequential logic
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        // -----------------------------
        // Synchronous reset
        // -----------------------------
        if (rst) begin
            // FIFO clear
            v0 <= 1'b0;  v1 <= 1'b0;
            f0 <= 1'b0;  f1 <= 1'b0;
            fifo_pc0    <= 32'h0;
            fifo_pc1    <= 32'h0;
            fifo_instr0 <= 32'h0;
            fifo_instr1 <= 32'h0;

            // Outputs reset
            instruction_reg_out     <= 32'h0;
            program_counter_reg_out <= 32'h0;
            status_forwards_out     <= pipeline_status::BUBBLE;

            // WB/PC
            next_pc  <= constants::RESET_ADDRESS; // assumes you have constants::RESET_ADDRESS
            req_pend <= 1'b0;
            wb_cyc_r <= 1'b0;
            wb_stb_r <= 1'b0;

        end else begin

            // --------------------------------------------------------
            // Handle JUMP (flush + restart). Takes priority.
            // --------------------------------------------------------
            if (status_backwards_in == pipeline_status::JUMP) begin
                // Flush FIFO
                v0 <= 1'b0;  v1 <= 1'b0;
                f0 <= 1'b0;  f1 <= 1'b0;

                // Restart at jump PC
                next_pc  <= jump_address_backwards_in;
                req_pend <= 1'b0;

                // Drop the bus for one beat to avoid handling a stale response
                wb_cyc_r <= 1'b0;
                wb_stb_r <= 1'b0;

                // Downstream sees a bubble on the jump beat
                status_forwards_out <= pipeline_status::BUBBLE;
                // Hold instruction_reg_out/program_counter_reg_out stable

            end else begin
                // ----------------------------------------------------
                // Normal operation (STALLED or RUNNING)
                // ----------------------------------------------------

                // 1) Present head to next stage only if READY & v0
                if (issue_now) begin
                    // Drive outputs for this cycle
                    instruction_reg_out     <= f0 ? 32'h0000_0000 : fifo_instr0;
                    program_counter_reg_out <= fifo_pc0;
                    status_forwards_out     <= f0 ? pipeline_status::FETCH_FAULT
                                                  : pipeline_status::VALID;

                    // Pop the head:
                    if (fifo_one) begin
                        v0 <= 1'b0;
                        f0 <= 1'b0;
                        // (slot0 data don't matter when v0==0)
                    end else if (fifo_full) begin
                        // shift tail -> head
                        fifo_pc0    <= fifo_pc1;
                        fifo_instr0 <= fifo_instr1;
                        f0          <= f1;
                        v0          <= 1'b1;
                        // tail becomes empty
                        v1 <= 1'b0;
                        f1 <= 1'b0;
                    end
                    // If FIFO was empty we wouldn't be in issue_now.

                end else begin
                    // HOLD outputs on STALL or when empty
                    // (Do not touch instruction_reg_out / program_counter_reg_out)
                    // Only status updates if we want to explicitly show a bubble on READY-with-empty:
                    if (status_backwards_in == pipeline_status::READY && fifo_empty) begin
                        status_forwards_out <= pipeline_status::BUBBLE;
                    end
                    // On STALL, hold prior status as requested.
                end

                // ----------------------------------------------------
                // 2) Handle Wishbone responses (ACK/ERR) — only when cyc=1
                //     Place returned word/fault into FIFO considering a same-cycle pop.
                // ----------------------------------------------------
                if (wb_cyc_r && wb.ack) begin
                    if (fifo_empty) begin
                        // Write into head
                        fifo_pc0    <= next_pc;
                        fifo_instr0 <= wb.dat_miso;
                        f0          <= 1'b0;
                        v0          <= 1'b1;

                    end else if (issue_now) begin
                        // A pop happens this cycle
                        if (fifo_full) begin
                            // After pop, tail is free -> put into tail
                            fifo_pc1    <= next_pc;
                            fifo_instr1 <= wb.dat_miso;
                            f1          <= 1'b0;
                            v1          <= 1'b1;
                        end else begin
                            // After pop, head is free -> put into head
                            fifo_pc0    <= next_pc;
                            fifo_instr0 <= wb.dat_miso;
                            f0          <= 1'b0;
                            v0          <= 1'b1;
                        end

                    end else begin
                        // Not popping: put into tail
                        fifo_pc1    <= next_pc;
                        fifo_instr1 <= wb.dat_miso;
                        f1          <= 1'b0;
                        v1          <= 1'b1;
                    end

                    // Advance PC for the *next* fetch
                    next_pc <= next_pc + 32'd4;

                    // Launch another request immediately if we have space
                    if (can_accept) begin
                        wb_stb_r <= 1'b1;
                        req_pend <= 1'b1;
                        wb_cyc_r <= 1'b1;
                    end else begin
                        wb_stb_r <= 1'b0;
                        req_pend <= 1'b0;
                        wb_cyc_r <= 1'b1; // keep the cycle open; no harm to leave CYC high
                    end

                end else if (wb_cyc_r && wb.err) begin
                    // Error = fault entry
                    if (fifo_empty) begin
                        fifo_pc0 <= next_pc; f0 <= 1'b1; v0 <= 1'b1;
                    end else if (issue_now) begin
                        if (fifo_full) begin
                            fifo_pc1 <= next_pc; f1 <= 1'b1; v1 <= 1'b1;
                        end else begin
                            fifo_pc0 <= next_pc; f0 <= 1'b1; v0 <= 1'b1;
                        end
                    end else begin
                        fifo_pc1 <= next_pc; f1 <= 1'b1; v1 <= 1'b1;
                    end

                    next_pc <= next_pc + 32'd4;

                    if (can_accept) begin
                        wb_stb_r <= 1'b1; req_pend <= 1'b1; wb_cyc_r <= 1'b1;
                    end else begin
                        wb_stb_r <= 1'b0; req_pend <= 1'b0; wb_cyc_r <= 1'b1;
                    end

                end else begin
                    // No response this cycle
                    // If no request outstanding and we can accept, start one
                    if (!req_pend && can_accept) begin
                        wb_stb_r <= 1'b1;
                        req_pend <= 1'b1;
                        wb_cyc_r <= 1'b1;
                    end else begin
                        // Keep STB asserted while a request is outstanding; otherwise drop it.
                        wb_stb_r <= req_pend ? 1'b1 : 1'b0;
                        // Keep CYC high during normal run
                        wb_cyc_r <= 1'b1;
                    end
                end
            end // !JUMP
        end // !rst
    end // always_ff

endmodule




