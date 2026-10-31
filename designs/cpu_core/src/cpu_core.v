// ============================================================================
// File: cpu_core.v
// Project: 8-Bit Pipelined RISC Microprocessor Core
// Architecture: Harvard Architecture, 5-Stage Pipeline (IF, ID, EX, MEM, WB)
// Target: Standard Verilog-2001 (Universal synthesis: Yosys / OpenLane / OpenROAD)
// Technology: SkyWater 130nm Standard Cells (sky130_fd_sc_hd)
// ============================================================================

`timescale 1ns / 1ps

module cpu_core #(
  parameter DATA_WIDTH  = 8,
  parameter ADDR_WIDTH  = 8,
  parameter INSTR_WIDTH = 16,
  parameter REG_ADDR_W  = 3
)(
  input  wire                   clk,
  input  wire                   rst_n,

  // Instruction Memory Interface (Fetch Stage)
  output wire [ADDR_WIDTH-1:0]  imem_addr,
  input  wire [INSTR_WIDTH-1:0] imem_data,

  // Data Memory Interface (Memory Stage)
  output wire [ADDR_WIDTH-1:0]  dmem_addr,
  output wire [DATA_WIDTH-1:0]  dmem_wdata,
  output wire                   dmem_we,
  output wire                   dmem_re,
  input  wire [DATA_WIDTH-1:0]  dmem_rdata,

  // Observability & Status
  output wire [ADDR_WIDTH-1:0]  debug_pc,
  output reg                    halted
);

  // --------------------------------------------------------------------------
  // Architecture Parameters
  // --------------------------------------------------------------------------
  localparam [3:0]
    OP_RTYPE = 4'b0000,
    OP_SLT   = 4'b0001,
    OP_SLTU  = 4'b0010,
    OP_LDI   = 4'b0011,
    OP_ADDI  = 4'b0100,
    OP_SUBI  = 4'b0101,
    OP_LD    = 4'b0110,
    OP_ST    = 4'b0111,
    OP_BEQ   = 4'b1000,
    OP_BNE   = 4'b1001,
    OP_BLT   = 4'b1010,
    OP_BGE   = 4'b1011,
    OP_JMP   = 4'b1100,
    OP_JAL   = 4'b1101,
    OP_JR    = 4'b1110,
    OP_HALT  = 4'b1111;

  localparam [2:0]
    FUNCT_ADD = 3'b000,
    FUNCT_SUB = 3'b001,
    FUNCT_AND = 3'b010,
    FUNCT_OR  = 3'b011,
    FUNCT_XOR = 3'b100,
    FUNCT_SLL = 3'b101,
    FUNCT_SRL = 3'b110,
    FUNCT_SRA = 3'b111;

  localparam [3:0]
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
    ALU_PASS_B = 4'd10;

  localparam [2:0]
    BR_NONE = 3'd0,
    BR_BEQ  = 3'd1,
    BR_BNE  = 3'd2,
    BR_BLT  = 3'd3,
    BR_BGE  = 3'd4;

  localparam [1:0]
    FWD_NONE = 2'b00,
    FWD_MEM  = 2'b01,
    FWD_WB   = 2'b10;

  // --------------------------------------------------------------------------
  // Interconnect Wires
  // --------------------------------------------------------------------------
  wire [1:0] fwd_a, fwd_b;
  wire       stall, flush_if_id, flush_id_ex;
  reg        branch_taken;
  wire       is_jump_ex;
  wire [ADDR_WIDTH-1:0] branch_target_ex;
  wire [ADDR_WIDTH-1:0] jump_target_ex;

  // --------------------------------------------------------------------------
  // 1. INSTRUCTION FETCH (IF) STAGE
  // --------------------------------------------------------------------------
  reg  [ADDR_WIDTH-1:0] pc;
  reg  [ADDR_WIDTH-1:0] pc_next;
  wire [ADDR_WIDTH-1:0] pc_plus_1;

  assign pc_plus_1 = pc + 8'd1;

  always @(*) begin
    if (branch_taken)
      pc_next = branch_target_ex;
    else if (is_jump_ex)
      pc_next = jump_target_ex;
    else if (stall)
      pc_next = pc;
    else
      pc_next = pc_plus_1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc <= {ADDR_WIDTH{1'b0}};
    else if (!halted)
      pc <= pc_next;
  end

  assign imem_addr = pc;
  assign debug_pc  = pc;

  // IF/ID Pipeline Registers
  reg [ADDR_WIDTH-1:0]  if_id_pc;
  reg [ADDR_WIDTH-1:0]  if_id_pc_plus_1;
  reg [INSTR_WIDTH-1:0] if_id_instr;
  reg                   if_id_valid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      if_id_pc        <= {ADDR_WIDTH{1'b0}};
      if_id_pc_plus_1 <= {ADDR_WIDTH{1'b0}};
      if_id_instr     <= {INSTR_WIDTH{1'b0}};
      if_id_valid     <= 1'b0;
    end else if (flush_if_id) begin
      if_id_pc        <= {ADDR_WIDTH{1'b0}};
      if_id_pc_plus_1 <= {ADDR_WIDTH{1'b0}};
      if_id_instr     <= {INSTR_WIDTH{1'b0}};
      if_id_valid     <= 1'b0;
    end else if (!stall) begin
      if_id_pc        <= pc;
      if_id_pc_plus_1 <= pc_plus_1;
      if_id_instr     <= imem_data;
      if_id_valid     <= (!halted);
    end
  end

  // --------------------------------------------------------------------------
  // 2. INSTRUCTION DECODE (ID) STAGE
  // --------------------------------------------------------------------------
  wire [REG_ADDR_W-1:0] cu_rd, cu_rs1, cu_rs2;
  wire [DATA_WIDTH-1:0] cu_imm;
  wire [3:0]            cu_alu_op;
  wire                  cu_alu_src;
  wire                  cu_mem_read, cu_mem_write, cu_mem_to_reg, cu_reg_write;
  wire [2:0]            cu_branch_type;
  wire                  cu_is_jump, cu_is_jal, cu_is_jr, cu_is_halt;

  control_unit #(
    .DATA_WIDTH(DATA_WIDTH),
    .INSTR_WIDTH(INSTR_WIDTH),
    .REG_ADDR_W(REG_ADDR_W)
  ) u_control (
    .instr       (if_id_instr),
    .rd          (cu_rd),
    .rs1         (cu_rs1),
    .rs2         (cu_rs2),
    .imm         (cu_imm),
    .alu_op      (cu_alu_op),
    .alu_src     (cu_alu_src),
    .mem_read    (cu_mem_read),
    .mem_write   (cu_mem_write),
    .mem_to_reg  (cu_mem_to_reg),
    .reg_write   (cu_reg_write),
    .branch_type (cu_branch_type),
    .is_jump     (cu_is_jump),
    .is_jal      (cu_is_jal),
    .is_jr       (cu_is_jr),
    .is_halt     (cu_is_halt)
  );

  // Register File
  wire [DATA_WIDTH-1:0] rf_rs1_data, rf_rs2_data;
  reg  [DATA_WIDTH-1:0] wb_data;

  // Pipeline register declarations needed for feedback
  reg                   mem_wb_reg_write;
  reg                   mem_wb_valid;
  reg  [REG_ADDR_W-1:0] mem_wb_rd;

  reg_file #(
    .DATA_WIDTH(DATA_WIDTH),
    .REG_ADDR_W(REG_ADDR_W)
  ) u_reg_file (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (cu_rs1),
    .rs1_data (rf_rs1_data),
    .rs2_addr (cu_rs2),
    .rs2_data (rf_rs2_data),
    .wr_en    (mem_wb_reg_write & mem_wb_valid),
    .wr_addr  (mem_wb_rd),
    .wr_data  (wb_data)
  );

  // Source register usage detection for load-use hazard logic
  reg id_uses_rs1, id_uses_rs2;
  wire [3:0] id_opcode;
  assign id_opcode = if_id_instr[15:12];

  always @(*) begin
    case (id_opcode)
      OP_RTYPE, OP_SLT, OP_SLTU: begin
        id_uses_rs1 = 1'b1;
        id_uses_rs2 = 1'b1;
      end
      OP_ADDI, OP_SUBI, OP_LD, OP_JR: begin
        id_uses_rs1 = 1'b1;
        id_uses_rs2 = 1'b0;
      end
      OP_ST: begin
        id_uses_rs1 = 1'b1;
        id_uses_rs2 = 1'b1;
      end
      OP_BEQ, OP_BNE, OP_BLT, OP_BGE: begin
        id_uses_rs1 = 1'b1;
        id_uses_rs2 = 1'b1;
      end
      default: begin
        id_uses_rs1 = 1'b0;
        id_uses_rs2 = 1'b0;
      end
    endcase
  end

  // ID/EX Pipeline Registers
  reg [ADDR_WIDTH-1:0] id_ex_pc;
  reg [ADDR_WIDTH-1:0] id_ex_pc_plus_1;
  reg [DATA_WIDTH-1:0] id_ex_rs1_val;
  reg [DATA_WIDTH-1:0] id_ex_rs2_val;
  reg [DATA_WIDTH-1:0] id_ex_imm;
  reg [REG_ADDR_W-1:0] id_ex_rd;
  reg [REG_ADDR_W-1:0] id_ex_rs1_addr;
  reg [REG_ADDR_W-1:0] id_ex_rs2_addr;
  reg                  id_ex_reg_write;
  reg                  id_ex_mem_read;
  reg                  id_ex_mem_write;
  reg                  id_ex_mem_to_reg;
  reg                  id_ex_alu_src;
  reg [3:0]            id_ex_alu_op;
  reg [2:0]            id_ex_branch_type;
  reg                  id_ex_is_jump;
  reg                  id_ex_is_jal;
  reg                  id_ex_is_jr;
  reg                  id_ex_is_halt;
  reg                  id_ex_valid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex_pc          <= {ADDR_WIDTH{1'b0}};
      id_ex_pc_plus_1   <= {ADDR_WIDTH{1'b0}};
      id_ex_rs1_val     <= {DATA_WIDTH{1'b0}};
      id_ex_rs2_val     <= {DATA_WIDTH{1'b0}};
      id_ex_imm         <= {DATA_WIDTH{1'b0}};
      id_ex_rd          <= {REG_ADDR_W{1'b0}};
      id_ex_rs1_addr    <= {REG_ADDR_W{1'b0}};
      id_ex_rs2_addr    <= {REG_ADDR_W{1'b0}};
      id_ex_reg_write   <= 1'b0;
      id_ex_mem_read    <= 1'b0;
      id_ex_mem_write   <= 1'b0;
      id_ex_mem_to_reg  <= 1'b0;
      id_ex_alu_src     <= 1'b0;
      id_ex_alu_op      <= 4'd0;
      id_ex_branch_type <= 3'd0;
      id_ex_is_jump     <= 1'b0;
      id_ex_is_jal      <= 1'b0;
      id_ex_is_jr       <= 1'b0;
      id_ex_is_halt     <= 1'b0;
      id_ex_valid       <= 1'b0;
    end else if (flush_id_ex) begin
      id_ex_pc          <= {ADDR_WIDTH{1'b0}};
      id_ex_pc_plus_1   <= {ADDR_WIDTH{1'b0}};
      id_ex_rs1_val     <= {DATA_WIDTH{1'b0}};
      id_ex_rs2_val     <= {DATA_WIDTH{1'b0}};
      id_ex_imm         <= {DATA_WIDTH{1'b0}};
      id_ex_rd          <= {REG_ADDR_W{1'b0}};
      id_ex_rs1_addr    <= {REG_ADDR_W{1'b0}};
      id_ex_rs2_addr    <= {REG_ADDR_W{1'b0}};
      id_ex_reg_write   <= 1'b0;
      id_ex_mem_read    <= 1'b0;
      id_ex_mem_write   <= 1'b0;
      id_ex_mem_to_reg  <= 1'b0;
      id_ex_alu_src     <= 1'b0;
      id_ex_alu_op      <= 4'd0;
      id_ex_branch_type <= 3'd0;
      id_ex_is_jump     <= 1'b0;
      id_ex_is_jal      <= 1'b0;
      id_ex_is_jr       <= 1'b0;
      id_ex_is_halt     <= 1'b0;
      id_ex_valid       <= 1'b0;
    end else begin
      id_ex_pc          <= if_id_pc;
      id_ex_pc_plus_1   <= if_id_pc_plus_1;
      id_ex_rs1_val     <= rf_rs1_data;
      id_ex_rs2_val     <= rf_rs2_data;
      id_ex_imm         <= cu_imm;
      id_ex_rd          <= cu_rd;
      id_ex_rs1_addr    <= cu_rs1;
      id_ex_rs2_addr    <= cu_rs2;
      id_ex_reg_write   <= cu_reg_write & if_id_valid;
      id_ex_mem_read    <= cu_mem_read  & if_id_valid;
      id_ex_mem_write   <= cu_mem_write & if_id_valid;
      id_ex_mem_to_reg  <= cu_mem_to_reg;
      id_ex_alu_src     <= cu_alu_src;
      id_ex_alu_op      <= cu_alu_op;
      id_ex_branch_type <= cu_branch_type;
      id_ex_is_jump     <= cu_is_jump   & if_id_valid;
      id_ex_is_jal      <= cu_is_jal    & if_id_valid;
      id_ex_is_jr       <= cu_is_jr     & if_id_valid;
      id_ex_is_halt     <= cu_is_halt   & if_id_valid;
      id_ex_valid       <= if_id_valid;
    end
  end

  // --------------------------------------------------------------------------
  // 3. EXECUTE (EX) STAGE
  // --------------------------------------------------------------------------
  reg  [ADDR_WIDTH-1:0] ex_mem_pc_plus_1;
  reg  [DATA_WIDTH-1:0] ex_mem_alu_result;
  reg  [REG_ADDR_W-1:0] ex_mem_rd;
  reg                   ex_mem_reg_write;
  reg                   ex_mem_mem_read;
  reg                   ex_mem_mem_write;
  reg                   ex_mem_mem_to_reg;
  reg                   ex_mem_is_jal;
  reg                   ex_mem_is_halt;
  reg                   ex_mem_valid;

  wire [DATA_WIDTH-1:0] fwd_val_mem;
  assign fwd_val_mem = (ex_mem_is_jal) ? ex_mem_pc_plus_1 : ex_mem_alu_result;

  reg [DATA_WIDTH-1:0] fwd_a_data;
  reg [DATA_WIDTH-1:0] fwd_b_data;

  always @(*) begin
    case (fwd_a)
      FWD_MEM: fwd_a_data = fwd_val_mem;
      FWD_WB:  fwd_a_data = wb_data;
      default: fwd_a_data = id_ex_rs1_val;
    endcase
  end

  always @(*) begin
    case (fwd_b)
      FWD_MEM: fwd_b_data = fwd_val_mem;
      FWD_WB:  fwd_b_data = wb_data;
      default: fwd_b_data = id_ex_rs2_val;
    endcase
  end

  wire [DATA_WIDTH-1:0] alu_in_a;
  wire [DATA_WIDTH-1:0] alu_in_b;
  assign alu_in_a = fwd_a_data;
  assign alu_in_b = (id_ex_alu_src) ? id_ex_imm : fwd_b_data;

  wire [DATA_WIDTH-1:0] alu_result;
  wire alu_zero, alu_negative, alu_carry, alu_overflow;

  alu #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_alu (
    .a         (alu_in_a),
    .b         (alu_in_b),
    .alu_op    (id_ex_alu_op),
    .result    (alu_result),
    .zero      (alu_zero),
    .negative  (alu_negative),
    .carry_out (alu_carry),
    .overflow  (alu_overflow)
  );

  // Branch and Jump evaluation
  always @(*) begin
    branch_taken = 1'b0;
    if (id_ex_valid) begin
      case (id_ex_branch_type)
        BR_BEQ:  branch_taken = (alu_in_a == fwd_b_data);
        BR_BNE:  branch_taken = (alu_in_a != fwd_b_data);
        BR_BLT:  branch_taken = ($signed(alu_in_a) <  $signed(fwd_b_data));
        BR_BGE:  branch_taken = ($signed(alu_in_a) >= $signed(fwd_b_data));
        default: branch_taken = 1'b0;
      endcase
    end
  end

  assign is_jump_ex       = id_ex_valid & id_ex_is_jump;
  assign branch_target_ex = id_ex_pc_plus_1 + id_ex_imm;
  assign jump_target_ex   = (id_ex_is_jr) ? alu_in_a : id_ex_imm;

  // EX/MEM Pipeline Registers
  reg [DATA_WIDTH-1:0] ex_mem_mem_write_data;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_mem_pc_plus_1      <= {ADDR_WIDTH{1'b0}};
      ex_mem_alu_result     <= {DATA_WIDTH{1'b0}};
      ex_mem_mem_write_data <= {DATA_WIDTH{1'b0}};
      ex_mem_rd             <= {REG_ADDR_W{1'b0}};
      ex_mem_reg_write      <= 1'b0;
      ex_mem_mem_read       <= 1'b0;
      ex_mem_mem_write      <= 1'b0;
      ex_mem_mem_to_reg     <= 1'b0;
      ex_mem_is_jal         <= 1'b0;
      ex_mem_is_halt        <= 1'b0;
      ex_mem_valid          <= 1'b0;
    end else begin
      ex_mem_pc_plus_1      <= id_ex_pc_plus_1;
      ex_mem_alu_result     <= alu_result;
      ex_mem_mem_write_data <= fwd_b_data;
      ex_mem_rd             <= id_ex_rd;
      ex_mem_reg_write      <= id_ex_reg_write;
      ex_mem_mem_read       <= id_ex_mem_read;
      ex_mem_mem_write      <= id_ex_mem_write;
      ex_mem_mem_to_reg     <= id_ex_mem_to_reg;
      ex_mem_is_jal         <= id_ex_is_jal;
      ex_mem_is_halt        <= id_ex_is_halt;
      ex_mem_valid          <= id_ex_valid;
    end
  end

  // --------------------------------------------------------------------------
  // 4. MEMORY ACCESS (MEM) STAGE
  // --------------------------------------------------------------------------
  assign dmem_addr  = ex_mem_alu_result;
  assign dmem_wdata = ex_mem_mem_write_data;
  assign dmem_we    = ex_mem_mem_write & ex_mem_valid;
  assign dmem_re    = ex_mem_mem_read  & ex_mem_valid;

  // MEM/WB Pipeline Registers
  reg [ADDR_WIDTH-1:0] mem_wb_pc_plus_1;
  reg [DATA_WIDTH-1:0] mem_wb_alu_result;
  reg [DATA_WIDTH-1:0] mem_wb_mem_read_data;
  reg                  mem_wb_mem_to_reg;
  reg                  mem_wb_is_jal;
  reg                  mem_wb_is_halt;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_wb_pc_plus_1     <= {ADDR_WIDTH{1'b0}};
      mem_wb_alu_result    <= {DATA_WIDTH{1'b0}};
      mem_wb_mem_read_data <= {DATA_WIDTH{1'b0}};
      mem_wb_rd            <= {REG_ADDR_W{1'b0}};
      mem_wb_reg_write     <= 1'b0;
      mem_wb_mem_to_reg    <= 1'b0;
      mem_wb_is_jal        <= 1'b0;
      mem_wb_is_halt       <= 1'b0;
      mem_wb_valid         <= 1'b0;
    end else begin
      mem_wb_pc_plus_1     <= ex_mem_pc_plus_1;
      mem_wb_alu_result    <= ex_mem_alu_result;
      mem_wb_mem_read_data <= dmem_rdata;
      mem_wb_rd            <= ex_mem_rd;
      mem_wb_reg_write     <= ex_mem_reg_write;
      mem_wb_mem_to_reg    <= ex_mem_mem_to_reg;
      mem_wb_is_jal        <= ex_mem_is_jal;
      mem_wb_is_halt       <= ex_mem_is_halt;
      mem_wb_valid         <= ex_mem_valid;
    end
  end

  // --------------------------------------------------------------------------
  // 5. WRITE-BACK (WB) STAGE
  // --------------------------------------------------------------------------
  always @(*) begin
    if (mem_wb_is_jal)
      wb_data = mem_wb_pc_plus_1;
    else if (mem_wb_mem_to_reg)
      wb_data = mem_wb_mem_read_data;
    else
      wb_data = mem_wb_alu_result;
  end

  // Processor halt latch
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      halted <= 1'b0;
    else if (mem_wb_valid && mem_wb_is_halt)
      halted <= 1'b1;
  end

  // --------------------------------------------------------------------------
  // 6. HAZARD DETECTION & FORWARDING UNIT
  // --------------------------------------------------------------------------
  hazard_unit #(
    .REG_ADDR_W(REG_ADDR_W)
  ) u_hazard (
    .if_id_rs1        (cu_rs1),
    .if_id_rs2        (cu_rs2),
    .id_uses_rs1      (id_uses_rs1),
    .id_uses_rs2      (id_uses_rs2),
    .id_ex_rs1        (id_ex_rs1_addr),
    .id_ex_rs2        (id_ex_rs2_addr),
    .id_ex_rd         (id_ex_rd),
    .id_ex_mem_read   (id_ex_mem_read & id_ex_valid),
    .ex_mem_rd        (ex_mem_rd),
    .ex_mem_reg_write (ex_mem_reg_write & ex_mem_valid),
    .mem_wb_rd        (mem_wb_rd),
    .mem_wb_reg_write (mem_wb_reg_write & mem_wb_valid),
    .branch_taken     (branch_taken),
    .is_jump_ex       (is_jump_ex),
    .fwd_a            (fwd_a),
    .fwd_b            (fwd_b),
    .stall            (stall),
    .flush_if_id      (flush_if_id),
    .flush_id_ex      (flush_id_ex)
  );

endmodule


// ============================================================================
// Module: reg_file
// ============================================================================
module reg_file #(
  parameter DATA_WIDTH = 8,
  parameter REG_ADDR_W = 3
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire [REG_ADDR_W-1:0] rs1_addr,
  output reg  [DATA_WIDTH-1:0] rs1_data,
  input  wire [REG_ADDR_W-1:0] rs2_addr,
  output reg  [DATA_WIDTH-1:0] rs2_data,
  input  wire                  wr_en,
  input  wire [REG_ADDR_W-1:0] wr_addr,
  input  wire [DATA_WIDTH-1:0] wr_data
);
  reg [DATA_WIDTH-1:0] registers [1:7];
  integer i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 1; i < 8; i = i + 1) begin
        registers[i] <= {DATA_WIDTH{1'b0}};
      end
    end else if (wr_en && (wr_addr != 3'd0)) begin
      registers[wr_addr] <= wr_data;
    end
  end

  always @(*) begin
    if (rs1_addr == 3'd0)
      rs1_data = {DATA_WIDTH{1'b0}};
    else if (wr_en && (wr_addr == rs1_addr))
      rs1_data = wr_data;
    else
      rs1_data = registers[rs1_addr];
  end

  always @(*) begin
    if (rs2_addr == 3'd0)
      rs2_data = {DATA_WIDTH{1'b0}};
    else if (wr_en && (wr_addr == rs2_addr))
      rs2_data = wr_data;
    else
      rs2_data = registers[rs2_addr];
  end
endmodule


// ============================================================================
// Module: alu
// ============================================================================
module alu #(
  parameter DATA_WIDTH = 8
)(
  input  wire [DATA_WIDTH-1:0] a,
  input  wire [DATA_WIDTH-1:0] b,
  input  wire [3:0]            alu_op,
  output reg  [DATA_WIDTH-1:0] result,
  output wire                  zero,
  output wire                  negative,
  output reg                   carry_out,
  output reg                   overflow
);
  reg [DATA_WIDTH:0] arith_res;

  always @(*) begin
    arith_res = {(DATA_WIDTH+1){1'b0}};
    carry_out = 1'b0;
    overflow  = 1'b0;
    result    = {DATA_WIDTH{1'b0}};

    case (alu_op)
      4'd0: begin // ALU_ADD
        arith_res = {1'b0, a} + {1'b0, b};
        result    = arith_res[DATA_WIDTH-1:0];
        carry_out = arith_res[DATA_WIDTH];
        overflow  = (~a[DATA_WIDTH-1] & ~b[DATA_WIDTH-1] &  result[DATA_WIDTH-1]) |
                    ( a[DATA_WIDTH-1] &  b[DATA_WIDTH-1] & ~result[DATA_WIDTH-1]);
      end

      4'd1: begin // ALU_SUB
        arith_res = {1'b0, a} - {1'b0, b};
        result    = arith_res[DATA_WIDTH-1:0];
        carry_out = arith_res[DATA_WIDTH];
        overflow  = (~a[DATA_WIDTH-1] &  b[DATA_WIDTH-1] &  result[DATA_WIDTH-1]) |
                    ( a[DATA_WIDTH-1] & ~b[DATA_WIDTH-1] & ~result[DATA_WIDTH-1]);
      end

      4'd2: result = a & b; // ALU_AND
      4'd3: result = a | b; // ALU_OR
      4'd4: result = a ^ b; // ALU_XOR
      4'd5: result = a << b[2:0]; // ALU_SLL
      4'd6: result = a >> b[2:0]; // ALU_SRL
      4'd7: result = $signed(a) >>> b[2:0]; // ALU_SRA
      4'd8: result = ($signed(a) < $signed(b)) ? 8'd1 : 8'd0; // ALU_SLT
      4'd9: result = (a < b) ? 8'd1 : 8'd0; // ALU_SLTU
      4'd10: result = b; // ALU_PASS_B
      default: result = {DATA_WIDTH{1'b0}};
    endcase
  end

  assign zero     = (result == {DATA_WIDTH{1'b0}});
  assign negative = result[DATA_WIDTH-1];
endmodule


// ============================================================================
// Module: control_unit
// ============================================================================
module control_unit #(
  parameter DATA_WIDTH  = 8,
  parameter INSTR_WIDTH = 16,
  parameter REG_ADDR_W  = 3
)(
  input  wire [INSTR_WIDTH-1:0] instr,
  output reg  [REG_ADDR_W-1:0]  rd,
  output reg  [REG_ADDR_W-1:0]  rs1,
  output reg  [REG_ADDR_W-1:0]  rs2,
  output reg  [DATA_WIDTH-1:0]  imm,
  output reg  [3:0]             alu_op,
  output reg                    alu_src,
  output reg                    mem_read,
  output reg                    mem_write,
  output reg                    mem_to_reg,
  output reg                    reg_write,
  output reg  [2:0]             branch_type,
  output reg                    is_jump,
  output reg                    is_jal,
  output reg                    is_jr,
  output reg                    is_halt
);

  localparam [3:0]
    OP_RTYPE = 4'b0000,
    OP_SLT   = 4'b0001,
    OP_SLTU  = 4'b0010,
    OP_LDI   = 4'b0011,
    OP_ADDI  = 4'b0100,
    OP_SUBI  = 4'b0101,
    OP_LD    = 4'b0110,
    OP_ST    = 4'b0111,
    OP_BEQ   = 4'b1000,
    OP_BNE   = 4'b1001,
    OP_BLT   = 4'b1010,
    OP_BGE   = 4'b1011,
    OP_JMP   = 4'b1100,
    OP_JAL   = 4'b1101,
    OP_JR    = 4'b1110,
    OP_HALT  = 4'b1111;

  localparam [2:0]
    FUNCT_ADD = 3'b000,
    FUNCT_SUB = 3'b001,
    FUNCT_AND = 3'b010,
    FUNCT_OR  = 3'b011,
    FUNCT_XOR = 3'b100,
    FUNCT_SLL = 3'b101,
    FUNCT_SRL = 3'b110,
    FUNCT_SRA = 3'b111;

  wire [3:0] opcode = instr[15:12];
  wire [2:0] funct  = instr[2:0];

  always @(*) begin
    rd          = instr[11:9];
    rs1         = instr[8:6];
    rs2         = instr[5:3];
    imm         = {DATA_WIDTH{1'b0}};
    alu_op      = 4'd0;
    alu_src     = 1'b0;
    mem_read    = 1'b0;
    mem_write   = 1'b0;
    mem_to_reg  = 1'b0;
    reg_write   = 1'b0;
    branch_type = 3'd0;
    is_jump     = 1'b0;
    is_jal      = 1'b0;
    is_jr       = 1'b0;
    is_halt     = 1'b0;

    case (opcode)
      OP_RTYPE: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        rs2       = instr[5:3];
        alu_src   = 1'b0;
        reg_write = (rd != 3'd0);
        case (funct)
          FUNCT_ADD: alu_op = 4'd0;
          FUNCT_SUB: alu_op = 4'd1;
          FUNCT_AND: alu_op = 4'd2;
          FUNCT_OR:  alu_op = 4'd3;
          FUNCT_XOR: alu_op = 4'd4;
          FUNCT_SLL: alu_op = 4'd5;
          FUNCT_SRL: alu_op = 4'd6;
          FUNCT_SRA: alu_op = 4'd7;
          default:   alu_op = 4'd0;
        endcase
      end

      OP_SLT: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        rs2       = instr[5:3];
        alu_src   = 1'b0;
        alu_op    = 4'd8;
        reg_write = (rd != 3'd0);
      end

      OP_SLTU: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        rs2       = instr[5:3];
        alu_src   = 1'b0;
        alu_op    = 4'd9;
        reg_write = (rd != 3'd0);
      end

      OP_LDI: begin
        rd        = instr[11:9];
        imm       = instr[7:0];
        alu_src   = 1'b1;
        alu_op    = 4'd10;
        reg_write = (rd != 3'd0);
      end

      OP_ADDI: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        imm       = {{2{instr[5]}}, instr[5:0]};
        alu_src   = 1'b1;
        alu_op    = 4'd0;
        reg_write = (rd != 3'd0);
      end

      OP_SUBI: begin
        rd        = instr[11:9];
        rs1       = instr[8:6];
        imm       = {{2{instr[5]}}, instr[5:0]};
        alu_src   = 1'b1;
        alu_op    = 4'd1;
        reg_write = (rd != 3'd0);
      end

      OP_LD: begin
        rd         = instr[11:9];
        rs1        = instr[8:6];
        imm        = {{2{instr[5]}}, instr[5:0]};
        alu_src    = 1'b1;
        alu_op     = 4'd0;
        mem_read   = 1'b1;
        mem_to_reg = 1'b1;
        reg_write  = (rd != 3'd0);
      end

      OP_ST: begin
        rs2        = instr[11:9];
        rs1        = instr[8:6];
        imm        = {{2{instr[5]}}, instr[5:0]};
        alu_src    = 1'b1;
        alu_op     = 4'd0;
        mem_write  = 1'b1;
        reg_write  = 1'b0;
      end

      OP_BEQ: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = 3'd1;
      end

      OP_BNE: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = 3'd2;
      end

      OP_BLT: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = 3'd3;
      end

      OP_BGE: begin
        rs1         = instr[11:9];
        rs2         = instr[8:6];
        imm         = {{2{instr[5]}}, instr[5:0]};
        branch_type = 3'd4;
      end

      OP_JMP: begin
        imm     = instr[7:0];
        is_jump = 1'b1;
      end

      OP_JAL: begin
        rd        = instr[11:9];
        imm       = instr[7:0];
        is_jump   = 1'b1;
        is_jal    = 1'b1;
        reg_write = (rd != 3'd0);
      end

      OP_JR: begin
        rs1     = instr[8:6];
        is_jr   = 1'b1;
        is_jump = 1'b1;
      end

      OP_HALT: begin
        is_halt = 1'b1;
      end

      default: begin
        // NOP
      end
    endcase
  end
endmodule


// ============================================================================
// Module: hazard_unit
// ============================================================================
module hazard_unit #(
  parameter REG_ADDR_W = 3
)(
  input  wire [REG_ADDR_W-1:0] if_id_rs1,
  input  wire [REG_ADDR_W-1:0] if_id_rs2,
  input  wire                  id_uses_rs1,
  input  wire                  id_uses_rs2,

  input  wire [REG_ADDR_W-1:0] id_ex_rs1,
  input  wire [REG_ADDR_W-1:0] id_ex_rs2,
  input  wire [REG_ADDR_W-1:0] id_ex_rd,
  input  wire                  id_ex_mem_read,

  input  wire [REG_ADDR_W-1:0] ex_mem_rd,
  input  wire                  ex_mem_reg_write,

  input  wire [REG_ADDR_W-1:0] mem_wb_rd,
  input  wire                  mem_wb_reg_write,

  input  wire                  branch_taken,
  input  wire                  is_jump_ex,

  output reg  [1:0]            fwd_a,
  output reg  [1:0]            fwd_b,
  output reg                   stall,
  output reg                   flush_if_id,
  output reg                   flush_id_ex
);

  localparam [1:0]
    FWD_NONE = 2'b00,
    FWD_MEM  = 2'b01,
    FWD_WB   = 2'b10;

  always @(*) begin
    if (ex_mem_reg_write && (ex_mem_rd != 3'd0) && (ex_mem_rd == id_ex_rs1))
      fwd_a = FWD_MEM;
    else if (mem_wb_reg_write && (mem_wb_rd != 3'd0) && (mem_wb_rd == id_ex_rs1))
      fwd_a = FWD_WB;
    else
      fwd_a = FWD_NONE;
  end

  always @(*) begin
    if (ex_mem_reg_write && (ex_mem_rd != 3'd0) && (ex_mem_rd == id_ex_rs2))
      fwd_b = FWD_MEM;
    else if (mem_wb_reg_write && (mem_wb_rd != 3'd0) && (mem_wb_rd == id_ex_rs2))
      fwd_b = FWD_WB;
    else
      fwd_b = FWD_NONE;
  end

  reg load_use_hazard;
  always @(*) begin
    load_use_hazard = 1'b0;
    if (id_ex_mem_read && (id_ex_rd != 3'd0)) begin
      if ((id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
          (id_uses_rs2 && (id_ex_rd == if_id_rs2))) begin
        load_use_hazard = 1'b1;
      end
    end
  end

  wire control_hazard = branch_taken | is_jump_ex;

  always @(*) begin
    if (control_hazard) begin
      stall       = 1'b0;
      flush_if_id = 1'b1;
      flush_id_ex = 1'b1;
    end else if (load_use_hazard) begin
      stall       = 1'b1;
      flush_if_id = 1'b0;
      flush_id_ex = 1'b1;
    end else begin
      stall       = 1'b0;
      flush_if_id = 1'b0;
      flush_id_ex = 1'b0;
    end
  end
endmodule
