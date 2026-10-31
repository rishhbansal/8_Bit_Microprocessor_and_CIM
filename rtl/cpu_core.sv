// ============================================================================
// File: cpu_core.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Core processor integrating the 5 pipeline stages (IF, ID, EX, MEM, WB),
//              Hazard Detection Unit, Data Forwarding, and Register File.
// ============================================================================

`include "cpu_pkg.sv"

module cpu_core
  import cpu_pkg::*;
(
  input  logic                   clk,
  input  logic                   rst_n,

  // Instruction Memory Interface
  output logic [ADDR_WIDTH-1:0]  imem_addr,
  input  logic [INSTR_WIDTH-1:0] imem_data,

  // Data Memory Interface
  output logic [ADDR_WIDTH-1:0]  dmem_addr,
  output logic [DATA_WIDTH-1:0]  dmem_wdata,
  output logic                   dmem_we,
  output logic                   dmem_re,
  input  logic [DATA_WIDTH-1:0]  dmem_rdata,

  // Core Status / Observability
  output logic [ADDR_WIDTH-1:0]  debug_pc,
  output logic                   halted
);

  // --------------------------------------------------------------------------
  // Pipeline Register Signals
  // --------------------------------------------------------------------------
  if_id_reg_t  if_id_in,  if_id_out;
  id_ex_reg_t  id_ex_in,  id_ex_out;
  ex_mem_reg_t ex_mem_in, ex_mem_out;
  mem_wb_reg_t mem_wb_in, mem_wb_out;

  // Hazard / Control Feedback Signals
  fwd_t fwd_a, fwd_b;
  logic stall;
  logic flush_if_id, flush_id_ex;
  logic branch_taken;
  logic is_jump_ex;
  logic [ADDR_WIDTH-1:0] branch_target_ex;
  logic [ADDR_WIDTH-1:0] jump_target_ex;

  // --------------------------------------------------------------------------
  // 1. INSTRUCTION FETCH (IF) STAGE
  // --------------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] pc, pc_next, pc_plus_1;

  assign pc_plus_1 = pc + 8'd1;

  // Next PC selection logic
  always_comb begin
    if (branch_taken) begin
      pc_next = branch_target_ex;
    end else if (is_jump_ex) begin
      pc_next = jump_target_ex;
    end else if (stall) begin
      pc_next = pc; // Freeze PC on load-use stall
    end else begin
      pc_next = pc_plus_1;
    end
  end

  // PC register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= '0;
    end else if (!halted) begin
      pc <= pc_next;
    end
  end

  // Instruction memory drive
  assign imem_addr = pc;
  assign debug_pc  = pc;

  // IF/ID Pipeline Register Inputs
  assign if_id_in.pc        = pc;
  assign if_id_in.pc_plus_1 = pc_plus_1;
  assign if_id_in.instr     = imem_data;
  assign if_id_in.valid     = rst_n & !halted;

  pipeline_reg_if_id u_if_id (
    .clk   (clk),
    .rst_n (rst_n),
    .stall (stall),
    .flush (flush_if_id),
    .in    (if_id_in),
    .out   (if_id_out)
  );

  // --------------------------------------------------------------------------
  // 2. INSTRUCTION DECODE (ID) STAGE
  // --------------------------------------------------------------------------
  logic [REG_ADDR_W-1:0] cu_rd, cu_rs1, cu_rs2;
  logic [DATA_WIDTH-1:0] cu_imm;
  alu_op_t               cu_alu_op;
  logic                  cu_alu_src;
  logic                  cu_mem_read, cu_mem_write, cu_mem_to_reg, cu_reg_write;
  branch_type_t          cu_branch_type;
  logic                  cu_is_jump, cu_is_jal, cu_is_jr, cu_is_halt;

  control_unit u_control (
    .instr       (if_id_out.instr),
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
  logic [DATA_WIDTH-1:0] rf_rs1_data, rf_rs2_data;
  logic [DATA_WIDTH-1:0] wb_data;

  reg_file u_reg_file (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (cu_rs1),
    .rs1_data (rf_rs1_data),
    .rs2_addr (cu_rs2),
    .rs2_data (rf_rs2_data),
    .wr_en    (mem_wb_out.reg_write & mem_wb_out.valid),
    .wr_addr  (mem_wb_out.rd),
    .wr_data  (wb_data)
  );

  // Source register usage identification for load-use detection
  logic id_uses_rs1, id_uses_rs2;
  opcode_t id_opcode;
  assign id_opcode = opcode_t'(if_id_out.instr[15:12]);

  always_comb begin
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
        id_uses_rs1 = 1'b1; // Base address
        id_uses_rs2 = 1'b1; // Store data register
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

  // ID/EX Pipeline Register Inputs
  assign id_ex_in.pc          = if_id_out.pc;
  assign id_ex_in.pc_plus_1   = if_id_out.pc_plus_1;
  assign id_ex_in.rs1_val     = rf_rs1_data;
  assign id_ex_in.rs2_val     = rf_rs2_data;
  assign id_ex_in.imm         = cu_imm;
  assign id_ex_in.rd          = cu_rd;
  assign id_ex_in.rs1_addr    = cu_rs1;
  assign id_ex_in.rs2_addr    = cu_rs2;
  assign id_ex_in.reg_write   = cu_reg_write & if_id_out.valid;
  assign id_ex_in.mem_read    = cu_mem_read  & if_id_out.valid;
  assign id_ex_in.mem_write   = cu_mem_write & if_id_out.valid;
  assign id_ex_in.mem_to_reg  = cu_mem_to_reg;
  assign id_ex_in.alu_src     = cu_alu_src;
  assign id_ex_in.alu_op      = cu_alu_op;
  assign id_ex_in.branch_type = cu_branch_type;
  assign id_ex_in.is_jump     = cu_is_jump   & if_id_out.valid;
  assign id_ex_in.is_jal      = cu_is_jal    & if_id_out.valid;
  assign id_ex_in.is_jr       = cu_is_jr     & if_id_out.valid;
  assign id_ex_in.is_halt     = cu_is_halt   & if_id_out.valid;
  assign id_ex_in.valid       = if_id_out.valid;

  pipeline_reg_id_ex u_id_ex (
    .clk   (clk),
    .rst_n (rst_n),
    .flush (flush_id_ex),
    .in    (id_ex_in),
    .out   (id_ex_out)
  );

  // --------------------------------------------------------------------------
  // 3. EXECUTE (EX) STAGE
  // --------------------------------------------------------------------------
  // Forwarding Multiplexers
  logic [DATA_WIDTH-1:0] fwd_val_mem;
  assign fwd_val_mem = (ex_mem_out.is_jal) ? ex_mem_out.pc_plus_1 : ex_mem_out.alu_result;

  logic [DATA_WIDTH-1:0] fwd_a_data, fwd_b_data;

  always_comb begin
    case (fwd_a)
      FWD_MEM: fwd_a_data = fwd_val_mem;
      FWD_WB:  fwd_a_data = wb_data;
      default: fwd_a_data = id_ex_out.rs1_val;
    endcase
  end

  always_comb begin
    case (fwd_b)
      FWD_MEM: fwd_b_data = fwd_val_mem;
      FWD_WB:  fwd_b_data = wb_data;
      default: fwd_b_data = id_ex_out.rs2_val;
    endcase
  end

  // ALU Input Muxes
  logic [DATA_WIDTH-1:0] alu_in_a, alu_in_b;
  assign alu_in_a = fwd_a_data;
  assign alu_in_b = (id_ex_out.alu_src) ? id_ex_out.imm : fwd_b_data;

  // ALU Instance
  logic [DATA_WIDTH-1:0] alu_result;
  logic alu_zero, alu_negative, alu_carry, alu_overflow;

  alu u_alu (
    .a         (alu_in_a),
    .b         (alu_in_b),
    .alu_op    (id_ex_out.alu_op),
    .result    (alu_result),
    .zero      (alu_zero),
    .negative  (alu_negative),
    .carry_out (alu_carry),
    .overflow  (alu_overflow)
  );

  // Branch & Jump Evaluation in EX
  always_comb begin
    branch_taken = 1'b0;
    if (id_ex_out.valid) begin
      case (id_ex_out.branch_type)
        BR_BEQ:  branch_taken = (alu_in_a == fwd_b_data);
        BR_BNE:  branch_taken = (alu_in_a != fwd_b_data);
        BR_BLT:  branch_taken = ($signed(alu_in_a) <  $signed(fwd_b_data));
        BR_BGE:  branch_taken = ($signed(alu_in_a) >= $signed(fwd_b_data));
        default: branch_taken = 1'b0;
      endcase
    end
  end

  assign is_jump_ex       = id_ex_out.valid & id_ex_out.is_jump;
  assign branch_target_ex = id_ex_out.pc_plus_1 + id_ex_out.imm;
  assign jump_target_ex   = (id_ex_out.is_jr) ? alu_in_a : id_ex_out.imm;

  // EX/MEM Pipeline Register Inputs
  assign ex_mem_in.pc_plus_1      = id_ex_out.pc_plus_1;
  assign ex_mem_in.alu_result     = alu_result;
  assign ex_mem_in.mem_write_data = fwd_b_data; // Forwarded store data
  assign ex_mem_in.rd             = id_ex_out.rd;
  assign ex_mem_in.reg_write      = id_ex_out.reg_write;
  assign ex_mem_in.mem_read       = id_ex_out.mem_read;
  assign ex_mem_in.mem_write      = id_ex_out.mem_write;
  assign ex_mem_in.mem_to_reg     = id_ex_out.mem_to_reg;
  assign ex_mem_in.is_jal         = id_ex_out.is_jal;
  assign ex_mem_in.is_halt        = id_ex_out.is_halt;
  assign ex_mem_in.valid          = id_ex_out.valid;

  pipeline_reg_ex_mem u_ex_mem (
    .clk   (clk),
    .rst_n (rst_n),
    .in    (ex_mem_in),
    .out   (ex_mem_out)
  );

  // --------------------------------------------------------------------------
  // 4. MEMORY ACCESS (MEM) STAGE
  // --------------------------------------------------------------------------
  assign dmem_addr  = ex_mem_out.alu_result;
  assign dmem_wdata = ex_mem_out.mem_write_data;
  assign dmem_we    = ex_mem_out.mem_write & ex_mem_out.valid;
  assign dmem_re    = ex_mem_out.mem_read  & ex_mem_out.valid;

  // MEM/WB Pipeline Register Inputs
  assign mem_wb_in.pc_plus_1     = ex_mem_out.pc_plus_1;
  assign mem_wb_in.alu_result    = ex_mem_out.alu_result;
  assign mem_wb_in.mem_read_data = dmem_rdata;
  assign mem_wb_in.rd            = ex_mem_out.rd;
  assign mem_wb_in.reg_write     = ex_mem_out.reg_write;
  assign mem_wb_in.mem_to_reg    = ex_mem_out.mem_to_reg;
  assign mem_wb_in.is_jal        = ex_mem_out.is_jal;
  assign mem_wb_in.is_halt       = ex_mem_out.is_halt;
  assign mem_wb_in.valid         = ex_mem_out.valid;

  pipeline_reg_mem_wb u_mem_wb (
    .clk   (clk),
    .rst_n (rst_n),
    .in    (mem_wb_in),
    .out   (mem_wb_out)
  );

  // --------------------------------------------------------------------------
  // 5. WRITE-BACK (WB) STAGE
  // --------------------------------------------------------------------------
  always_comb begin
    if (mem_wb_out.is_jal) begin
      wb_data = mem_wb_out.pc_plus_1; // Return address
    end else if (mem_wb_out.mem_to_reg) begin
      wb_data = mem_wb_out.mem_read_data;
    end else begin
      wb_data = mem_wb_out.alu_result;
    end
  end

  // Processor halt latch
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      halted <= 1'b0;
    end else if (mem_wb_out.valid && mem_wb_out.is_halt) begin
      halted <= 1'b1;
    end
  end

  // --------------------------------------------------------------------------
  // 6. HAZARD DETECTION & FORWARDING UNIT
  // --------------------------------------------------------------------------
  hazard_unit u_hazard (
    .if_id_rs1        (cu_rs1),
    .if_id_rs2        (cu_rs2),
    .id_uses_rs1      (id_uses_rs1),
    .id_uses_rs2      (id_uses_rs2),
    .id_ex_rs1        (id_ex_out.rs1_addr),
    .id_ex_rs2        (id_ex_out.rs2_addr),
    .id_ex_rd         (id_ex_out.rd),
    .id_ex_mem_read   (id_ex_out.mem_read & id_ex_out.valid),
    .ex_mem_rd        (ex_mem_out.rd),
    .ex_mem_reg_write (ex_mem_out.reg_write & ex_mem_out.valid),
    .mem_wb_rd        (mem_wb_out.rd),
    .mem_wb_reg_write (mem_wb_out.reg_write & mem_wb_out.valid),
    .branch_taken     (branch_taken),
    .is_jump_ex       (is_jump_ex),
    .fwd_a            (fwd_a),
    .fwd_b            (fwd_b),
    .stall            (stall),
    .flush_if_id      (flush_if_id),
    .flush_id_ex      (flush_id_ex)
  );

endmodule : cpu_core
