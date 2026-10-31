# Bonus Task: C Program to Custom ISA Mapping
## Manual Compilation, Register Allocation, and Pipeline State Tracking

This document satisfies the **Bonus Task** requirements:
1. A complete C program exercising arithmetic, array memory access, signed shifts, conditional branching, and function calling.
2. Manual line-by-line compilation into our custom 8-bit RISC assembly.
3. A detailed architectural mapping document tracking register and memory transitions across pipeline stages.

---

## 1. High-Level C Source Code

```c
// ============================================================================
// evaluation_benchmark.c
// 8-Bit Evaluation Algorithm: Vector Transform, Arithmetic & Subroutine
// ============================================================================

#define BASE_ADDR  0x10
#define OUT_ADDR   0xFF

// Function prototype: doubles a signed value
int double_val(int x) {
    return x + x;
}

void main() {
    // 1. Immediate loading & Arithmetic
    int a = 10;
    int b = 20;
    int c = 5;
    int d = a + b;       // d = 30
    int e = d - c;       // e = 25

    // 2. Signed & Unsigned Shifts
    signed char val = -16; // 0xF0
    int shift_amt = 2;
    unsigned char u_shifted = ((unsigned char)val) >> shift_amt; // 0x3C (60)
    signed char s_shifted   = val >> shift_amt;                 // 0xFC (-4)

    // 3. Logic & Memory Store
    unsigned char stored_data = (u_shifted & val) | 0x14;       // 0x34
    unsigned char *dmem = (unsigned char *)BASE_ADDR;
    dmem[0] = stored_data;                                      // Mem[0x10] = 0x34

    // 4. Memory Load & Arithmetic
    unsigned char loaded_data = dmem[0];                        // 0x34
    int result = loaded_data + 6;                               // 0x3A (58)

    // 5. Conditional Flow Control
    int x = 10, y = 20;
    if (x != y) {
        x = x + 5; // x becomes 15
    }

    if (x == 15) {
        // Correct branch taken
        int input = 7;
        int doubled = double_val(input); // doubled = 14
        result = doubled + 10;           // result = 24
    }

    // 6. Write final benchmark signature to memory
    unsigned char *out_ptr = (unsigned char *)OUT_ADDR;
    *out_ptr = (unsigned char)result; // Mem[0xFF] = 24
}
```

---

## 2. Register Allocation Convention

To compile this C program onto our 8-bit RISC core, we adopt the following ABI (Application Binary Interface):

| C Construct / Variable | Assigned Hardware Register | Purpose |
| :--- | :--- | :--- |
| Constants / Zero | `R0` | Fixed hardware zero (`8'h00`) |
| `a`, `loaded_data`, `input`, `result`, Return Val | `R1` | Primary accumulator and function argument/return register |
| `b`, `s_shifted`, `stored_data` | `R2` | General operand / intermediate variable |
| `c`, `result` (intermediate) | `R3` | General operand |
| `d`, `x` | `R4` | Scratchpad / conditional test variable |
| `e`, `y` | `R5` | Scratchpad / conditional test variable |
| `val` (-16 / `0xF0`) | `R6` | Signed test operand |
| `shift_amt`, Memory pointers, `dmem`, `out_ptr`, Return Address | `R7` | Link register for `JAL` and memory address base pointer |

---

## 3. Line-by-Line C to Assembly Compilation

| Line # | High-Level C Code | Custom Assembly Instruction | Hex Machine Code | Action / Hardware Semantic |
| :---: | :--- | :--- | :---: | :--- |
| 16 | `int a = 10;` | `LDI R1, 10` | `0x320A` | `R1 = 10` |
| 17 | `int b = 20;` | `LDI R2, 20` | `0x3414` | `R2 = 20` |
| 18 | `int c = 5;` | `LDI R3, 5` | `0x3605` | `R3 = 5` |
| 19 | `int d = a + b;` | `ADD R4, R1, R2` | `0x0850` | `R4 = 30` (EX-stage forward) |
| 20 | `int e = d - c;` | `SUB R5, R4, R3` | `0x0B19` | `R5 = 25` (EX-stage forward) |
| 23 | `signed char val = -16;` | `LDI R6, 0xF0` | `0x3CF0` | `R6 = 0xF0` |
| 24 | `int shift_amt = 2;` | `LDI R7, 2` | `0x3E02` | `R7 = 2` |
| 25 | `u_shifted = val >> 2;` | `SRL R1, R6, R7` | `0x03BE` | `R1 = 0x3C` (Unsigned shift) |
| 26 | `s_shifted = val >> 2;` | `SRA R2, R6, R7` | `0x05BF` | `R2 = 0xFC` (Signed arithmetic shift) |
| 29 | `stored_data = ...` | `OR R2, R1, R3` | `0x045B` | `R2 = 0x34` |
| 31 | `dmem[0] = stored_data;` | `LDI R7, 0x10` <br> `ST R2, [R7 + 0]` | `0x3E10` <br> `0x75C0` | `Mem[0x10] = 0x34` |
| 34 | `loaded_data = dmem[0];` | `LD R1, [R7 + 0]` | `0x63C0` | `R1 = Mem[0x10] = 0x34` |
| 35 | `result = loaded_data + 6;`| `ADDI R3, R1, 6` | `0x4646` | **Load-Use Stall inserted!** `R3 = 0x3A` |
| 38 | `if (x != y)` | `BEQ R4, R5, skip` | `0x8942` | Branch Not Taken (no stall) |
| 39 | `x = x + 5;` | `ADDI R4, R4, 5` | `0x4905` | `R4 = 15` |
| 42 | `if (x == 15)` | `BEQ R4, R5, target`| `0x8942` | **Branch Taken -> Flushes wrong path** |
| 44 | `input = 7;` | `LDI R1, 7` | `0x3207` | `R1 = 7` |
| 45 | `doubled = double_val(input);`| `JAL R7, subroutine`| `0xDE22` | Call: `R7 = PC+1`, `PC = 0x22` |
| 9-11| Subroutine `double_val` | `ADD R1, R1, R1` <br> `JR R7` | `0x0248` <br> `0xE1C0` | `R1 = 14`, Return to caller |
| 46 | `result = doubled + 10;` | `ADDI R1, R1, 10` | `0x424A` | `R1 = 24 (0x18)` |
| 50 | `*out_ptr = result;` | `LDI R7, 0xFE` <br> `ST R1, [R7 + 1]` | `0x3EFE` <br> `0x73C1` | `Mem[0xFF] = 24 (0x18)` |
| - | Execution complete | `HALT` | `0xF000` | Halts core pipeline |

---

## 4. Architectural State Transition Mapping

The following state matrix tracks how physical memory and registers transform during the benchmark execution:

| Phase | Milestone Description | Pipeline Phenomena | Architectural State Change |
| :--- | :--- | :--- | :--- |
| **Phase 1** | Immediate Loads | Normal Flow | `R1=0x0A, R2=0x14, R3=0x05` |
| **Phase 2** | Back-to-Back Arithmetic | RAW Forwarding (EX->EX) | `R4=0x1E (30), R5=0x19 (25)` with **0 stall cycles** |
| **Phase 3** | Unsigned vs Signed Shift | Barrel Shifter MSB Sign Fill | `R1=0x3C` (0-filled), `R2=0xFC` (1-filled) |
| **Phase 4** | Memory Store | Address Gen in EX, Write in MEM | `Mem[0x10] <= 0x34` |
| **Phase 5** | Memory Load-Use | **1-Cycle Stall Bubble** | PC frozen at `0x13`, ID/EX cleared to NOP |
| **Phase 6** | Branch Taken Evaluation | **Pipeline Flush** | Flushes 2 ghost instructions (`0xAA`, `0xBB`) |
| **Phase 7** | Subroutine Call & Return | Link Register `JAL` + `JR` | `R7 = return_pc`, `R1 = 14`, then `R1 = 24` |
| **Phase 8** | Final Signature Store | End of Execution | `Mem[0xFF] <= 0x18 (24)`, `halted = 1` |
