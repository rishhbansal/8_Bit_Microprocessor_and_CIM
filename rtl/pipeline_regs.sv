// ============================================================================
// File: pipeline_regs.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Synchronous pipeline stage registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
//              with stall and flush capabilities.
// ============================================================================

`include "cpu_pkg.sv"

// ----------------------------------------------------------------------------
// IF / ID Pipeline Register
// ----------------------------------------------------------------------------
module pipeline_reg_if_id
  import cpu_pkg::*;
(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       stall,
  input  logic       flush,
  input  if_id_reg_t in,
  output if_id_reg_t out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out <= '0;
    end else if (flush) begin
      out <= '0; // Flushes to NOP (valid = 0)
    end else if (!stall) begin
      out <= in;  // Normal pipeline step
    end
    // if stall == 1, maintain previous 'out' value
  end

endmodule : pipeline_reg_if_id

// ----------------------------------------------------------------------------
// ID / EX Pipeline Register
// ----------------------------------------------------------------------------
module pipeline_reg_id_ex
  import cpu_pkg::*;
(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       flush, // Active on branch mispredict or stall bubble
  input  id_ex_reg_t in,
  output id_ex_reg_t out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out <= '0;
    end else if (flush) begin
      out <= '0; // Bubble insertion (control signals de-asserted)
    end else begin
      out <= in;
    end
  end

endmodule : pipeline_reg_id_ex

// ----------------------------------------------------------------------------
// EX / MEM Pipeline Register
// ----------------------------------------------------------------------------
module pipeline_reg_ex_mem
  import cpu_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  ex_mem_reg_t in,
  output ex_mem_reg_t out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out <= '0;
    end else begin
      out <= in;
    end
  end

endmodule : pipeline_reg_ex_mem

// ----------------------------------------------------------------------------
// MEM / WB Pipeline Register
// ----------------------------------------------------------------------------
module pipeline_reg_mem_wb
  import cpu_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  mem_wb_reg_t in,
  output mem_wb_reg_t out
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out <= '0;
    end else begin
      out <= in;
    end
  end

endmodule : pipeline_reg_mem_wb
