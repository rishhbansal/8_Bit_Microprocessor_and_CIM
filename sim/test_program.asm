# ============================================================================
# Comprehensive Verification Assembly Program for 8-Bit Pipelined CPU
# Covers all requirements:
# 1. Immediate loading (LDI)
# 2. Register-register arithmetic (ADD, SUB, AND, OR, XOR)
# 3. Shifts: Logical (SLL, SRL) and Signed Arithmetic (SRA)
# 4. Signed and unsigned comparisons (SLT, SLTU)
# 5. Memory load & store (LD, ST)
# 6. RAW Data Hazard with forwarding (no stall)
# 7. Load-Use Data Hazard (automatic 1-cycle stall bubble)
# 8. Control Flow: Conditional branches (taken/not-taken) & Jumps (JAL, JR, JMP)
# ============================================================================

    # -------------------------------------------------------------------------
    # Test 1: Immediate Loading (LDI)
    # -------------------------------------------------------------------------
    LDI R1, 10          # R1 = 10
    LDI R2, 20          # R2 = 20
    LDI R3, 5           # R3 = 5

    # -------------------------------------------------------------------------
    # Test 2: RAW Data Hazard Forwarding (EX->EX and MEM->EX)
    # R4 depends on R1 and R2 immediately computed above!
    # Forwarding unit should forward without any stall cycles.
    # -------------------------------------------------------------------------
    ADD R4, R1, R2      # R4 = R1 + R2 = 10 + 20 = 30
    SUB R5, R4, R3      # R5 = R4 - R3 = 30 - 5 = 25 (Back-to-back RAW!)

    # -------------------------------------------------------------------------
    # Test 3: Bitwise Operations & Shifts (Signed vs Unsigned)
    # -------------------------------------------------------------------------
    LDI R6, 0xF0        # R6 = 8'b1111_0000 (signed: -16, unsigned: 240)
    LDI R7, 2           # Shift count = 2

    # Logical Shift Right (SRL): Unsigned, inserts zeroes at MSB
    # 1111_0000 >> 2 = 0011_1100 = 0x3C (60)
    SRL R1, R6, R7      # R1 = 0x3C

    # Arithmetic Shift Right (SRA): Signed, sign-extended MSB
    # 1111_0000 >>> 2 = 1111_1100 = 0xFC (-4)
    SRA R2, R6, R7      # R2 = 0xFC

    # Shift Left Logical (SLL)
    # 0000_0101 << 2 = 0001_0100 = 20 (0x14)
    SLL R3, R3, R7      # R3 = 20

    # Bitwise Logic
    AND R1, R6, R1      # R1 = 0xF0 & 0x3C = 0x30
    OR  R2, R1, R3      # R2 = 0x30 | 0x14 = 0x34
    XOR R1, R2, R3      # R1 = 0x34 ^ 0x14 = 0x20

    # -------------------------------------------------------------------------
    # Test 4: Signed vs Unsigned Comparisons (SLT vs SLTU)
    # R6 = 0xF0 (-16 signed, 240 unsigned)
    # R3 = 20   (+20 signed, 20 unsigned)
    # -------------------------------------------------------------------------
    SLT  R4, R6, R3     # Signed: -16 < 20 is TRUE -> R4 = 1
    SLTU R5, R6, R3     # Unsigned: 240 < 20 is FALSE -> R5 = 0

    # -------------------------------------------------------------------------
    # Test 5: Memory Store and Load + Load-Use Hazard
    # Store R2 (0x34) to memory address 0x10
    # -------------------------------------------------------------------------
    LDI R7, 0x10        # Base memory address = 16
    ST  R2, [R7 + 0]    # Mem[16] = 0x34

    # Load from memory
    LD  R1, [R7 + 0]    # R1 = Mem[16] = 0x34
    # LOAD-USE HAZARD: Next instruction uses R1 immediately!
    # Hazard unit must detect this and insert exactly 1 stall bubble.
    ADDI R3, R1, 6      # R3 = R1 + 6 = 0x34 + 6 = 0x3A (58)

    # -------------------------------------------------------------------------
    # Test 6: Control Hazards (Branches and Jumps)
    # Branch Not Taken
    # -------------------------------------------------------------------------
    LDI R4, 10
    LDI R5, 20
    BEQ R4, R5, bad_branch   # 10 != 20 -> Not Taken, no flush!
    ADDI R4, R4, 5           # R4 = 15 (Correct path executed)
    JMP test_branch_taken

bad_branch:
    LDI R4, 0xEE             # Should NEVER execute
    HALT

test_branch_taken:
    # Branch Taken: must flush wrong-path instructions!
    LDI R5, 15
    BEQ R4, R5, good_branch  # 15 == 15 -> Taken!
    LDI R4, 0xAA             # Should be flushed!
    LDI R5, 0xBB             # Should be flushed!

good_branch:
    # -------------------------------------------------------------------------
    # Test 7: Subroutine Call with JAL and Return with JR
    # -------------------------------------------------------------------------
    LDI R1, 7
    JAL R7, my_subroutine    # Call subroutine, R7 holds return address
    # Return landed here!
    ADDI R1, R1, 10          # R1 = (7 * 2) + 10 = 14 + 10 = 24
    JMP program_end

my_subroutine:
    # Subroutine doubles R1: R1 = R1 + R1
    ADD R1, R1, R1           # R1 = 14
    JR  R7                   # Return to caller!

program_end:
    # Store final verification signature to memory address 0xFF
    LDI R7, 0xFE
    ST  R1, [R7 + 1]         # Mem[0xFF] = 24 (0x18)
    HALT                     # End of test execution
