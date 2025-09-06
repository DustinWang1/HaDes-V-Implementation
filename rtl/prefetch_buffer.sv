/* parameterized prefetch buffer implemented as a shift-register FIFO
 * module name matches filename to satisfy many lint tools and simulators
 */

module prefetch_buffer #(
    parameter int DEPTH = 2
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             push,       // push new entry into tail
    input  logic             pop,        // pop oldest entry from head
    input  logic [31:0]      instr_in,
    input  logic [31:0]      pc_in,
    output logic [31:0]      instr_out,  // oldest entry
    output logic [31:0]      pc_out,     // oldest entry PC
    output logic             can_push,   // true if buffer can accept another push
    output logic             empty,      // true if buffer is empty
    output logic [$clog2(DEPTH+1)-1:0] count // number of stored entries
);

    // storage arrays: index 0 = head (oldest), index DEPTH-1 = tail (newest)
    logic [31:0] buf_instr [0:DEPTH-1];
    logic [31:0] buf_pc    [0:DEPTH-1];
    // internal counter (wider int) used for arithmetic
    int unsigned cnt_int;

    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < DEPTH; i++) begin
                buf_instr[i] = 32'b0;
                buf_pc[i]    = 32'b0;
            end
            cnt_int <= 0;
        end else begin
            // compute next counter once and apply at end
            int unsigned next_cnt = cnt_int;

            // Handle push/pop combinations using blocking assigns for arrays
            if (push && !pop) begin
                // if empty, put new entry at head so it's immediately visible on instr_out
                if (cnt_int == 0) begin
                    buf_instr[0] = instr_in;
                    buf_pc[0]    = pc_in;
                    // clear any other entries
                    for (i = 1; i < DEPTH; i++) begin
                        buf_instr[i] = 32'b0;
                        buf_pc[i]    = 32'b0;
                    end
                    next_cnt = 1;
                end else if (cnt_int < DEPTH) begin
                    // append at tail (index = cnt_int)
                    buf_instr[cnt_int] = instr_in;
                    buf_pc[cnt_int]    = pc_in;
                    next_cnt = cnt_int + 1;
                end
            end else if (!push && pop) begin
                if (cnt_int > 0) begin
                    // remove head and shift left
                    for (i = 0; i < DEPTH-1; i++) begin
                        buf_instr[i] = buf_instr[i+1];
                        buf_pc[i]    = buf_pc[i+1];
                    end
                    buf_instr[DEPTH-1] = 32'b0;
                    buf_pc[DEPTH-1]    = 32'b0;
                    next_cnt = cnt_int - 1;
                end
            end else if (push && pop) begin
                // perform pop then push in same clock: preserve count when possible
                if (cnt_int == 0) begin
                    // empty: push becomes single element
                    buf_instr[0] = instr_in;
                    buf_pc[0]    = pc_in;
                    for (i = 1; i < DEPTH; i++) begin
                        buf_instr[i] = 32'b0;
                        buf_pc[i]    = 32'b0;
                    end
                    next_cnt = 1;
                end else begin
                    // pop: shift left by one (reduce count by 1)
                    for (i = 0; i < cnt_int-1; i++) begin
                        buf_instr[i] = buf_instr[i+1];
                        buf_pc[i]    = buf_pc[i+1];
                    end
                    // clear the previous tail position
                    buf_instr[cnt_int-1] = 32'b0;
                    buf_pc[cnt_int-1]    = 32'b0;
                    next_cnt = cnt_int - 1;
                    // now push: append at new tail if space
                    if (next_cnt < DEPTH) begin
                        buf_instr[next_cnt] = instr_in;
                        buf_pc[next_cnt]    = pc_in;
                        next_cnt = next_cnt + 1;
                    end
                end
            end

            // apply updated counter
            cnt_int <= next_cnt;
        end
    end

    // outputs reflect head (oldest)
    assign instr_out = buf_instr[0];
    assign pc_out    = buf_pc[0];

    // status signals
    // expose the lower bits of the internal counter
    assign count    = cnt_int[$clog2(DEPTH+1)-1:0];
    assign can_push = (cnt_int < DEPTH);
    assign empty    = (cnt_int == 0);

endmodule
