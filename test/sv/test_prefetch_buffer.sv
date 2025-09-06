`timescale 1ns/1ps
module tb_prefetch;
    // clock/reset
    logic clk;
    logic rst;
    always #5 clk = ~clk; // 100MHz-ish

    // DUT signals
    logic push, pop;
    logic [31:0] instr_in, pc_in;
    logic [31:0] instr_out, pc_out;
    logic can_push, empty;
    logic [$clog2(4)-1:0] count; // we'll instantiate DEPTH=3 in this test

    // instantiate with DEPTH=3
    prefetch_buffer #(.DEPTH(3)) dut (
        .clk(clk), .rst(rst), .push(push), .pop(pop),
        .instr_in(instr_in), .pc_in(pc_in),
        .instr_out(instr_out), .pc_out(pc_out),
        .can_push(can_push), .empty(empty), .count(count)
    );

    initial begin
        // init
        clk = 0; rst = 1; push = 0; pop = 0; instr_in = 0; pc_in = 0;
        #20 rst = 0; // release reset

        // sanity: empty after reset
        #10;
        if (!empty) $fatal(1, "Buffer should be empty after reset");

        // push A
        instr_in = 32'hA; pc_in = 32'h100; push = 1; #10; push = 0; #10;
        if (empty) $fatal(1, "Buffer should not be empty after 1 push");
        if (count != 1) $fatal(1, "Count should be 1 after 1 push (got %0d)", count);
        if (instr_out != 32'hA) $fatal(1, "instr_out should be A (got %08x)", instr_out);

        // push B
        instr_in = 32'hB; pc_in = 32'h104; push = 1; #10; push = 0; #10;
        if (count != 2) $fatal(1, "Count should be 2 after 2 pushes (got %0d)", count);
        if (instr_out != 32'hA) $fatal(1, "instr_out should still be A (got %08x)", instr_out);

        // pop (consume A)
        pop = 1; #10; pop = 0; #10;
        if (count != 1) $fatal(1, "Count should be 1 after pop (got %0d)", count);
        if (instr_out != 32'hB) $fatal(1, "instr_out should now be B (got %08x)", instr_out);

        // push C, push D (overflow test: only 3 entries)
        instr_in = 32'hC; pc_in = 32'h108; push = 1; #10; push = 0; #10;
        instr_in = 32'hD; pc_in = 32'h10C; push = 1; #10; push = 0; #10;
        if (count != 3) $fatal(1, "Count should be 3 after pushes (got %0d)", count);
        if (!can_push) $fatal(1, "can_push should be false when full");

        // pop twice -> expect D to move
        pop = 1; #10; pop = 0; #10;
        pop = 1; #10; pop = 0; #10;
        if (count != 1) $fatal(1, "Count should be 1 after two pops (got %0d)", count);

        // simultaneous push+pop: push E while pop -> replace head, count unchanged
        instr_in = 32'hE; pc_in = 32'h110; push = 1; pop = 1; #10; push = 0; pop = 0; #10;
        if (count != 1) $fatal(1, "Count should remain 1 after simultaneous push+pop (got %0d)", count);

        // final check of instr_out equals E
        if (instr_out != 32'hE) $fatal(1, "instr_out should be E after simultaneous op (got %08x)", instr_out);

        $display("PREFETCH_BUFFER TEST PASSED");
        $finish;
    end
endmodule
