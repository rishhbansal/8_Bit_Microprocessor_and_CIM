// ============================================================================
// File: hazard_unit.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Detects data and control hazards.
//              - Forwards operands from EX/MEM and MEM/WB to EX stage (RAW hazards).
//              - Detects Load-Use hazards and inserts 1-cycle stall bubble.
//              - Generates pipeline flush signals for branches and jumps.
// ============================================================================

`include "cpu_pkg.sv"

module hazard_unit
  import cpu_pkg::*;
(
  // Source register addresses from ID stage (for load-use detection)
  input  logic [REG_ADDR_W-1:0] if_id_rs1,
  input  logic [REG_ADDR_W-1:0] if_id_rs2,
  input  logic                  id_uses_rs1,
  input  logic                  id_uses_rs2,

  // ID/EX stage signals
  input  logic [REG_ADDR_W-1:0] id_ex_rs1,
  input  logic [REG_ADDR_W-1:0] id_ex_rs2,
  input  logic [REG_ADDR_W-1:0] id_ex_rd,
  input  logic                  id_ex_mem_read,

  // EX/MEM stage signals
  input  logic [REG_ADDR_W-1:0] ex_mem_rd,
  input  logic                  ex_mem_reg_write,

  // MEM/WB stage signals
  input  logic [REG_ADDR_W-1:0] mem_wb_rd,
  input  logic                  mem_wb_reg_write,

  // Branch / Jump control from EX stage
  input  logic                  branch_taken,
  input  logic                  is_jump_ex,

  // Forwarding control outputs (to EX stage ALU input muxes)
  output fwd_t                  fwd_a,
  output fwd_t                  fwd_b,

  // Hazard handling outputs
  output logic                  stall,        // Stalls PC and IF/ID
  output logic                  flush_if_id,  // Flushes IF/ID register
  output logic                  flush_id_ex   // Flushes ID/EX register
);

  // --------------------------------------------------------------------------
  // 1. Data Forwarding Unit (EX Stage ALU Inputs)
  // --------------------------------------------------------------------------
  always_comb begin
    // Forwarding for Operand A (id_ex_rs1)
    if (ex_mem_reg_write && (ex_mem_rd != 3'd0) && (ex_mem_rd == id_ex_rs1)) begin
      fwd_a = FWD_MEM; // Forward from EX/MEM stage
    end else if (mem_wb_reg_write && (mem_wb_rd != 3'd0) && (mem_wb_rd == id_ex_rs1)) begin
      fwd_a = FWD_WB;  // Forward from MEM/WB stage
    end else begin
      fwd_a = FWD_NONE;
    end

    // Forwarding for Operand B (id_ex_rs2)
    if (ex_mem_reg_write && (ex_mem_rd != 3'd0) && (ex_mem_rd == id_ex_rs2)) begin
      fwd_b = FWD_MEM; // Forward from EX/MEM stage
    end else if (mem_wb_reg_write && (mem_wb_rd != 3'd0) && (mem_wb_rd == id_ex_rs2)) begin
      fwd_b = FWD_WB;  // Forward from MEM/WB stage
    end else begin
      fwd_b = FWD_NONE;
    end
  end

  // --------------------------------------------------------------------------
  // 2. Load-Use Hazard Detection
  // If the instruction currently in EX is a LOAD (mem_read == 1) and its
  // destination register (id_ex_rd) matches either rs1 or rs2 of the instruction
  // currently in ID stage, insert a 1-cycle bubble.
  // --------------------------------------------------------------------------
  logic load_use_hazard;

  always_comb begin
    load_use_hazard = 1'b0;
    if (id_ex_mem_read && (id_ex_rd != 3'd0)) begin
      if ((id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
          (id_uses_rs2 && (id_ex_rd == if_id_rs2))) begin
        load_use_hazard = 1'b1;
      end
    end
  end

  // --------------------------------------------------------------------------
  // 3. Stall and Flush Generation
  // --------------------------------------------------------------------------
  logic control_hazard;
  assign control_hazard = branch_taken | is_jump_ex;

  always_comb begin
    if (control_hazard) begin
      // Branch taken or Jump: flush wrong-path instructions in IF and ID
      stall       = 1'b0;
      flush_if_id = 1'b1;
      flush_id_ex = 1'b1;
    end else if (load_use_hazard) begin
      // Load-use hazard: freeze PC and IF/ID, insert bubble (flush) into ID/EX
      stall       = 1'b1;
      flush_if_id = 1'b0;
      flush_id_ex = 1'b1;
    end else begin
      stall       = 1'b0;
      flush_if_id = 1'b0;
      flush_id_ex = 1'b0;
    end
  end

endmodule : hazard_unit
