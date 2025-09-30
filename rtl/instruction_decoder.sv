/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: instruction_decoder.sv
 */

/* verilator lint_off UNUSEDSIGNAL */
function automatic instruction::t decode_csr(logic [31:0] instr);
    automatic instruction::t result;
    // Set defaults for a CSR instruction
    result.op = op::ILLEGAL;
    result.rd_address = instr[11:7];
    result.rs1_address = instr[19:15];
    result.rs2_address = 5'b0;
    result.immediate = {27'b0, instr[19:15]}; // For CSRRI variants
    result.csr = csr::MSTATUS; // Default enum

    // Translate the 12-bit CSR address to the enum type
    // and check if it's one of the CSRs implemented in HADES-V
    case (instr[31:20])
        csr::MSTATUS, csr::MTVEC, csr::MIP, csr::MIE, csr::MCYCLE, csr::MCYCLEH,
        csr::MINSTRET, csr::MINSTRETH, csr::MSCRATCH, csr::MEPC, csr::MCAUSE:
            result.csr = csr::t'(instr[31:20]);
        default:
            return '{op: op::ILLEGAL, csr: csr::MSCRATCH, default: '0}; // Unimplemented CSR
    endcase

    // Decode the specific CSR operation
    case (instr[14:12]) // funct3
        3'b001: result.op = op::CSRRW;
        3'b010: result.op = op::CSRRS;
        3'b011: result.op = op::CSRRC;
        3'b101: result.op = op::CSRRWI;
        3'b110: result.op = op::CSRRSI;
        3'b111: result.op = op::CSRRCI;
        default: result.op = op::ILLEGAL;
    endcase
    return result;
endfunction
/* verilator lint_on UNUSEDSIGNAL */

module instruction_decoder (
    input  logic [31:0]   instruction_in,
    output instruction::t instruction_out
);
    instruction::t decoded_instr;
    assign instruction_out = decoded_instr;

    always_comb begin
        // Default assignment for any instruction that doesn't match a valid pattern
        decoded_instr = '{op: op::ILLEGAL, csr: csr::MSCRATCH, default: '0};

        casez (instruction_in)
            // U-Type
            {25'b?, 7'b0110111}: decoded_instr = '{op: op::LUI,   rd_address: instruction_in[11:7], csr: csr::MSCRATCH, immediate: {instruction_in[31:12], 12'b0}, default: '0};
            {25'b?, 7'b0010111}: decoded_instr = '{op: op::AUIPC, rd_address: instruction_in[11:7], csr: csr::MSCRATCH, immediate: {instruction_in[31:12], 12'b0}, default: '0};

            // J-Type
            {25'b?, 7'b1101111}: decoded_instr = '{op: op::JAL, rd_address: instruction_in[11:7], csr: csr::MSCRATCH, immediate: {{12{instruction_in[31]}}, instruction_in[19:12], instruction_in[20], instruction_in[30:21], 1'b0}, default: '0};

            // I-Type
            {12'b?, 5'b?, 3'b000, 5'b?, 7'b1100111}: decoded_instr = '{op: op::JALR,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b000, 5'b?, 7'b0000011}: decoded_instr = '{op: op::LB,    rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b001, 5'b?, 7'b0000011}: decoded_instr = '{op: op::LH,    rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b010, 5'b?, 7'b0000011}: decoded_instr = '{op: op::LW,    rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b100, 5'b?, 7'b0000011}: decoded_instr = '{op: op::LBU,   rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b101, 5'b?, 7'b0000011}: decoded_instr = '{op: op::LHU,   rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b000, 5'b?, 7'b0010011}: decoded_instr = '{op: op::ADDI,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b010, 5'b?, 7'b0010011}: decoded_instr = '{op: op::SLTI,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b011, 5'b?, 7'b0010011}: decoded_instr = '{op: op::SLTIU, rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b100, 5'b?, 7'b0010011}: decoded_instr = '{op: op::XORI,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b110, 5'b?, 7'b0010011}: decoded_instr = '{op: op::ORI,   rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {12'b?, 5'b?, 3'b111, 5'b?, 7'b0010011}: decoded_instr = '{op: op::ANDI,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:20]}, default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b001, 5'b?, 7'b0010011}: decoded_instr = '{op: op::SLLI, rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {27'b0, instruction_in[24:20]}, default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b101, 5'b?, 7'b0010011}: decoded_instr = '{op: op::SRLI, rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {27'b0, instruction_in[24:20]}, default: '0};
            {7'b0100000, 5'b?, 5'b?, 3'b101, 5'b?, 7'b0010011}: decoded_instr = '{op: op::SRAI, rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, immediate: {27'b0, instruction_in[24:20]}, default: '0};

            // S-Type
            {7'b?, 5'b?, 5'b?, 3'b000, 5'b?, 7'b0100011}: decoded_instr = '{op: op::SB, rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:25], instruction_in[11:7]}, default: '0};
            {7'b?, 5'b?, 5'b?, 3'b001, 5'b?, 7'b0100011}: decoded_instr = '{op: op::SH, rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:25], instruction_in[11:7]}, default: '0};
            {7'b?, 5'b?, 5'b?, 3'b010, 5'b?, 7'b0100011}: decoded_instr = '{op: op::SW, rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[31:25], instruction_in[11:7]}, default: '0};

            // B-Type
            {7'b?, 5'b?, 5'b?, 3'b000, 5'b?, 7'b1100011}: decoded_instr = '{op: op::BEQ,  rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[7], instruction_in[30:25], instruction_in[11:8], 1'b0}, default: '0};
            {7'b?, 5'b?, 5'b?, 3'b001, 5'b?, 7'b1100011}: decoded_instr = '{op: op::BNE,  rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[7], instruction_in[30:25], instruction_in[11:8], 1'b0}, default: '0};
            {7'b?, 5'b?, 5'b?, 3'b100, 5'b?, 7'b1100011}: decoded_instr = '{op: op::BLT,  rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[7], instruction_in[30:25], instruction_in[11:8], 1'b0}, default: '0};
            {7'b?, 5'b?, 5'b?, 3'b101, 5'b?, 7'b1100011}: decoded_instr = '{op: op::BGE,  rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[7], instruction_in[30:25], instruction_in[11:8], 1'b0}, default: '0};
            {7'b?, 5'b?, 5'b?, 3'b110, 5'b?, 7'b1100011}: decoded_instr = '{op: op::BLTU, rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[7], instruction_in[30:25], instruction_in[11:8], 1'b0}, default: '0};
            {7'b?, 5'b?, 5'b?, 3'b111, 5'b?, 7'b1100011}: decoded_instr = '{op: op::BGEU, rs1_address: instruction_in[19:15], rs2_address: instruction_in[24:20], csr: csr::MSCRATCH, immediate: {{20{instruction_in[31]}}, instruction_in[7], instruction_in[30:25], instruction_in[11:8], 1'b0}, default: '0};

            // R-Type
            {7'b0000000, 5'b?, 5'b?, 3'b000, 5'b?, 7'b0110011}: decoded_instr = '{op: op::ADD,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0100000, 5'b?, 5'b?, 3'b000, 5'b?, 7'b0110011}: decoded_instr = '{op: op::SUB,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b001, 5'b?, 7'b0110011}: decoded_instr = '{op: op::SLL,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b010, 5'b?, 7'b0110011}: decoded_instr = '{op: op::SLT,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b011, 5'b?, 7'b0110011}: decoded_instr = '{op: op::SLTU, rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b100, 5'b?, 7'b0110011}: decoded_instr = '{op: op::XOR,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b101, 5'b?, 7'b0110011}: decoded_instr = '{op: op::SRL,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0100000, 5'b?, 5'b?, 3'b101, 5'b?, 7'b0110011}: decoded_instr = '{op: op::SRA,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b110, 5'b?, 7'b0110011}: decoded_instr = '{op: op::OR,   rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};
            {7'b0000000, 5'b?, 5'b?, 3'b111, 5'b?, 7'b0110011}: decoded_instr = '{op: op::AND,  rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, rs2_address: instruction_in[24:20], default: '0};

            // FENCE
            {12'b?, 5'b?, 3'b000, 5'b?, 7'b0001111}: decoded_instr = '{op: op::FENCE,   rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, default: '0};
            {12'b?, 5'b?, 3'b001, 5'b?, 7'b0001111}: decoded_instr = '{op: op::FENCE_I, rd_address: instruction_in[11:7], rs1_address: instruction_in[19:15], csr: csr::MSCRATCH, default: '0};

            // SYSTEM
            32'h00000073: decoded_instr = '{op: op::ECALL,  csr: csr::MSCRATCH, default: '0};
            32'h00100073: decoded_instr = '{op: op::EBREAK, csr: csr::MSCRATCH, default: '0};
            32'h30200073: decoded_instr = '{op: op::MRET,   csr: csr::MSCRATCH, default: '0};
            32'h10500073: decoded_instr = '{op: op::WFI,    csr: csr::MSCRATCH, default: '0};
            
            // SYSTEM 
            {12'b?, 5'b?, 3'b001, 5'b?, 7'b1110011},
            {12'b?, 5'b?, 3'b010, 5'b?, 7'b1110011},
            {12'b?, 5'b?, 3'b011, 5'b?, 7'b1110011},
            {12'b?, 5'b?, 3'b101, 5'b?, 7'b1110011},
            {12'b?, 5'b?, 3'b110, 5'b?, 7'b1110011},
            {12'b?, 5'b?, 3'b111, 5'b?, 7'b1110011}: decoded_instr = decode_csr(instruction_in);

            default: decoded_instr = '{op: op::ILLEGAL, csr: csr::MSCRATCH, default: '0};
        endcase
    end
endmodule
