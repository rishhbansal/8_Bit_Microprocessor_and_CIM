// ============================================================================
// File: alu.sv
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Arithmetic Logic Unit with support for signed/unsigned operations,
//              arithmetic & logical shifts, and comparison flags.
// ============================================================================

`include "cpu_pkg.sv"

module alu
  import cpu_pkg::*;
(
  input  logic [DATA_WIDTH-1:0] a,
  input  logic [DATA_WIDTH-1:0] b,
  input  alu_op_t               alu_op,
  output logic [DATA_WIDTH-1:0] result,
  output logic                  zero,
  output logic                  negative,
  output logic                  carry_out,
  output logic                  overflow
);

  logic [DATA_WIDTH:0] arith_res; // 9-bit temporary to capture carry/borrow

  always_comb begin
    arith_res = '0;
    carry_out = 1'b0;
    overflow  = 1'b0;

    case (alu_op)
      ALU_ADD: begin
        arith_res = {1'b0, a} + {1'b0, b};
        result    = arith_res[DATA_WIDTH-1:0];
        carry_out = arith_res[DATA_WIDTH];
        // Overflow in signed addition: (+A) + (+B) = -Res or (-A) + (-B) = +Res
        overflow  = (~a[DATA_WIDTH-1] & ~b[DATA_WIDTH-1] &  result[DATA_WIDTH-1]) |
                    ( a[DATA_WIDTH-1] &  b[DATA_WIDTH-1] & ~result[DATA_WIDTH-1]);
      end

      ALU_SUB: begin
        arith_res = {1'b0, a} - {1'b0, b};
        result    = arith_res[DATA_WIDTH-1:0];
        carry_out = arith_res[DATA_WIDTH]; // Borrow flag
        // Overflow in signed subtraction: (+A) - (-B) = -Res or (-A) - (+B) = +Res
        overflow  = (~a[DATA_WIDTH-1] &  b[DATA_WIDTH-1] &  result[DATA_WIDTH-1]) |
                    ( a[DATA_WIDTH-1] & ~b[DATA_WIDTH-1] & ~result[DATA_WIDTH-1]);
      end

      ALU_AND: begin
        result = a & b;
      end

      ALU_OR: begin
        result = a | b;
      end

      ALU_XOR: begin
        result = a ^ b;
      end

      // Logical Shift Left: bits shifted in are zero
      ALU_SLL: begin
        result = a << b[2:0];
      end

      // Logical Shift Right (unsigned): zeroes shifted in at MSB
      ALU_SRL: begin
        result = a >> b[2:0];
      end

      // Arithmetic Shift Right (signed): sign-bit replicated into MSBs
      ALU_SRA: begin
        result = $signed(a) >>> b[2:0];
      end

      // Set Less Than (Signed comparison)
      ALU_SLT: begin
        result = ($signed(a) < $signed(b)) ? 8'd1 : 8'd0;
      end

      // Set Less Than Unsigned
      ALU_SLTU: begin
        result = (a < b) ? 8'd1 : 8'd0;
      end

      // Pass B (used for LDI: Rd = Immediate)
      ALU_PASS_B: begin
        result = b;
      end

      default: begin
        result = '0;
      end
    endcase
  end

  // Status flags
  assign zero     = (result == {DATA_WIDTH{1'b0}});
  assign negative = result[DATA_WIDTH-1];

endmodule : alu
