module csr_file (
    input  logic        clk,
    input  logic        rst,
    
    // Write enables
    input logic mstatus_en,
    input logic mtvec_en,
    // mip is read-only (no enable needed)
    input logic mie_en,
    input logic mcycle_en,
    input logic mcycleh_en,
    input logic minstret_en,
    input logic minstreth_en,
    input logic mscratch_en,
    input logic mepc_en,
    input logic mcause_en,
    
    // Write data inputs
    input logic[31:0] mstatus_in,
    input logic[31:0] mtvec_in,
    // mip has no write input (read-only)
    input logic[31:0] mie_in,
    input logic[31:0] mcycle_in,
    input logic[31:0] mcycleh_in,
    input logic[31:0] minstret_in,
    input logic[31:0] minstreth_in,
    input logic[31:0] mscratch_in,
    input logic[31:0] mepc_in,
    input logic[31:0] mcause_in,
    
    // External interrupt inputs for MIP
    input logic external_interrupt,
    input logic timer_interrupt,
    
    // Special inputs for counters
    input logic valid_instruction,  // For MINSTRET increment
    
    // Outputs
    output logic[31:0] mstatus_out,
    output logic[31:0] mtvec_out,
    output logic[31:0] mip_out,
    output logic[31:0] mie_out,
    output logic[31:0] mcycle_out,
    output logic[31:0] mcycleh_out,
    output logic[31:0] minstret_out,
    output logic[31:0] minstreth_out,
    output logic[31:0] mscratch_out,
    output logic[31:0] mepc_out,
    output logic[31:0] mcause_out
);

    // CSR storage registers
    logic        mstatus_mie, mstatus_mpie;
    logic [31:0] mtvec;
    logic        mie_meie, mie_mtie;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [63:0] mcycle;
    logic [63:0] minstret;
    
    // Sequential logic for CSR updates
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset values according to spec
            mstatus_mie  <= 1'b0;  // MIE must be cleared on reset
            mstatus_mpie <= 1'b0;
            mtvec        <= 32'b0;
            mie_meie     <= 1'b0;
            mie_mtie     <= 1'b0;
            mscratch     <= 32'b0;
            mepc         <= 32'b0;
            mcause       <= 32'b0;  // Cleared on reset per spec
            mcycle       <= 64'b0;
            minstret     <= 64'b0;
        end else begin
            // Default increments for counters
            mcycle <= mcycle + 1;
            if (valid_instruction) begin
                minstret <= minstret + 1;
            end
            
            // CSR writes (override increments if written)
            if (mstatus_en) begin
                mstatus_mie  <= mstatus_in[3];   // MIE is bit 3
                mstatus_mpie <= mstatus_in[7];   // MPIE is bit 7
                // All other bits read as 0
            end
            
            if (mtvec_en) begin
                mtvec <= {mtvec_in[31:2], 2'b00};  // Keep aligned (lower 2 bits = 0)
            end
            
            if (mie_en) begin
                mie_meie <= mie_in[11];  // MEIE is bit 11
                mie_mtie <= mie_in[7];   // MTIE is bit 7
            end
            
            if (mcycle_en) begin
                mcycle[31:0] <= mcycle_in;
            end
            
            if (mcycleh_en) begin
                mcycle[63:32] <= mcycleh_in;
            end
            
            if (minstret_en) begin
                minstret[31:0] <= minstret_in;
            end
            
            if (minstreth_en) begin
                minstret[63:32] <= minstreth_in;
            end
            
            if (mscratch_en) begin
                mscratch <= mscratch_in;
            end
            
            if (mepc_en) begin
                mepc <= {mepc_in[31:2], 2'b00};  // Keep aligned (lower 2 bits = 0)
            end
            
            if (mcause_en) begin
                mcause <= mcause_in;
            end
        end
    end
    
    // Combinational outputs
    always_comb begin
        // MSTATUS: only MPIE (bit 7) and MIE (bit 3) are implemented
        mstatus_out = {24'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
        
        // MTVEC: aligned address
        mtvec_out = {mtvec[31:2], 2'b00};
        
        // MIP: read-only based on interrupt inputs
        // MEIP is bit 11, MTIP is bit 7
        mip_out = {20'b0, external_interrupt, 3'b0, timer_interrupt, 7'b0};
        
        // MIE: only MEIE (bit 11) and MTIE (bit 7) are implemented
        mie_out = {20'b0, mie_meie, 3'b0, mie_mtie, 7'b0};
        
        // Counter outputs
        mcycle_out = mcycle[31:0];
        mcycleh_out = mcycle[63:32];
        minstret_out = minstret[31:0];
        minstreth_out = minstret[63:32];
        
        // Other CSRs
        mscratch_out = mscratch;
        mepc_out = {mepc[31:2], 2'b00};
        mcause_out = mcause;
    end

endmodule
