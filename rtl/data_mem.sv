// ============================================================================
// File: data_mem.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Data Memory (RAM) with 256 bytes of 8-bit storage.
//              Synchronous write, asynchronous read for single-cycle MEM stage.
// ============================================================================

`include "cpu_pkg.sv"

module data_mem
  import cpu_pkg::*;
#(
  parameter string INIT_FILE = ""
)(
  input  logic                  clk,
  input  logic [ADDR_WIDTH-1:0] addr,
  input  logic [DATA_WIDTH-1:0] write_data,
  input  logic                  mem_write,
  input  logic                  mem_read,
  output logic [DATA_WIDTH-1:0] read_data
);

  localparam int MEM_DEPTH = 1 << ADDR_WIDTH; // 256 bytes

  logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  // Initialize memory from hex file if provided
  initial begin
    for (int i = 0; i < MEM_DEPTH; i++) begin
      mem[i] = '0;
    end
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // Synchronous Write
  always_ff @(posedge clk) begin
    if (mem_write) begin
      mem[addr] <= write_data;
    end
  end

  // Asynchronous Read
  assign read_data = (mem_read) ? mem[addr] : 8'd0;

endmodule : data_mem
