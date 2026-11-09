// ============================================================================
// File: evaluation_benchmark.c
// Project: 8-Bit Pipelined RISC Microprocessor
// Description: Benchmark algorithm exercising vector transform, signed arithmetic,
//              memory load/store, conditional branching, and subroutine calling.
// ============================================================================

#define BASE_ADDR  0x10
#define OUT_ADDR   0xFF

// Subroutine: Doubles an input value (exercised via JAL / JR)
int double_val(int x) {
    return x + x;
}

void main() {
    // ------------------------------------------------------------------------
    // Test 1: Immediate Loading & Multi-Stage Arithmetic
    // ------------------------------------------------------------------------
    int a = 10;
    int b = 20;
    int c = 5;
    int d = a + b;       // d = 30  (Tests EX-to-EX RAW Forwarding)
    int e = d - c;       // e = 25  (Tests MEM-to-EX RAW Forwarding)

    // ------------------------------------------------------------------------
    // Test 2: Signed (SRA) vs. Unsigned (SRL) Barrel Shifting
    // ------------------------------------------------------------------------
    signed char val = -16; // 0xF0 (Two's complement negative number)
    int shift_amt = 2;
    unsigned char u_shifted = ((unsigned char)val) >> shift_amt; // 0x3C (60)  - Logical shift (zeros in)
    signed char   s_shifted = val >> shift_amt;                 // 0xFC (-4)  - Arithmetic shift (sign preserved)

    // ------------------------------------------------------------------------
    // Test 3: Bitwise Logic & Memory Store (ST)
    // ------------------------------------------------------------------------
    unsigned char stored_data = (u_shifted & val) | 0x14;       // (0x3C & 0xF0) | 0x14 = 0x34 (52)
    unsigned char *dmem = (unsigned char *)BASE_ADDR;
    dmem[0] = stored_data;                                      // Mem[0x10] = 0x34

    // ------------------------------------------------------------------------
    // Test 4: Memory Load (LD) & Load-Use Hazard Stall
    // ------------------------------------------------------------------------
    unsigned char loaded_data = dmem[0];                        // 0x34
    int result = loaded_data + 6;                               // 0x3A (58) - Forces 1-cycle hardware bubble!

    // ------------------------------------------------------------------------
    // Test 5: Conditional Branching (BEQ / BNE)
    // ------------------------------------------------------------------------
    int x = 10, y = 20;
    if (x != y) {
        x = x + 5; // x becomes 15 (Tests BNE not-equal path)
    }

    if (x == 15) {
        // Correct branch taken (Tests BEQ taken path + 2-cycle flush)
        int input = 7;
        int doubled = double_val(input); // doubled = 14 (Tests JAL / JR subroutine linkage)
        result = doubled + 10;           // result = 24
    }

    // ------------------------------------------------------------------------
    // Test 6: Final Benchmark Signature Write
    // ------------------------------------------------------------------------
    unsigned char *out_ptr = (unsigned char *)OUT_ADDR;
    *out_ptr = (unsigned char)result; // Mem[0xFF] = 0x18 (24)
}
