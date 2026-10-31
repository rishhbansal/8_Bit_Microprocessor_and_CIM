// ============================================================================
// File: cpu_pkg.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Package containing architecture definitions, opcodes, ALU operations,
//              and pipeline register data structures.
// Target: AMD/Xilinx Vivado (SystemVerilog IEEE 1800-2012/2017)
// ============================================================================

`ifndef CPU_PKG_SV
`define CPU_PKG_SV

package cpu_pkg;

  // --------------------------------------------------------------------------
  // Architectural Constants
  // --------------------------------------------------------------------------
  localparam int DATA_WIDTH  = 8;   // 8-bit ALU, registers, and data memory
  localparam int ADDR_WIDTH  = 8;   // 8-bit program counter and data addresses
  localparam int INSTR_WIDTH = 16;  // 16-bit fixed instruction width
  localparam int REG_COUNT   = 8;   // 8 general purpose registers (R0 - R7)
  localparam int REG_ADDR_W  = 3;   // log2(8) = 3 bits to address R0..R7

  // --------------------------------------------------------------------------
  // Instruction Opcodes (instr[15:12])
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    OP_RTYPE  = 4'b0000,  // Register-Register ALU operations (funct specifies op)
    OP_SLT    = 4'b0001,  // Set Less Than Signed: Rd = (Rs1 < Rs2) ? 1 : 0
    OP_SLTU   = 4'b0010,  // Set Less Than Unsigned: Rd = (Rs1 < Rs2) ? 1 : 0
    OP_LDI    = 4'b0011,  // Load Immediate: Rd = Imm8
    OP_ADDI   = 4'b0100,  // Add Immediate: Rd = Rs1 + SignExt(Imm6)
    OP_SUBI   = 4'b0101,  // Subtract Immediate: Rd = Rs1 - SignExt(Imm6)
    OP_LD     = 4'b0110,  // Load Data from Memory: Rd = Mem[Rs1 + Offset]
    OP_ST     = 4'b0111,  // Store Data to Memory: Mem[Rs1 + Offset] = Rs2
    OP_BEQ    = 4'b1000,  // Branch if Equal: if (Rs1 == Rs2) PC = Target
    OP_BNE    = 4'b1001,  // Branch if Not Equal: if (Rs1 != Rs2) PC = Target
    OP_BLT    = 4'b1010,  // Branch if Less Than (signed): if (Rs1 < Rs2) PC = Target
    OP_BGE    = 4'b1011,  // Branch if Greater/Equal (signed): if (Rs1 >= Rs2) PC = Target
    OP_JMP    = 4'b1100,  // Unconditional Jump: PC = Target8
    OP_JAL    = 4'b1101,  // Jump and Link: Rd = PC + 1, PC = Target8
    OP_JR     = 4'b1110,  // Jump Register: PC = Rs1
    OP_HALT   = 4'b1111   // Halt processor execution
  } opcode_t;

  // --------------------------------------------------------------------------
  // R-Type Function Codes (instr[2:0])
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    FUNCT_ADD = 3'b000,   // Addition: Rd = Rs1 + Rs2
    FUNCT_SUB = 3'b001,   // Subtraction: Rd = Rs1 - Rs2
    FUNCT_AND = 3'b010,   // Bitwise AND: Rd = Rs1 & Rs2
    FUNCT_OR  = 3'b011,   // Bitwise OR: Rd = Rs1 | Rs2
    FUNCT_XOR = 3'b100,   // Bitwise XOR: Rd = Rs1 ^ Rs2
    FUNCT_SLL = 3'b101,   // Shift Left Logical: Rd = Rs1 << Rs2[2:0]
    FUNCT_SRL = 3'b110,   // Shift Right Logical (unsigned): Rd = Rs1 >> Rs2[2:0]
    FUNCT_SRA = 3'b111    // Shift Right Arithmetic (signed): Rd = Rs1 >>> Rs2[2:0]
  } funct_t;

  // --------------------------------------------------------------------------
  // ALU Operation Control Codes
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD    = 4'd0,
    ALU_SUB    = 4'd1,
    ALU_AND    = 4'd2,
    ALU_OR     = 4'd3,
    ALU_XOR    = 4'd4,
    ALU_SLL    = 4'd5,
    ALU_SRL    = 4'd6,
    ALU_SRA    = 4'd7,
    ALU_SLT    = 4'd8,
    ALU_SLTU   = 4'd9,
    ALU_PASS_B = 4'd10
  } alu_op_t;

  // --------------------------------------------------------------------------
  // Branch Condition Types
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    BR_NONE = 3'd0,
    BR_BEQ  = 3'd1,
    BR_BNE  = 3'd2,
    BR_BLT  = 3'd3,
    BR_BGE  = 3'd4
  } branch_type_t;

  // --------------------------------------------------------------------------
  // Forwarding Control Enums
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FWD_NONE = 2'b00,  // Use register file operand directly from ID/EX
    FWD_MEM  = 2'b01,  // Forward from EX/MEM stage (1 instruction ahead)
    FWD_WB   = 2'b10   // Forward from MEM/WB stage (2 instructions ahead)
  } fwd_t;

  // --------------------------------------------------------------------------
  // Pipeline Register Data Structures (Packed Structs)
  // --------------------------------------------------------------------------

  // IF -> ID Pipeline Register
  typedef struct packed {
    logic [ADDR_WIDTH-1:0]  pc;
    logic [ADDR_WIDTH-1:0]  pc_plus_1;
    logic [INSTR_WIDTH-1:0] instr;
    logic                   valid;
  } if_id_reg_t;

  // ID -> EX Pipeline Register
  typedef struct packed {
    logic [ADDR_WIDTH-1:0]  pc;
    logic [ADDR_WIDTH-1:0]  pc_plus_1;
    logic [DATA_WIDTH-1:0]  rs1_val;
    logic [DATA_WIDTH-1:0]  rs2_val;
    logic [DATA_WIDTH-1:0]  imm;
    logic [REG_ADDR_W-1:0]  rd;
    logic [REG_ADDR_W-1:0]  rs1_addr;
    logic [REG_ADDR_W-1:0]  rs2_addr;
    // Control Signals
    logic                   reg_write;
    logic                   mem_read;
    logic                   mem_write;
    logic                   mem_to_reg;
    logic                   alu_src;     // 0: Rs2, 1: Immediate
    alu_op_t                alu_op;
    branch_type_t           branch_type;
    logic                   is_jump;
    logic                   is_jal;
    logic                   is_jr;
    logic                   is_halt;
    logic                   valid;
  } id_ex_reg_t;

  // EX -> MEM Pipeline Register
  typedef struct packed {
    logic [ADDR_WIDTH-1:0]  pc_plus_1;
    logic [DATA_WIDTH-1:0]  alu_result;
    logic [DATA_WIDTH-1:0]  mem_write_data;
    logic [REG_ADDR_W-1:0]  rd;
    // Control Signals
    logic                   reg_write;
    logic                   mem_read;
    logic                   mem_write;
    logic                   mem_to_reg;
    logic                   is_jal;
    logic                   is_halt;
    logic                   valid;
  } ex_mem_reg_t;

  // MEM -> WB Pipeline Register
  typedef struct packed {
    logic [ADDR_WIDTH-1:0]  pc_plus_1;
    logic [DATA_WIDTH-1:0]  alu_result;
    logic [DATA_WIDTH-1:0]  mem_read_data;
    logic [REG_ADDR_W-1:0]  rd;
    // Control Signals
    logic                   reg_write;
    logic                   mem_to_reg;
    logic                   is_jal;
    logic                   is_halt;
    logic                   valid;
  } mem_wb_reg_t;

endpackage : cpu_pkg

`endif // CPU_PKG_SV
