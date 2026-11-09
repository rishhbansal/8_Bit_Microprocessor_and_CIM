#!/usr/bin/env python3
"""
Cycle-Accurate 5-Stage Pipelined Simulator for the 8-Bit RISC CPU.
Models IF, ID, EX, MEM, WB pipeline stages, RAW forwarding, Load-Use stalls,
and control hazard flushes. Verifies functional correctness from first principles.
"""

import sys
import os

OPCODES = {
    0x0: 'RTYPE',
    0x1: 'SLT',
    0x2: 'SLTU',
    0x3: 'LDI',
    0x4: 'ADDI',
    0x5: 'SUBI',
    0x6: 'LD',
    0x7: 'ST',
    0x8: 'BEQ',
    0x9: 'BNE',
    0xA: 'BLT',
    0xB: 'BGE',
    0xC: 'JMP',
    0xD: 'JAL',
    0xE: 'JR',
    0xF: 'HALT'
}

FUNCT_NAMES = {
    0: 'ADD', 1: 'SUB', 2: 'AND', 3: 'OR', 4: 'XOR', 5: 'SLL', 6: 'SRL', 7: 'SRA'
}

def to_signed8(val):
    val = val & 0xFF
    return val - 256 if val >= 128 else val

class PipelineSimulator:
    def __init__(self, mem_file):
        self.imem = [0] * 256
        self.dmem = [0] * 256
        self.regs = [0] * 8
        self.pc = 0

        # Pipeline Registers (dict holding stage state)
        self.if_id = {'valid': False, 'pc': 0, 'instr': 0}
        self.id_ex = {'valid': False, 'pc': 0, 'op': 'NOP', 'rd': 0, 'rs1': 0, 'rs2': 0,
                      'val1': 0, 'val2': 0, 'imm': 0, 'mem_read': False, 'mem_write': False,
                      'reg_write': False, 'mem_to_reg': False, 'is_jump': False, 'is_jal': False,
                      'is_jr': False, 'is_halt': False}
        self.ex_mem = {'valid': False, 'pc': 0, 'rd': 0, 'alu_res': 0, 'store_data': 0,
                       'reg_write': False, 'mem_read': False, 'mem_write': False,
                       'mem_to_reg': False, 'is_jal': False, 'is_halt': False}
        self.mem_wb = {'valid': False, 'pc': 0, 'rd': 0, 'wb_data': 0, 'reg_write': False,
                       'is_halt': False}

        self.cycle = 0
        self.halted = False
        self.load_imem(mem_file)

    def load_imem(self, mem_file):
        if not os.path.exists(mem_file):
            raise FileNotFoundError(f"Instruction memory file not found: {os.path.abspath(mem_file)}")
        with open(mem_file, 'r') as f:
            for idx, line in enumerate(f):
                line = line.strip()
                if line and idx < 256:
                    self.imem[idx] = int(line, 16)

    def step(self):
        self.cycle += 1

        # -------------------------------------------------------------
        # 1. WRITE-BACK (WB) STAGE
        # -------------------------------------------------------------
        if self.mem_wb['valid'] and self.mem_wb['reg_write'] and self.mem_wb['rd'] != 0:
            self.regs[self.mem_wb['rd']] = self.mem_wb['wb_data'] & 0xFF

        if self.mem_wb['valid'] and self.mem_wb['is_halt']:
            self.halted = True
            return

        # -------------------------------------------------------------
        # 2. MEMORY (MEM) STAGE -> Prepare MEM/WB
        # -------------------------------------------------------------
        next_mem_wb = {'valid': False, 'rd': 0, 'wb_data': 0, 'reg_write': False, 'is_halt': False}
        if self.ex_mem['valid']:
            next_mem_wb['valid'] = True
            next_mem_wb['rd'] = self.ex_mem['rd']
            next_mem_wb['reg_write'] = self.ex_mem['reg_write']
            next_mem_wb['is_halt'] = self.ex_mem['is_halt']

            if self.ex_mem['is_jal']:
                next_mem_wb['wb_data'] = (self.ex_mem['pc'] + 1) & 0xFF
            elif self.ex_mem['mem_read']:
                addr = self.ex_mem['alu_res'] & 0xFF
                next_mem_wb['wb_data'] = self.dmem[addr]
            else:
                next_mem_wb['wb_data'] = self.ex_mem['alu_res'] & 0xFF

            if self.ex_mem['mem_write']:
                addr = self.ex_mem['alu_res'] & 0xFF
                self.dmem[addr] = self.ex_mem['store_data'] & 0xFF

        # -------------------------------------------------------------
        # 3. EXECUTE (EX) STAGE -> Prepare EX/MEM
        # -------------------------------------------------------------
        next_ex_mem = {'valid': False, 'pc': 0, 'rd': 0, 'alu_res': 0, 'store_data': 0,
                       'reg_write': False, 'mem_read': False, 'mem_write': False,
                       'mem_to_reg': False, 'is_jal': False, 'is_halt': False}

        branch_taken = False
        branch_target = 0
        is_jump = False
        jump_target = 0

        if self.id_ex['valid']:
            # Forwarding logic for Operand A
            fwd_a = self.id_ex['val1']
            if self.ex_mem['valid'] and self.ex_mem['reg_write'] and self.ex_mem['rd'] != 0 and self.ex_mem['rd'] == self.id_ex['rs1']:
                fwd_a = (self.ex_mem['pc'] + 1) if self.ex_mem['is_jal'] else self.ex_mem['alu_res']
            elif self.mem_wb['valid'] and self.mem_wb['reg_write'] and self.mem_wb['rd'] != 0 and self.mem_wb['rd'] == self.id_ex['rs1']:
                fwd_a = self.mem_wb['wb_data']

            # Forwarding logic for Operand B
            fwd_b = self.id_ex['val2']
            if self.ex_mem['valid'] and self.ex_mem['reg_write'] and self.ex_mem['rd'] != 0 and self.ex_mem['rd'] == self.id_ex['rs2']:
                fwd_b = (self.ex_mem['pc'] + 1) if self.ex_mem['is_jal'] else self.ex_mem['alu_res']
            elif self.mem_wb['valid'] and self.mem_wb['reg_write'] and self.mem_wb['rd'] != 0 and self.mem_wb['rd'] == self.id_ex['rs2']:
                fwd_b = self.mem_wb['wb_data']

            alu_in_a = fwd_a & 0xFF
            alu_in_b = self.id_ex['imm'] if self.id_ex['alu_src'] else fwd_b & 0xFF
            alu_res = 0

            op = self.id_ex['op']
            if op == 'ADD':
                alu_res = (alu_in_a + alu_in_b) & 0xFF
            elif op == 'SUB':
                alu_res = (alu_in_a - alu_in_b) & 0xFF
            elif op == 'AND':
                alu_res = (alu_in_a & alu_in_b) & 0xFF
            elif op == 'OR':
                alu_res = (alu_in_a | alu_in_b) & 0xFF
            elif op == 'XOR':
                alu_res = (alu_in_a ^ alu_in_b) & 0xFF
            elif op == 'SLL':
                alu_res = (alu_in_a << (alu_in_b & 0x7)) & 0xFF
            elif op == 'SRL':
                alu_res = (alu_in_a >> (alu_in_b & 0x7)) & 0xFF
            elif op == 'SRA':
                sa = alu_in_b & 0x7
                s_val = to_signed8(alu_in_a)
                alu_res = (s_val >> sa) & 0xFF
            elif op == 'SLT':
                alu_res = 1 if to_signed8(alu_in_a) < to_signed8(alu_in_b) else 0
            elif op == 'SLTU':
                alu_res = 1 if alu_in_a < alu_in_b else 0
            elif op == 'PASS_B':
                alu_res = alu_in_b & 0xFF

            # Branch evaluation
            if self.id_ex['branch_type'] == 'BEQ':
                branch_taken = (alu_in_a == (fwd_b & 0xFF))
            elif self.id_ex['branch_type'] == 'BNE':
                branch_taken = (alu_in_a != (fwd_b & 0xFF))
            elif self.id_ex['branch_type'] == 'BLT':
                branch_taken = (to_signed8(alu_in_a) < to_signed8(fwd_b & 0xFF))
            elif self.id_ex['branch_type'] == 'BGE':
                branch_taken = (to_signed8(alu_in_a) >= to_signed8(fwd_b & 0xFF))

            if branch_taken:
                branch_target = (self.id_ex['pc'] + 1 + self.id_ex['imm']) & 0xFF

            if self.id_ex['is_jump']:
                is_jump = True
                jump_target = alu_in_a if self.id_ex['is_jr'] else self.id_ex['imm'] & 0xFF

            next_ex_mem['valid'] = True
            next_ex_mem['pc'] = self.id_ex['pc']
            next_ex_mem['rd'] = self.id_ex['rd']
            next_ex_mem['alu_res'] = alu_res
            next_ex_mem['store_data'] = fwd_b & 0xFF
            next_ex_mem['reg_write'] = self.id_ex['reg_write']
            next_ex_mem['mem_read'] = self.id_ex['mem_read']
            next_ex_mem['mem_write'] = self.id_ex['mem_write']
            next_ex_mem['mem_to_reg'] = self.id_ex['mem_to_reg']
            next_ex_mem['is_jal'] = self.id_ex['is_jal']
            next_ex_mem['is_halt'] = self.id_ex['is_halt']

        # -------------------------------------------------------------
        # 4. INSTRUCTION DECODE (ID) STAGE & HAZARD DETECTION
        # -------------------------------------------------------------
        stall = False
        control_hazard = branch_taken or is_jump

        if self.if_id['valid']:
            raw_instr = self.if_id['instr']
            opcode_num = (raw_instr >> 12) & 0xF
            op_name = OPCODES.get(opcode_num, 'UNKNOWN')

            funct = raw_instr & 0x7
            rd = (raw_instr >> 9) & 0x7

            if op_name in ['BEQ', 'BNE', 'BLT', 'BGE']:
                rs1 = (raw_instr >> 9) & 0x7
                rs2 = (raw_instr >> 6) & 0x7
            elif op_name == 'ST':
                rs2 = (raw_instr >> 9) & 0x7
                rs1 = (raw_instr >> 6) & 0x7
            else:
                rs1 = (raw_instr >> 6) & 0x7
                rs2 = (raw_instr >> 3) & 0x7

            # Sign-extended 6-bit immediate
            imm6 = raw_instr & 0x3F
            if imm6 & 0x20:
                imm6 -= 64

            # Usage flags for load-use check
            uses_rs1 = op_name in ['RTYPE', 'SLT', 'SLTU', 'ADDI', 'SUBI', 'LD', 'ST', 'BEQ', 'BNE', 'BLT', 'BGE', 'JR']
            uses_rs2 = op_name in ['RTYPE', 'SLT', 'SLTU', 'ST', 'BEQ', 'BNE', 'BLT', 'BGE']

            # Load-Use hazard detection
            if self.id_ex['valid'] and self.id_ex['mem_read'] and self.id_ex['rd'] != 0:
                if (uses_rs1 and rs1 == self.id_ex['rd']) or (uses_rs2 and rs2 == self.id_ex['rd']):
                    stall = True

        next_id_ex = {'valid': False, 'pc': 0, 'op': 'NOP', 'rd': 0, 'rs1': 0, 'rs2': 0,
                      'val1': 0, 'val2': 0, 'imm': 0, 'mem_read': False, 'mem_write': False,
                      'reg_write': False, 'mem_to_reg': False, 'alu_src': False,
                      'branch_type': 'NONE', 'is_jump': False, 'is_jal': False, 'is_jr': False,
                      'is_halt': False}

        if not stall and not control_hazard and self.if_id['valid']:
            next_id_ex['valid'] = True
            next_id_ex['pc'] = self.if_id['pc']
            next_id_ex['rs1'] = rs1
            next_id_ex['rs2'] = rs2
            next_id_ex['rd'] = rd

            # Internal forwarding WB-to-ID
            val1 = self.regs[rs1] if rs1 != 0 else 0
            if next_mem_wb['valid'] and next_mem_wb['reg_write'] and next_mem_wb['rd'] != 0 and next_mem_wb['rd'] == rs1:
                val1 = next_mem_wb['wb_data']

            val2 = self.regs[rs2] if rs2 != 0 else 0
            if next_mem_wb['valid'] and next_mem_wb['reg_write'] and next_mem_wb['rd'] != 0 and next_mem_wb['rd'] == rs2:
                val2 = next_mem_wb['wb_data']

            next_id_ex['val1'] = val1
            next_id_ex['val2'] = val2

            if op_name == 'RTYPE':
                next_id_ex['op'] = FUNCT_NAMES.get(funct, 'ADD')
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'SLT':
                next_id_ex['op'] = 'SLT'
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'SLTU':
                next_id_ex['op'] = 'SLTU'
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'LDI':
                next_id_ex['op'] = 'PASS_B'
                next_id_ex['alu_src'] = True
                next_id_ex['imm'] = raw_instr & 0xFF
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'ADDI':
                next_id_ex['op'] = 'ADD'
                next_id_ex['alu_src'] = True
                next_id_ex['imm'] = imm6
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'SUBI':
                next_id_ex['op'] = 'SUB'
                next_id_ex['alu_src'] = True
                next_id_ex['imm'] = imm6
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'LD':
                next_id_ex['op'] = 'ADD'
                next_id_ex['alu_src'] = True
                next_id_ex['imm'] = imm6
                next_id_ex['mem_read'] = True
                next_id_ex['mem_to_reg'] = True
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'ST':
                next_id_ex['op'] = 'ADD'
                next_id_ex['alu_src'] = True
                next_id_ex['imm'] = imm6
                next_id_ex['mem_write'] = True
            elif op_name in ['BEQ', 'BNE', 'BLT', 'BGE']:
                next_id_ex['branch_type'] = op_name
                next_id_ex['imm'] = imm6
            elif op_name == 'JMP':
                next_id_ex['is_jump'] = True
                next_id_ex['imm'] = raw_instr & 0xFF
            elif op_name == 'JAL':
                next_id_ex['is_jump'] = True
                next_id_ex['is_jal'] = True
                next_id_ex['imm'] = raw_instr & 0xFF
                next_id_ex['reg_write'] = (rd != 0)
            elif op_name == 'JR':
                next_id_ex['is_jump'] = True
                next_id_ex['is_jr'] = True
            elif op_name == 'HALT':
                next_id_ex['is_halt'] = True

        # -------------------------------------------------------------
        # 5. INSTRUCTION FETCH (IF) STAGE
        # -------------------------------------------------------------
        if control_hazard:
            self.if_id = {'valid': False, 'pc': 0, 'instr': 0}
            if branch_taken:
                self.pc = branch_target
            else:
                self.pc = jump_target
        elif stall:
            # Keep if_id and PC unchanged
            pass
        else:
            fetched_instr = self.imem[self.pc]
            self.if_id = {'valid': True, 'pc': self.pc, 'instr': fetched_instr}
            self.pc = (self.pc + 1) & 0xFF

        # Advance pipeline stage registers
        self.mem_wb = next_mem_wb
        self.ex_mem = next_ex_mem
        self.id_ex = next_id_ex

    def print_trace(self):
        reg_str = " ".join([f"R{i}:{self.regs[i]:02X}" for i in range(1, 8)])
        print(f"Cycle {self.cycle:3d} | PC:{self.pc:02X} | {reg_str}")

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_mem = os.path.join(script_dir, "program.mem")
    mem_file = sys.argv[1] if len(sys.argv) > 1 else default_mem
    sim = PipelineSimulator(mem_file)
    print("=" * 70)
    print("STARTING CYCLE-ACCURATE 5-STAGE PIPELINE SIMULATION")
    print("=" * 70)

    for _ in range(150):
        sim.step()
        sim.print_trace()
        if sim.halted:
            break

    print("\n" + "=" * 70)
    print("SIMULATION COMPLETED!")
    print(f"Total Cycles: {sim.cycle}")
    print("Final Registers:")
    for i in range(8):
        print(f"  R{i} = 0x{sim.regs[i]:02X} ({sim.regs[i]})")
    print("\nKey Memory Locations:")
    print(f"  Mem[0x10] = 0x{sim.dmem[0x10]:02X} (Expected: 0x34)")
    print(f"  Mem[0xFF] = 0x{sim.dmem[0xFF]:02X} (Expected: 0x18 / 24)")

    # Assertions
    assert sim.dmem[0x10] == 0x34, "Store to 0x10 failed!"
    assert sim.dmem[0xFF] == 24, "Final calculation at 0xFF failed!"
    assert sim.regs[1] == 24, "R1 final calculation failed!"
    print("\n>>> ALL SIMULATION ASSERTIONS PASSED PERFECTLY! <<<")
    print("=" * 70)

if __name__ == '__main__':
    main()
