# First Principles & Tinkering Guide: 8-Bit Pipelined RISC Microprocessor
## Understanding Every Line of SystemVerilog from Silicon to Architecture

Welcome to the engineering guide for this processor. This document is specifically written to bridge the transition from classic **Verilog-2001** to modern **SystemVerilog (IEEE 1800)**, breaking down every module block-by-block from **first principles** (logic gates, registers, multiplexers, and pipeline flow).

---

## 1. SystemVerilog vs. Verilog: The Mental Pivot

When pivoting from Verilog to SystemVerilog in RTL design, keep these three rules of thumb in mind:

| Verilog-2001 Concept | SystemVerilog Upgrade | Why It Matters (First Principles) |
| :--- | :--- | :--- |
| `wire` vs `reg` confusion | `logic` | In Verilog, beginners struggle with "why is an output a `reg` if it is combinatorial?". In SystemVerilog, `logic` is a 4-state data type that can be driven by either continuous assignment (`assign`) or procedural blocks (`always_comb`/`always_ff`). |
| `always @(*)` | `always_comb` | `always_comb` prevents unintentional latch inference. If you miss an `else` branch, the compiler immediately warns you. It also evaluates at time zero to avoid simulation race conditions. |
| `always @(posedge clk)` | `always_ff @(posedge clk or negedge rst_n)` | Enforces flip-flop semantics. Synthesis tools and linters will throw an error if you accidentally write non-clocked combinational code inside it. |
| `#define` or separate `wire` bundles | `typedef enum` and `typedef struct packed` | Grouping pipeline registers into packed structs turns messy 25-wire inter-stage connections into a single structured signal, preventing port-mismatch bugs. |

---

## 2. File-by-File Block Walkthrough

### File 1: `rtl/cpu_pkg.sv` (Architecture Definition & Structs)

#### Block A: Opcodes & ALU Enums
```systemverilog
typedef enum logic [3:0] {
  OP_RTYPE  = 4'b0000,
  OP_SLT    = 4'b0001,
  OP_LDI    = 4'b0011,
  ...
} opcode_t;
```
* **Hardware Inferred:** 4-bit binary wire encoding.
* **Why do this?** In Vivado simulation waveforms, instead of seeing `4'h3`, you will see `OP_LDI`. It makes waveform debugging instant.
* **Tinkering Idea:** Add a new opcode like `OP_MUL` or `OP_NOT` by giving it a unique 4-bit code.

#### Block B: Packed Pipeline Structs
```systemverilog
typedef struct packed {
  logic [ADDR_WIDTH-1:0]  pc;
  logic [ADDR_WIDTH-1:0]  pc_plus_1;
  logic [INSTR_WIDTH-1:0] instr;
  logic                   valid;
} if_id_reg_t;
```
* **Hardware Inferred:** A set of contiguous D flip-flops with a total bit-width equal to the sum of the fields (8 + 8 + 16 + 1 = 33 flip-flops).
* **The "Packed" Keyword:** `packed` guarantees that the simulator and synthesis tool treat the struct as a contiguous flat bit-vector. You can slice it, reset it with `'0`, and pass it across module boundaries as a single bus.

---

### File 2: `rtl/alu.sv` (Arithmetic Logic Unit)

#### Block A: Port Definitions
```systemverilog
module alu import cpu_pkg::*; (
  input  logic [DATA_WIDTH-1:0] a, b,
  input  alu_op_t               alu_op,
  output logic [DATA_WIDTH-1:0] result,
  output logic                  zero, negative, carry_out, overflow
);
```
* **Hardware Inferred:** 8-bit combinational data path and status flag comparators.

#### Block B: Signed vs. Unsigned Operations & Shifts
```systemverilog
// Unsigned Logical Shift Right
ALU_SRL: result = a >> b[2:0];

// Signed Arithmetic Shift Right
ALU_SRA: result = $signed(a) >>> b[2:0];
```
* **Hardware Inferred:** 8-bit barrel shifter multiplexer tree.
* **First Principles:**
  * When shifting `8'b1111_0000` (-16 in 2's complement) right by 2:
  * `SRL` fills the top two bits with `00`: `0011_1100` (60 decimal).
  * `SRA` fills the top two bits with the sign-bit `11`: `1111_1100` (-4 decimal). This preserves signed division by $2^k$.
* **Tinkering Idea:** Try shifting negative numbers and verify in waveforms that `negative` flag stays high.

#### Block C: Overflow Detection
```systemverilog
overflow = (~a[7] & ~b[7] & result[7]) | (a[7] & b[7] & ~result[7]);
```
* **First Principles:** If you add two positive numbers and get a negative number (or two negatives and get a positive), arithmetic overflow has occurred!

---

### File 3: `rtl/reg_file.sv` (Register File 8x8)

#### Block A: Storage Elements
```systemverilog
logic [DATA_WIDTH-1:0] registers [1:REG_COUNT-1];
```
* **Hardware Inferred:** 56 D-flip-flops (7 registers of 8 bits each).
* **Why is R0 omitted?** R0 is hardwired to 0. Omitting it from the array saves 8 flip-flops and simplifies zeroing registers.

#### Block B: Internal Forwarding (Write-Before-Read)
```systemverilog
always_comb begin
  if (rs1_addr == 3'd0) begin
    rs1_data = '0;
  end else if (wr_en && (wr_addr == rs1_addr)) begin
    rs1_data = wr_data; // Bypass!
  end else begin
    rs1_data = registers[rs1_addr];
  end
end
```
* **Hardware Inferred:** 8-to-1 multiplexer with bypass comparator (`wr_addr == rs1_addr`).
* **First Principles:** In a 5-stage pipeline, the Write-Back stage writes to a register at the exact same clock edge that Decode is reading it. Without this bypass, the Decode stage would read stale data (the value from the previous cycle). Internal forwarding makes the register file *transparent*.

---

### File 4: `rtl/control_unit.sv` (Decoder)

#### Block A: Instruction Field Slicing
```systemverilog
assign opcode = opcode_t'(instr[15:12]);
assign funct  = funct_t'(instr[2:0]);
```
* **Hardware Inferred:** Direct wire taps from the instruction register.

#### Block B: Immediate Sign Extension
```systemverilog
imm = {{2{instr[5]}}, instr[5:0]};
```
* **Hardware Inferred:** Wire replication. The sign bit `instr[5]` is copied twice onto the upper bits `[7:6]`.
* **First Principles:** To add a 6-bit negative number (e.g. -3 = `6'b111101`) to an 8-bit register, you must sign-extend it to 8 bits (`8'b11111101`). If you zero-extended it instead, -3 would turn into +61!

---

### File 5: `rtl/hazard_unit.sv` (Hazards & Forwarding)

This is the brain of high-performance pipelined execution.

#### Block A: ALU Data Forwarding (RAW Hazards)
```systemverilog
if (ex_mem_reg_write && (ex_mem_rd != 3'd0) && (ex_mem_rd == id_ex_rs1)) begin
  fwd_a = FWD_MEM; // Forward from EX/MEM stage
end else if (mem_wb_reg_write && (mem_wb_rd != 3'd0) && (mem_wb_rd == id_ex_rs1)) begin
  fwd_a = FWD_WB;  // Forward from MEM/WB stage
end else begin
  fwd_a = FWD_NONE;
end
```
* **Hardware Inferred:** 3-to-1 multiplexer feeding the ALU inputs, controlled by address match comparators.
* **First Principles:**
  * If instruction 1 is `ADD R1, R2, R3` (currently in EX/MEM) and instruction 2 is `SUB R4, R1, R5` (currently in EX), R1 is sitting on the output of the EX/MEM register. We route that wire directly into the ALU input, eliminating 2 wasted stall cycles!

#### Block B: Load-Use Hazard Stall
```systemverilog
if (id_ex_mem_read && (id_ex_rd != 3'd0)) begin
  if ((id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
      (id_uses_rs2 && (id_ex_rd == if_id_rs2))) begin
    load_use_hazard = 1'b1;
  end
end
```
* **First Principles:** Data from a `LD` instruction is physically inside the Data RAM. It is NOT available until the end of the MEM stage. Forwarding cannot travel backward in time! Therefore, the processor MUST insert a 1-cycle stall bubble:
  1. Freeze the Program Counter (`pc_next = pc`).
  2. Freeze the IF/ID register.
  3. Clear the ID/EX control signals (injecting a NOP bubble into EX).

#### Block C: Control Hazard Flush
```systemverilog
if (branch_taken | is_jump_ex) begin
  flush_if_id = 1'b1;
  flush_id_ex = 1'b1;
end
```
* **First Principles:** When a branch is taken, the instructions fetched in the subsequent 2 cycles are on the wrong execution path. We synchronously assert synchronous reset on IF/ID and ID/EX, converting those ghost instructions into harmless NOPs.

---

### File 6: `rtl/cpu_core.sv` & `rtl/cpu_top.sv`

* **Hardware Inferred:** The complete integrated datapath. Connects memories, pipeline registers, and control logic together.
* **Synthesis Note:** All memories in `cpu_top.sv` are separate from the core (Harvard Architecture), allowing simultaneous instruction fetching and data memory access in the same cycle without contention.

---

## 3. Tinkering Exercises: Try These Out!

1. **Add a `NOR` or `NAND` Instruction:**
   * Open `cpu_pkg.sv`: Add `ALU_NOR` to `alu_op_t` and `FUNCT_NOR = 3'b...` to `funct_t`.
   * Open `alu.sv`: Add `ALU_NOR: result = ~(a | b);`.
   * Open `control_unit.sv`: Map `FUNCT_NOR` to `ALU_NOR`.
   * Re-run `python sim/run_sim.py` and test it in assembly!

2. **Measure CPI (Cycles Per Instruction):**
   * Total cycles for 39 instructions was 50 cycles.
   * $CPI = 50 / 39 = 1.28$ cycles/instruction.
   * Notice how close it is to the theoretical ideal of 1.0! The only overhead comes from the initial 4-cycle pipeline fill, 1-cycle load-use bubble, and branch flushes.
