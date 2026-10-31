// ============================================================================
// File: instruction_mem.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Instruction Memory (ROM/RAM) addressing 256 16-bit instructions.
//              Supports initial program loading via hex file.
// ============================================================================

`include "cpu_pkg.sv"

module instruction_mem
  import cpu_pkg::*;
#(
  parameter string INIT_FILE = ""
)(
  input  logic [ADDR_WIDTH-1:0]  addr,
  output logic [INSTR_WIDTH-1:0] instr
);

  localparam int MEM_DEPTH = 1 << ADDR_WIDTH; // 256 words

  logic [INSTR_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  // Initialize memory from hex file if provided
  initial begin
    for (int i = 0; i < MEM_DEPTH; i++) begin
      mem[i] = '0; // Default to NOP
    end
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // Asynchronous read for single-cycle IF stage
  assign instr = mem[addr];

endmodule : instruction_mem
