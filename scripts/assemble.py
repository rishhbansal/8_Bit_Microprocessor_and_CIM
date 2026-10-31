#!/usr/bin/env python3
"""
Custom 2-Pass Assembler for the 8-Bit Pipelined RISC Microprocessor.
Converts assembly source code (.asm) into hex memory files (.mem) for Vivado simulation and FPGA synthesis.
"""

import sys
import re
import os

OPCODES = {
    'RTYPE': 0b0000,
    'SLT'  : 0b0001,
    'SLTU' : 0b0010,
    'LDI'  : 0b0011,
    'ADDI' : 0b0100,
    'SUBI' : 0b0101,
    'LD'   : 0b0110,
    'ST'   : 0b0111,
    'BEQ'  : 0b1000,
    'BNE'  : 0b1001,
    'BLT'  : 0b1010,
    'BGE'  : 0b1011,
    'JMP'  : 0b1100,
    'JAL'  : 0b1101,
    'JR'   : 0b1110,
    'HALT' : 0b1111,
}

FUNCT_CODES = {
    'ADD': 0b000,
    'SUB': 0b001,
    'AND': 0b010,
    'OR' : 0b011,
    'XOR': 0b100,
    'SLL': 0b101,
    'SRL': 0b110,
    'SRA': 0b111,
}

def parse_reg(reg_str):
    reg_str = reg_str.strip().lower()
    if not reg_str.startswith('r'):
        raise ValueError(f"Invalid register name: {reg_str}")
    num = int(reg_str[1:])
    if not (0 <= num <= 7):
        raise ValueError(f"Register number out of bounds (0-7): {reg_str}")
    return num

def parse_val(val_str):
    val_str = val_str.strip()
    if val_str.startswith(('0x', '0X')):
        return int(val_str, 16)
    elif val_str.startswith(('0b', '0B')):
        return int(val_str, 2)
    else:
        return int(val_str, 10)

def parse_mem_operand(op_str):
    # Matches [Rs + offset], [Rs - offset], [Rs], offset(Rs)
    op_str = op_str.strip()
    m = re.match(r'\[\s*(r\d)\s*([+-]\s*\w+)?\s*\]', op_str, re.IGNORECASE)
    if m:
        base_reg = parse_reg(m.group(1))
        offset = parse_val(m.group(2).replace(' ', '')) if m.group(2) else 0
        return base_reg, offset

    m2 = re.match(r'([+-]?\w+)\s*\(\s*(r\d)\s*\)', op_str, re.IGNORECASE)
    if m2:
        offset = parse_val(m2.group(1))
        base_reg = parse_reg(m2.group(2))
        return base_reg, offset

    raise ValueError(f"Invalid memory operand syntax: {op_str}")

def tokenize_line(line):
    # Protect content inside brackets [ ... ] from being split by spaces
    line = re.sub(r'\[\s*([^\]]+?)\s*\]', lambda m: '[' + re.sub(r'\s+', '', m.group(1)) + ']', line)
    # Split by commas or whitespace
    parts = [p.strip() for p in re.split(r'[\s,]+', line) if p.strip()]
    return parts

def assemble(asm_text):
    lines = asm_text.splitlines()
    clean_lines = []
    labels = {}
    pc = 0

    # Pass 1: Strip comments, find labels, assign addresses
    for line_num, line in enumerate(lines, 1):
        line = re.sub(r'#.*|//.*', '', line).strip()
        if not line:
            continue

        # Check for label
        if ':' in line:
            parts = line.split(':', 1)
            label = parts[0].strip()
            labels[label] = pc
            line = parts[1].strip()
            if not line:
                continue

        clean_lines.append((pc, line_num, line))
        pc += 1

    # Pass 2: Generate machine code
    machine_code = []
    listing = []

    for pc, line_num, line in clean_lines:
        tokens = tokenize_line(line)
        instr = tokens[0].upper()
        args = tokens[1:]

        try:
            if instr == 'NOP':
                word = 0x0000
                desc = "NOP (ADD R0, R0, R0)"

            elif instr in FUNCT_CODES:
                # ADD Rd, Rs1, Rs2
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                funct = FUNCT_CODES[instr]
                word = (OPCODES['RTYPE'] << 12) | (rd << 9) | (rs1 << 6) | (rs2 << 3) | funct
                desc = f"{instr} R{rd}, R{rs1}, R{rs2}"

            elif instr == 'SLT':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                word = (OPCODES['SLT'] << 12) | (rd << 9) | (rs1 << 6) | (rs2 << 3)
                desc = f"SLT R{rd}, R{rs1}, R{rs2}"

            elif instr == 'SLTU':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                word = (OPCODES['SLTU'] << 12) | (rd << 9) | (rs1 << 6) | (rs2 << 3)
                desc = f"SLTU R{rd}, R{rs1}, R{rs2}"

            elif instr == 'LDI':
                rd = parse_reg(args[0])
                val = parse_val(args[1]) & 0xFF
                word = (OPCODES['LDI'] << 12) | (rd << 9) | val
                desc = f"LDI R{rd}, 0x{val:02X} ({val})"

            elif instr == 'ADDI':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                imm = parse_val(args[2]) & 0x3F # 6-bit sign-extended
                word = (OPCODES['ADDI'] << 12) | (rd << 9) | (rs1 << 6) | imm
                desc = f"ADDI R{rd}, R{rs1}, {args[2]}"

            elif instr == 'SUBI':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                imm = parse_val(args[2]) & 0x3F
                word = (OPCODES['SUBI'] << 12) | (rd << 9) | (rs1 << 6) | imm
                desc = f"SUBI R{rd}, R{rs1}, {args[2]}"

            elif instr == 'LD':
                rd = parse_reg(args[0])
                if len(args) == 2:
                    rs1, offset = parse_mem_operand(args[1])
                else:
                    rs1 = parse_reg(args[1])
                    offset = parse_val(args[2])
                word = (OPCODES['LD'] << 12) | (rd << 9) | (rs1 << 6) | (offset & 0x3F)
                desc = f"LD R{rd}, [R{rs1} + {offset}]"

            elif instr == 'ST':
                # ST Rs2, [Rs1 + offset]
                rs2 = parse_reg(args[0])
                if len(args) == 2:
                    rs1, offset = parse_mem_operand(args[1])
                else:
                    rs1 = parse_reg(args[1])
                    offset = parse_val(args[2])
                word = (OPCODES['ST'] << 12) | (rs2 << 9) | (rs1 << 6) | (offset & 0x3F)
                desc = f"ST R{rs2}, [R{rs1} + {offset}]"

            elif instr in ('BEQ', 'BNE', 'BLT', 'BGE'):
                rs1 = parse_reg(args[0])
                rs2 = parse_reg(args[1])
                target_str = args[2]
                if target_str in labels:
                    target_pc = labels[target_str]
                    offset = target_pc - (pc + 1)
                else:
                    offset = parse_val(target_str)
                offset_6b = offset & 0x3F
                word = (OPCODES[instr] << 12) | (rs1 << 9) | (rs2 << 6) | offset_6b
                desc = f"{instr} R{rs1}, R{rs2}, offset={offset}"

            elif instr == 'JMP':
                target_str = args[0]
                target_pc = labels[target_str] if target_str in labels else parse_val(target_str)
                word = (OPCODES['JMP'] << 12) | (target_pc & 0xFF)
                desc = f"JMP 0x{target_pc:02X}"

            elif instr == 'JAL':
                rd = parse_reg(args[0])
                target_str = args[1]
                target_pc = labels[target_str] if target_str in labels else parse_val(target_str)
                word = (OPCODES['JAL'] << 12) | (rd << 9) | (target_pc & 0xFF)
                desc = f"JAL R{rd}, 0x{target_pc:02X}"

            elif instr == 'JR':
                rs1 = parse_reg(args[0])
                word = (OPCODES['JR'] << 12) | (rs1 << 6)
                desc = f"JR R{rs1}"

            elif instr == 'HALT':
                word = (OPCODES['HALT'] << 12)
                desc = "HALT"

            else:
                raise ValueError(f"Unknown instruction: {instr}")

            machine_code.append(word)
            listing.append(f"0x{pc:02X} : 0x{word:04X}  # {desc}")

        except Exception as e:
            print(f"Error at line {line_num}: '{line}' -> {e}", file=sys.stderr)
            raise

    return machine_code, listing

def main():
    if len(sys.argv) < 3:
        print("Usage: assemble.py <input.asm> <output.mem> [listing.txt]")
        sys.exit(1)

    in_file = sys.argv[1]
    out_file = sys.argv[2]
    list_file = sys.argv[3] if len(sys.argv) > 3 else None

    with open(in_file, 'r') as f:
        asm_text = f.read()

    words, listing = assemble(asm_text)

    os.makedirs(os.path.dirname(os.path.abspath(out_file)), exist_ok=True)
    with open(out_file, 'w') as f:
        for w in words:
            f.write(f"{w:04X}\n")

    if list_file:
        with open(list_file, 'w') as f:
            f.write("\n".join(listing) + "\n")

    print(f"Successfully assembled {len(words)} instructions to {out_file}")

if __name__ == '__main__':
    main()
