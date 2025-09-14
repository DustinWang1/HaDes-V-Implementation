/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: register_file.sv
 */



module register_file (
    input logic clk,
    input logic rst,
    // read ports
    input  logic [4:0]  read_address1,
    output logic [31:0] read_data1,
    input  logic [4:0]  read_address2,
    output logic [31:0] read_data2,
    // write port
    input  logic [4:0]  write_address,
    input  logic [31:0] write_data,
    input  logic        write_enable
);
    logic [31:0] rf [32];
    assign read_data1 = rf[read_address1];
    assign read_data2 = rf[read_address2];

    always_ff @(posedge clk) begin
        if(rst) begin
            rf <= '{default:0};
        end
        else if(write_enable && write_address != 0) begin
            rf[write_address] <= write_data;
        end
    end 

endmodule
