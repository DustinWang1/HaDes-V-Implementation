/* Copyright (c) 2024 Tobias Scheipel, David Beikircher, Florian Riedl
 * Embedded Architectures & Systems Group, Graz University of Technology
 * SPDX-License-Identifier: MIT
 * ---------------------------------------------------------------------
 * File: instruction_decoder.sv
 */



module instruction_decoder (
    input  logic [31:0]   instruction_in,
    output instruction::t instruction_out
);
    instruction::t decoded_instr;
    assign instruction_out = decoded_instr;

    always_comb begin
        // Start with default assignments to prevent latches and handle illegal instructions
        decoded_instr.op          = op::ILLEGAL;
        decoded_instr.rd_address  = 5'b0;
        decoded_instr.rs1_address = 5'b0;
        decoded_instr.rs2_address = 5'b0;
        decoded_instr.immediate   = 32'b0;
        decoded_instr.csr         = csr::t'(0); // Default to a valid, but neutral, enum value

        case (instruction_in[6:0])
            // R-Type: Register-Register Operations (e.g., add rd, rs1, rs2)
            7'b0110011: begin // OP
                decoded_instr.rd_address  = instruction_in[11:7];
                decoded_instr.rs1_address = instruction_in[19:15];
                decoded_instr.rs2_address = instruction_in[24:20];
                case (instruction_in[14:12]) // funct3
                    3'b000: decoded_instr.op = (instruction_in[30]) ? op::SUB : op::ADD;
                    3'b001: decoded_instr.op = op::SLL;
                    3'b010: decoded_instr.op = op::SLT;
                    3'b011: decoded_instr.op = op::SLTU;
                    3'b100: decoded_instr.op = op::XOR;
                    3'b101: decoded_instr.op = (instruction_in[30]) ? op::SRA : op::SRL;
                    3'b110: decoded_instr.op = op::OR;
                    3'b111: decoded_instr.op = op::AND;
                    default: decoded_instr.op = op::ILLEGAL;
                endcase
            end

            // I-Type: Register-Immediate Operations
            7'b0010011: begin // OP-IMM (e.g., addi rd, rs1, imm)
                decoded_instr.rd_address  = instruction_in[11:7];
                decoded_instr.rs1_address = instruction_in[19:15];
                decoded_instr.immediate   = {{20{instruction_in[31]}}, instruction_in[31:20]}; // Sign-extended immediate
                case (instruction_in[14:12]) // funct3
                    3'b000: decoded_instr.op = op::ADDI;
                    3'b001: decoded_instr.op = op::SLLI;
                    3'b010: decoded_instr.op = op::SLTI;
                    3'b011: decoded_instr.op = op::SLTIU;
                    3'b100: decoded_instr.op = op::XORI;
                    3'b101: decoded_instr.op = (instruction_in[30]) ? op::SRAI : op::SRLI;
                    3'b110: decoded_instr.op = op::ORI;
                    3'b111: decoded_instr.op = op::ANDI;
                    default: decoded_instr.op = op::ILLEGAL;
                endcase
            end
            7'b0000011: begin // LOAD (e.g., lw rd, imm(rs1))
                decoded_instr.rd_address  = instruction_in[11:7];
                decoded_instr.rs1_address = instruction_in[19:15];
                decoded_instr.immediate   = {{20{instruction_in[31]}}, instruction_in[31:20]}; // Sign-extended immediate
                case (instruction_in[14:12]) // funct3
                    3'b000: decoded_instr.op = op::LB;
                    3'b001: decoded_instr.op = op::LH;
                    3'b010: decoded_instr.op = op::LW;
                    3'b100: decoded_instr.op = op::LBU;
                    3'b101: decoded_instr.op = op::LHU;
                    default: decoded_instr.op = op::ILLEGAL;
                endcase
            end
            7'b1100111: begin // JALR
                decoded_instr.op          = op::JALR;
                decoded_instr.rd_address  = instruction_in[11:7];
                decoded_instr.rs1_address = instruction_in[19:15];
                decoded_instr.immediate   = {{20{instruction_in[31]}}, instruction_in[31:20]}; // Sign-extended immediate
            end

            // S-Type: Store Operations (e.g., sw rs2, imm(rs1))
            7'b0100011: begin // STORE
                decoded_instr.rs1_address = instruction_in[19:15];
                decoded_instr.rs2_address = instruction_in[24:20];
                // Reassemble immediate from scattered bits, then sign-extend
                decoded_instr.immediate   = {{20{instruction_in[31]}}, instruction_in[31:25], instruction_in[11:7]};
                case (instruction_in[14:12]) // funct3
                    3'b000: decoded_instr.op = op::SB;
                    3'b001: decoded_instr.op = op::SH;
                    3'b010: decoded_instr.op = op::SW;
                    default: decoded_instr.op = op::ILLEGAL;
                endcase
            end

            // B-Type: Branch Operations (e.g., beq rs1, rs2, imm)
            7'b1100011: begin // BRANCH
                decoded_instr.rs1_address = instruction_in[19:15];
                decoded_instr.rs2_address = instruction_in[24:20];
                // Reassemble immediate and sign-extend. Note the final 0 bit.
                decoded_instr.immediate = {{20{instruction_in[31]}}, instruction_in[7], instruction_in[30:25], instruction_in[11:8], 1'b0};
                case (instruction_in[14:12]) // funct3
                    3'b000: decoded_instr.op = op::BEQ;
                    3'b001: decoded_instr.op = op::BNE;
                    3'b100: decoded_instr.op = op::BLT;
                    3'b101: decoded_instr.op = op::BGE;
                    3'b110: decoded_instr.op = op::BLTU;
                    3'b111: decoded_instr.op = op::BGEU;
                    default: decoded_instr.op = op::ILLEGAL;
                endcase
            end

            // U-Type: Upper Immediate Operations
            7'b0110111: begin // LUI
                decoded_instr.op         = op::LUI;
                decoded_instr.rd_address = instruction_in[11:7];
                decoded_instr.immediate  = {instruction_in[31:12], 12'b0};
            end
            7'b0010111: begin // AUIPC
                decoded_instr.op         = op::AUIPC;
                decoded_instr.rd_address = instruction_in[11:7];
                decoded_instr.immediate  = {instruction_in[31:12], 12'b0};
            end

            // J-Type: Jump Operations
            7'b1101111: begin // JAL
                decoded_instr.op         = op::JAL;
                decoded_instr.rd_address = instruction_in[11:7];
                // Reassemble immediate from J-type's unique bit locations
                decoded_instr.immediate = {{12{instruction_in[31]}}, instruction_in[19:12], instruction_in[20], instruction_in[30:21], 1'b0};
            end

            // System & CSR Instructions
            7'b1110011: begin // SYSTEM
                // First, decode special system instructions that don't use the CSR format
                if (instruction_in[31:7] == 25'h0000000)      decoded_instr.op = op::ECALL;
                else if (instruction_in[31:7] == 25'h0010000) decoded_instr.op = op::EBREAK;
                else if (instruction_in[31:7] == 25'h3020000) decoded_instr.op = op::MRET;
                else if (instruction_in[31:7] == 25'h1050000) decoded_instr.op = op::WFI;
                else begin // Otherwise, it's a CSR instruction
                    case (instruction_in[14:12]) // funct3 for CSR
                        3'b001: begin decoded_instr.op = op::CSRRW;  decoded_instr.rs1_address = instruction_in[19:15]; end
                        3'b010: begin decoded_instr.op = op::CSRRS;  decoded_instr.rs1_address = instruction_in[19:15]; end
                        3'b011: begin decoded_instr.op = op::CSRRC;  decoded_instr.rs1_address = instruction_in[19:15]; end
                        3'b101: begin decoded_instr.op = op::CSRRWI; decoded_instr.immediate = {27'b0, instruction_in[19:15]}; end
                        3'b110: begin decoded_instr.op = op::CSRRSI; decoded_instr.immediate = {27'b0, instruction_in[19:15]}; end
                        3'b111: begin decoded_instr.op = op::CSRRCI; decoded_instr.immediate = {27'b0, instruction_in[19:15]}; end
                        default: decoded_instr.op = op::ILLEGAL;
                    endcase

                    decoded_instr.rd_address = instruction_in[11:7];
                    // Translate the 12-bit CSR address from the instruction into the csr::t enum type
                    case (instruction_in[31:20])
                        // List of CSRs implemented in the HADES-V processor
                        csr::MSTATUS:   decoded_instr.csr = csr::MSTATUS;
                        csr::MTVEC:     decoded_instr.csr = csr::MTVEC;
                        csr::MIP:       decoded_instr.csr = csr::MIP;
                        csr::MIE:       decoded_instr.csr = csr::MIE;
                        csr::MCYCLE:    decoded_instr.csr = csr::MCYCLE;
                        csr::MCYCLEH:   decoded_instr.csr = csr::MCYCLEH;
                        csr::MINSTRET:  decoded_instr.csr = csr::MINSTRET;
                        csr::MINSTRETH: decoded_instr.csr = csr::MINSTRETH;
                        csr::MSCRATCH:  decoded_instr.csr = csr::MSCRATCH;
                        csr::MEPC:      decoded_instr.csr = csr::MEPC;
                        csr::MCAUSE:    decoded_instr.csr = csr::MCAUSE;
                        default:        decoded_instr.op = op::ILLEGAL; // Attempt to access an unimplemented CSR
                    endcase
                end
            end

            // FENCE Instructions
            7'b0001111: begin // FENCE
                decoded_instr.rd_address  = instruction_in[11:7];
                decoded_instr.rs1_address = instruction_in[19:15];
                case (instruction_in[14:12]) // funct3
                    3'b000: decoded_instr.op = op::FENCE;
                    3'b001: decoded_instr.op = op::FENCE_I;
                    default: decoded_instr.op = op::ILLEGAL;
                endcase
            end

            default: begin
                decoded_instr.op = op::ILLEGAL;
            end
        endcase
    end
endmodule
