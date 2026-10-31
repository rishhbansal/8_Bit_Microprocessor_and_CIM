// ============================================================================
// File: cpu_top.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Top-level SoC wrapper integrating cpu_core, instruction_mem,
//              and data_mem. Synthesizable for Vivado targeting Xilinx FPGAs.
// ============================================================================

`include "cpu_pkg.sv"

module cpu_top
  import cpu_pkg::*;
#(
  parameter string IMEM_INIT_FILE = "",
  parameter string DMEM_INIT_FILE = ""
)(
  input  logic                  clk,
  input  logic                  rst_n,
  output logic                  halted,
  output logic [ADDR_WIDTH-1:0] debug_pc
);

  // Instruction Memory Interconnect
  logic [ADDR_WIDTH-1:0]  imem_addr;
  logic [INSTR_WIDTH-1:0] imem_data;

  // Data Memory Interconnect
  logic [ADDR_WIDTH-1:0]  dmem_addr;
  logic [DATA_WIDTH-1:0]  dmem_wdata;
  logic                   dmem_we;
  logic                   dmem_re;
  logic [DATA_WIDTH-1:0]  dmem_rdata;

  // Instantiate CPU Core
  cpu_core u_core (
    .clk        (clk),
    .rst_n      (rst_n),
    .imem_addr  (imem_addr),
    .imem_data  (imem_data),
    .dmem_addr  (dmem_addr),
    .dmem_wdata (dmem_wdata),
    .dmem_we    (dmem_we),
    .dmem_re    (dmem_re),
    .dmem_rdata (dmem_rdata),
    .debug_pc   (debug_pc),
    .halted     (halted)
  );

  // Instantiate Instruction Memory (ROM / Harvard Architecture)
  instruction_mem #(
    .INIT_FILE (IMEM_INIT_FILE)
  ) u_imem (
    .addr  (imem_addr),
    .instr (imem_data)
  );

  // Instantiate Data Memory (RAM)
  data_mem #(
    .INIT_FILE (DMEM_INIT_FILE)
  ) u_dmem (
    .clk        (clk),
    .addr       (dmem_addr),
    .write_data (dmem_wdata),
    .mem_write  (dmem_we),
    .mem_read   (dmem_re),
    .read_data  (dmem_rdata)
  );

endmodule : cpu_top
