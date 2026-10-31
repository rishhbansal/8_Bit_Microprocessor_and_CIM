# ISA Specification: 8-Bit Pipelined RISC Microprocessor
## Architecture Reference Manual

---

## 1. Architectural Overview

* **Data Word Width:** 8 bits
* **Instruction Width:** 16 bits (fixed length)
* **Address Space:** 256 words instruction memory (ROM), 256 bytes data memory (RAM)
* **Architecture Style:** Harvard Architecture (independent instruction and data buses)
* **Pipeline Depth:** 5 stages:
  1. **IF** - Instruction Fetch
  2. **ID** - Instruction Decode & Register Fetch
  3. **EX** - Execute / ALU / Branch Resolution / Address Generation
  4. **MEM** - Data Memory Access
  5. **WB** - Register Write-Back

---

## 2. Register File Organization

The CPU contains 8 general-purpose registers:

| Register | Name | Bit Width | Accessibility | Architectural Role |
| :--- | :--- | :--- | :--- | :--- |
| `R0` | Zero Register | 8 bits | Read-Only | Hardwired to `8'h00`. Writes to `R0` are ignored. Enables zero-cost register moves (`ADD Rd, Rs, R0`), clears, and NOPs. |
| `R1` | General / Return Val | 8 bits | Read / Write | General arithmetic, function return values. |
| `R2` - `R6` | General Purpose | 8 bits | Read / Write | Scratchpad operands, temporary values, array pointers. |
| `R7` | Link / Pointer Register | 8 bits | Read / Write | Function return address for `JAL`, general pointer. |

---

## 3. Instruction Encoding Formats

All instructions are fixed 16-bit words.

### Format 1: R-Type (Register-Register Arithmetic & Logic)
```
15        12 11     9 8       6 5       3 2       0
+-----------+--------+---------+---------+---------+
| Opcode    |   Rd   |   Rs1   |   Rs2   |  Funct  |
| 4 bits    | 3 bits | 3 bits  | 3 bits  | 3 bits  |
+-----------+--------+---------+---------+---------+
```

### Format 2: I-Type (Immediate Arithmetic & Comparisons)
```
15        12 11     9 8       6 5                 0
+-----------+--------+---------+-------------------+
| Opcode    |   Rd   |   Rs1   |    Imm6 (signed)  |
| 4 bits    | 3 bits | 3 bits  |       6 bits      |
+-----------+--------+---------+-------------------+
```

### Format 3: LDI Format (8-bit Immediate Load)
```
15        12 11     9 8                           0
+-----------+--------+-----------------------------+
| Opcode    |   Rd   |       Imm8 (unsigned/signed)|
| 4 bits    | 3 bits |             8 bits          |
+-----------+--------+-----------------------------+
```

### Format 4: Memory Format (Load / Store)
```
15        12 11     9 8       6 5                 0
+-----------+--------+---------+-------------------+
| Opcode    | Rd/Rs2 |   Rs1   |   Offset (signed) |
| 4 bits    | 3 bits | 3 bits  |       6 bits      |
+-----------+--------+---------+-------------------+
```
* For `LD`: `[11:9]` is destination register `Rd`.
* For `ST`: `[11:9]` is source data register `Rs2` (data to write into memory).

### Format 5: Branch Format (Conditional Branches)
```
15        12 11     9 8       6 5                 0
+-----------+--------+---------+-------------------+
| Opcode    |   Rs1  |   Rs2   |   Offset (signed) |
| 4 bits    | 3 bits | 3 bits  |       6 bits      |
+-----------+--------+---------+-------------------+
```
Target address = `PC + 1 + SignExt(Offset)`.

### Format 6: Jump Format (Unconditional Jumps & Links)
```
15        12 11     9 8       7                   0
+-----------+--------+---------+-------------------+
| Opcode    |   Rd   | Unused  |    Target (8-bit) |
| 4 bits    | 3 bits | 1 bit   |        8 bits     |
+-----------+--------+---------+-------------------+
```

---

## 4. Complete Instruction Set Summary

| Mnemonic | Opcode | Funct | Semantics | Description |
| :--- | :--- | :--- | :--- | :--- |
| `NOP` | `0000` | `000` | `R0 = R0 + R0` | No Operation |
| `ADD Rd, Rs1, Rs2` | `0000` | `000` | `Rd = Rs1 + Rs2` | Add registers |
| `SUB Rd, Rs1, Rs2` | `0000` | `001` | `Rd = Rs1 - Rs2` | Subtract registers |
| `AND Rd, Rs1, Rs2` | `0000` | `010` | `Rd = Rs1 & Rs2` | Bitwise AND |
| `OR  Rd, Rs1, Rs2` | `0000` | `011` | `Rd = Rs1 \| Rs2` | Bitwise OR |
| `XOR Rd, Rs1, Rs2` | `0000` | `100` | `Rd = Rs1 ^ Rs2` | Bitwise XOR |
| `SLL Rd, Rs1, Rs2` | `0000` | `101` | `Rd = Rs1 << Rs2[2:0]` | Shift Left Logical |
| `SRL Rd, Rs1, Rs2` | `0000` | `110` | `Rd = Rs1 >> Rs2[2:0]` | Shift Right Logical (unsigned) |
| `SRA Rd, Rs1, Rs2` | `0000` | `111` | `Rd = $signed(Rs1) >>> Rs2[2:0]` | Shift Right Arithmetic (signed) |
| `SLT Rd, Rs1, Rs2` | `0001` | - | `Rd = ($signed(Rs1) < $signed(Rs2)) ? 1 : 0` | Set Less Than (Signed) |
| `SLTU Rd, Rs1, Rs2`| `0010` | - | `Rd = (Rs1 < Rs2) ? 1 : 0` | Set Less Than Unsigned |
| `LDI Rd, Imm8` | `0011` | - | `Rd = Imm8` | Load 8-bit Immediate |
| `ADDI Rd, Rs1, Imm`| `0100` | - | `Rd = Rs1 + SignExt(Imm6)` | Add Immediate |
| `SUBI Rd, Rs1, Imm`| `0101` | - | `Rd = Rs1 - SignExt(Imm6)` | Subtract Immediate |
| `LD Rd, [Rs1 + off]`| `0110` | - | `Rd = Mem[Rs1 + SignExt(off)]` | Load Data from RAM |
| `ST Rs2, [Rs1 + off]`|`0111` | - | `Mem[Rs1 + SignExt(off)] = Rs2` | Store Data to RAM |
| `BEQ Rs1, Rs2, tgt`| `1000` | - | `if (Rs1 == Rs2) PC = Target` | Branch if Equal |
| `BNE Rs1, Rs2, tgt`| `1001` | - | `if (Rs1 != Rs2) PC = Target` | Branch if Not Equal |
| `BLT Rs1, Rs2, tgt`| `1010` | - | `if ($signed(Rs1) < $signed(Rs2)) PC = Target` | Branch Less Than (Signed) |
| `BGE Rs1, Rs2, tgt`| `1011` | - | `if ($signed(Rs1) >= $signed(Rs2)) PC = Target`| Branch Greater/Equal (Signed) |
| `JMP Target` | `1100` | - | `PC = Target` | Unconditional Jump |
| `JAL Rd, Target` | `1101` | - | `Rd = PC + 1, PC = Target` | Jump and Link (Call) |
| `JR Rs1` | `1110` | - | `PC = Rs1` | Jump Register (Return) |
| `HALT` | `1111` | - | Processor enters halt state | Stop execution |

---

## 5. Pipeline Latency & Hazard Timing

* **Ideal Throughput:** 1 instruction per clock cycle ($CPI = 1.0$).
* **RAW Data Hazard (Register-to-Register):** Handled via **Forwarding** (0 stall cycles).
* **Load-Use Data Hazard:** Automatically inserts **1 stall cycle** (hardware bubble).
* **Control Hazard (Branch Taken):** **2-cycle penalty** (flushes IF/ID and ID/EX).
* **Control Hazard (Branch Not Taken):** **0-cycle penalty** (execution continues sequentially).
