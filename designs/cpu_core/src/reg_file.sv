// ============================================================================
// File: reg_file.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Dual-read, single-write 8x8 register file.
//              R0 is hardwired to 0. Internal forwarding ensures write-before-read
//              transparency between WB and ID stages.
// ============================================================================

`include "cpu_pkg.sv"

module reg_file
  import cpu_pkg::*;
(
  input  logic                   clk,
  input  logic                   rst_n,

  // Read port 1
  input  logic [REG_ADDR_W-1:0]  rs1_addr,
  output logic [DATA_WIDTH-1:0]  rs1_data,

  // Read port 2
  input  logic [REG_ADDR_W-1:0]  rs2_addr,
  output logic [DATA_WIDTH-1:0]  rs2_data,

  // Write port
  input  logic                   wr_en,
  input  logic [REG_ADDR_W-1:0]  wr_addr,
  input  logic [DATA_WIDTH-1:0]  wr_data
);

  // Registers R1 to R7 (R0 is hardwired to 0)
  logic [DATA_WIDTH-1:0] registers [1:REG_COUNT-1];

  // Synchronous Write Operation
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 1; i < REG_COUNT; i++) begin
        registers[i] <= '0;
      end
    end else if (wr_en && (wr_addr != 3'd0)) begin
      registers[wr_addr] <= wr_data;
    end
  end

  // Asynchronous Read with internal forwarding (write-before-read)
  // Read Port 1:
  always_comb begin
    if (rs1_addr == 3'd0) begin
      rs1_data = '0; // R0 is always zero
    end else if (wr_en && (wr_addr == rs1_addr)) begin
      rs1_data = wr_data; // WB-to-ID internal bypass
    end else begin
      rs1_data = registers[rs1_addr];
    end
  end

  // Read Port 2:
  always_comb begin
    if (rs2_addr == 3'd0) begin
      rs2_data = '0; // R0 is always zero
    end else if (wr_en && (wr_addr == rs2_addr)) begin
      rs2_data = wr_data; // WB-to-ID internal bypass
    end else begin
      rs2_data = registers[rs2_addr];
    end
  end

endmodule : reg_file
