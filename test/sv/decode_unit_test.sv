module decode_unit_test;
    import clk_params::*;
    import forwarding::*;

    /*verilator lint_off UNUSED*/
    logic clk, clk_vga;
    logic rst;
    /*verilator lint_on UNUSED*/

    // System clock
    initial begin
        clk = 1;
        forever begin
            #(int'(SIM_CYCLES_PER_SYS_CLK / 2));
            clk = ~clk;
        end
    end

    // VGA pixel clock
    initial begin
        clk_vga = 1;
        forever begin
            #(int'(SIM_CYCLES_PER_VGA_CLK / 2));
            clk_vga = ~clk_vga;
        end
    end

    // --------------------------------------------------------------------------------------------
    // test bench variables
    int error_count = 0;

    // --------------------------------------------------------------------------------------------
    // device under test
    logic [31:0] instruction_in;
    logic [31:0] program_counter_in;
    forwarding::t exe_forwarding_in;
    forwarding::t mem_forwarding_in;
    forwarding::t wb_forwarding_in;

    logic [31:0] rs1_data_reg_out;
    logic [31:0] rs2_data_reg_out;
    logic [31:0] program_counter_reg_out;
    instruction::t instruction_reg_out;

    pipeline_status::forwards_t status_forwards_in;
    pipeline_status::forwards_t status_forwards_out;
    pipeline_status::backwards_t status_backwards_in;
    pipeline_status::backwards_t status_backwards_out;
    logic [31:0] jump_address_backwards_in;
    logic [31:0] jump_address_backwards_out;

    decode_stage dut (
        .clk(clk),
        .rst(rst),

        .instruction_in(instruction_in),
        .program_counter_in(program_counter_in),
        .exe_forwarding_in(exe_forwarding_in),
        .mem_forwarding_in(mem_forwarding_in),
        .wb_forwarding_in(wb_forwarding_in),

        .rs1_data_reg_out(rs1_data_reg_out),
        .rs2_data_reg_out(rs2_data_reg_out),
        .program_counter_reg_out(program_counter_reg_out),
        .instruction_reg_out(instruction_reg_out),

        .status_forwards_in(status_forwards_in),
        .status_forwards_out(status_forwards_out),
        .status_backwards_in(status_backwards_in),
        .status_backwards_out(status_backwards_out),
        .jump_address_backwards_in(jump_address_backwards_in),
        .jump_address_backwards_out(jump_address_backwards_out)
    );

    initial begin
        $dumpfile("decode_unit_test.fst");
        $dumpvars;

        perform_rst();

        test_forwarding_priority();
        test_load_use_hazard_stall();
        test_ignore_x0();
        test_invalid_instruction();
        // test_write_read_only_csr();
        // test_csr_address_dne();
        // test_instruction_formats();

        print_test_done();
    end

    function void test_load_use_hazard_stall();
        perform_rst();

        @(posedge clk);
        ready_pipeline_status();
        instruction_in = 32'h00550313;
        exe_forwarding_in.data_valid = 1'b0;
        exe_forwarding_in.data = 32'hcafebabe;
        exe_forwarding_in.address = 5'd10;

        @(posedge clk);
        assert(status_backwards_out == pipeline_status::STALL) else begin
            // Print the enum name through a case statement
            string status_name;
            case(status_backwards_out)
                pipeline_status::STALL: status_name = "STALL";
                pipeline_status::READY: status_name = "READY";
                pipeline_status::JUMP: status_name = "JUMP";
            endcase
            
            $display("[Load Use Hazard Stall Test] (%6d ns) status_backwards_out = %s, expected STALL", $time(), status_name);
            error_count++;
        end;
    endfunction

    function void test_forwarding_priority(); 
        perform_rst();

        // set instruction input to addi x6, x10, 5
        @(posedge clk);
        ready_pipeline_status();
        instruction_in = 32'h00550313;
        exe_forwarding_in.data_valid = 1'b1;
        exe_forwarding_in.data = 32'hcafebab1;
        exe_forwarding_in.address = 5'd10;

        mem_forwarding_in.data_valid = 1'b1;
        mem_forwarding_in.data = 32'hcafebab2;
        mem_forwarding_in.address = 5'd10;

        wb_forwarding_in.data_valid = 1'b1;
        wb_forwarding_in.data = 32'hcafebab3;
        wb_forwarding_in.address = 5'd10;
        
        @(posedge clk);
        assert(rs1_data_reg_out == exe_forwarding_in.data) else begin 
            $display("[Forwarding Priority Test] (%6d ns) rs1_data_reg_out = 0x%x, expected 0xcafebab1", $time(), rs1_data_reg_out); 
            error_count++; 
        end;
    endfunction

    function void test_ignore_x0();
        perform_rst();
        // Data dependency on x0. It should read zero from the register file not the forwarding unit
        @(posedge clk);
        ready_pipeline_status();
        instruction_in = 32'h00100313; // addi x0, x6, 1
        exe_forwarding_in.data_valid = 1'b1;
        exe_forwarding_in.data = 32'hcafebabe;
        exe_forwarding_in.address = 5'd0;

        @(posedge clk);
        assert(rs1_data_reg_out == 32'b0) else begin
            $display("[ignore forward x0 test] (%6d ns) rs1_data_reg_out = 0x%x, expected 0x0", $time(), rs1_data_reg_out);
            error_count++;
        end;
    endfunction

    function void test_invalid_instruction();
        perform_rst();

        @(posedge clk);
        ready_pipeline_status();
        instruction_in = 32'h00000000;

        @(posedge clk);
        assert(status_forwards_out == pipeline_status::ILLEGAL_INSTRUCTION) else begin
            // Print the enum name through a case statement
            string status_name;
            case(status_forwards_out)
                pipeline_status::BUBBLE: status_name = "BUBBLE";
                pipeline_status::VALID: status_name = "VALID";
                pipeline_status::EBREAK: status_name = "EBREAK";
                pipeline_status::ECALL: status_name = "ECALL";
                pipeline_status::ILLEGAL_INSTRUCTION: status_name = "ILLEGAL_INSTRUCTION";
            endcase
            
            $display("[invalid instruction test] (%6d ns) status_forwards_out = %s, expected ILLEGAL INSTRUCTION", $time(), status_name);
            error_count++;
        end;
    endfunction

    function void ready_pipeline_status();
        status_forwards_in = pipeline_status::VALID;
        status_backwards_in = pipeline_status::READY;
    endfunction

    function void reset_module_inputs();
        automatic forwarding::t empty;
        instruction_in = 32'b0;
        program_counter_in = 32'b0;

        empty.data_valid = 1'b0;
        empty.data = 32'b0;
        empty.address = 5'b0;

        exe_forwarding_in = empty;
        mem_forwarding_in = empty;
        wb_forwarding_in = empty;

        status_forwards_in = pipeline_status::BUBBLE;
        status_backwards_in = pipeline_status::STALL;
    endfunction

    function void perform_rst();
        @(negedge clk); #1;
        rst = 1;
        // reset module inputs
        reset_module_inputs();
        // clear reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
    endfunction

    function void print_test_done();
        if (error_count != 0) begin
            $display("\033[0;31m"); // color_red
            $display("Some test(s) failed! (# Errors: %4d)", error_count);
        end
        else begin
            $display("\033[0;32m"); // color green
            $display("All tests passed! (# Errors: %4d)", error_count);
        end
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("!!!!!!!!!!!!!!!!!!!! TEST DONE !!!!!!!!!!!!!!!!!!!!");
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("\033[0m"); // color off
    endfunction
endmodule