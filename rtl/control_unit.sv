// ============================================================================
// File: control_unit.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Decodes 16-bit instructions, generates control signals for
//              datapath, pipeline registers, and immediate extraction.
// ============================================================================

`include "cpu_pkg.sv"

module control_unit
  import cpu_pkg::*;
(
  input  logic [INSTR_WIDTH-1:0] instr,

  // Register addresses
  output logic [REG_ADDR_W-1:0]  rd,
  output logic [REG_ADDR_W-1:0]  rs1,
  output logic [REG_ADDR_W-1:0]  rs2,

  // Immediate value (8-bit)
  output logic [DATA_WIDTH-1:0]  imm,

  // Execution Control
  output alu_op_t                alu_op,
  output logic                   alu_src,    // 0: Rs2, 1: Immediate

  // Memory Control
  output logic                   mem_read,
  output logic                   mem_write,
  output logic                   mem_to_reg, // 0: ALU result, 1: Mem read data

  // Register File Control
  output logic                   reg_write,

  // Branch & Jump Control
  output branch_type_t           branch_type,
  output logic                   is_jump,
  output logic                   is_jal,
  output logic                   is_jr,
  output logic                   is_halt
);

  opcode_t opcode;
  funct_t  funct;

  assign opcode = opcode_t'(instr[15:12]);
  assign funct  = funct_t'(instr[2:0]);

  always_comb begin
    // Default assignments (NOP / safe defaults)
    rd          = instr[11:9];
    rs1         = instr[8:6];
    rs2         = instr[5:3];
    imm         = 8'd0;
    alu_op      = ALU_ADD;
    alu_src     = 1'b0;
    mem_read    = 1'b0;
    mem_write   = 1'b0;
    mem_to_reg  = 1'b0;
    reg_write   = 1'b0;
    branch_type = BR_NONE;
    is_jump     = 1'b0;
    is_jal      = 1'b0;
    is_jr       = 1'b0;
    is_halt     = 1'b0;

    case (opcode)
      // ----------------------------------------------------------------------
      // R-Type Instructions (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA)
      // Format: [15:12]=0000 | [11:9]=Rd | [8:6]=Rs1 | [5:3]=Rs2 | [2:0]=Funct
      // ----------------------------------------------------------------------
      OP_RTYPE: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        rs2       = instr[5:3];
        alu_src   = 1'b0;
        reg_write = (rd != 3'd0); // R0 is read-only
        case (funct)
          FUNCT_ADD: alu_op = ALU_ADD;
          FUNCT_SUB: alu_op = ALU_SUB;
          FUNCT_AND: alu_op = ALU_AND;
          FUNCT_OR:  alu_op = ALU_OR;
          FUNCT_XOR: alu_op = ALU_XOR;
          FUNCT_SLL: alu_op = ALU_SLL;
          FUNCT_SRL: alu_op = ALU_SRL;
          FUNCT_SRA: alu_op = ALU_SRA;
          default:   alu_op = ALU_ADD;
        endcase
      end

      // ----------------------------------------------------------------------
      // Set Less Than Signed: Rd = (Rs1 < Rs2) ? 1 : 0
      // ----------------------------------------------------------------------
      OP_SLT: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        rs2       = instr[5:3];
        alu_src   = 1'b0;
        alu_op    = ALU_SLT;
        reg_write = (rd != 3'd0);
      end

      // ----------------------------------------------------------------------
      // Set Less Than Unsigned: Rd = (Rs1 < Rs2) ? 1 : 0
      // ----------------------------------------------------------------------
      OP_SLTU: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        rs2       = instr[5:3];
        alu_src   = 1'b0;
        alu_op    = ALU_SLTU;
        reg_write = (rd != 3'd0);
      end

      // ----------------------------------------------------------------------
      // Load Immediate: Rd = Imm8
      // Format: [15:12]=0011 | [11:9]=Rd | [7:0]=Imm8
      // ----------------------------------------------------------------------
      OP_LDI: begin
        rd        = instr[11:9];
        imm       = instr[7:0];
        alu_src   = 1'b1;
        alu_op    = ALU_PASS_B;
        reg_write = (rd != 3'd0);
      end

      // ----------------------------------------------------------------------
      // Add Immediate: Rd = Rs1 + SignExt(Imm6)
      // Format: [15:12]=0100 | [11:9]=Rd | [8:6]=Rs1 | [5:0]=Imm6
      // ----------------------------------------------------------------------
      OP_ADDI: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        imm       = {{2{instr[5]}}, instr[5:0]}; // 6-bit sign extend
        alu_src   = 1'b1;
        alu_op    = ALU_ADD;
        reg_write = (rd != 3'd0);
      end

      // ----------------------------------------------------------------------
      // Subtract Immediate: Rd = Rs1 - SignExt(Imm6)
      // ----------------------------------------------------------------------
      OP_SUBI: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        imm       = {{2{instr[5]}}, instr[5:0]};
        alu_src   = 1'b1;
        alu_op    = ALU_SUB;
        reg_write = (rd != 3'd0);
      end

      // ----------------------------------------------------------------------
      // Load from Memory: Rd = Mem[Rs1 + SignExt(offset)]
      // Format: [15:12]=0110 | [11:9]=Rd | [8:6]=Rs1 | [5:0]=offset
      // ----------------------------------------------------------------------
      OP_LD: begin
        rd         = instr[11:9];
        rs1        = instr[8:6];
        imm        = {{2{instr[5]}}, instr[5:0]};
        alu_src    = 1'b1;
        alu_op     = ALU_ADD;
        mem_read   = 1'b1;
        mem_to_reg = 1'b1;
        reg_write  = (rd != 3'd0);
      end

      // ----------------------------------------------------------------------
      // Store to Memory: Mem[Rs1 + SignExt(offset)] = Rs2
      // Format: [15:12]=0111 | [11:9]=Rs2(store data) | [8:6]=Rs1(base) | [5:0]=offset
      // ----------------------------------------------------------------------
      OP_ST: begin
        rs2        = instr[11:9]; // In ST, [11:9] is the data register
        rs1        = instr[8:6];  // Base address register
        imm        = {{2{instr[5]}}, instr[5:0]};
        alu_src    = 1'b1;
        alu_op     = ALU_ADD;
        mem_write  = 1'b1;
        reg_write  = 1'b0;
      end

      // ----------------------------------------------------------------------
      // Branch if Equal: if (Rs1 == Rs2) PC = PC + 1 + SignExt(offset)
      // Format: [15:12]=1000 | [11:9]=Rs1 | [8:6]=Rs2 | [5:0]=offset
      // ----------------------------------------------------------------------
      OP_BEQ: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = BR_BEQ;
      end

      // ----------------------------------------------------------------------
      // Branch if Not Equal
      // ----------------------------------------------------------------------
      OP_BNE: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = BR_BNE;
      end

      // ----------------------------------------------------------------------
      // Branch if Less Than (signed)
      // ----------------------------------------------------------------------
      OP_BLT: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = BR_BLT;
      end

      // ----------------------------------------------------------------------
      // Branch if Greater/Equal (signed)
      // ----------------------------------------------------------------------
      OP_BGE: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = BR_BGE;
      end

      // ----------------------------------------------------------------------
      // Unconditional Jump: PC = Target8
      // Format: [15:12]=1100 | [11:8]=unused | [7:0]=Target8
      // ----------------------------------------------------------------------
      OP_JMP: begin
        imm     = instr[7:0];
        is_jump = 1'b1;
      end

      // ----------------------------------------------------------------------
      // Jump and Link: Rd = PC + 1, PC = Target8
      // Format: [15:12]=1101 | [11:9]=Rd | [7:0]=Target8
      // ----------------------------------------------------------------------
      OP_JAL: begin
        rd        = instr[11:9];
        imm       = instr[7:0];
        is_jump   = 1'b1;
        is_jal    = 1'b1;
        reg_write = (rd != 3'd0);
      end

      // ----------------------------------------------------------------------
      // Jump Register: PC = Rs1
      // Format: [15:12]=1110 | [8:6]=Rs1
      // ----------------------------------------------------------------------
      OP_JR: begin
        rs1     = instr[8:6];
        is_jr   = 1'b1;
        is_jump = 1'b1;
      end

      // ----------------------------------------------------------------------
      // Halt Processor
      // ----------------------------------------------------------------------
      OP_HALT: begin
        is_halt = 1'b1;
      end

      default: begin
        // NOP
      end
    endcase
  end

endmodule : control_unit
