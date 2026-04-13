# Glossary (plain-language terms for this module):
# - Opcode: Numeric instruction byte read by CPU (for example 0xA9 for LDA immediate).
# - Decode table: Lookup array that maps opcode to handler function and timing metadata.
# - Cycle count: How many CPU clock cycles one instruction normally costs.
# - Page boundary penalty: Extra cycle charged when indexed access crosses 256-byte page.
# - RMW instruction: Read-Modify-Write operation that reads memory, changes value, writes back.
# - Handler function: Small routine that performs one concrete instruction behavior.
# - Timing metadata: Extra information needed to emulate hardware pacing correctly.
# - Illegal/Unofficial opcode: Real 6502 byte patterns not in official docs but used by some games.
# - Instruction matrix: Full mapping of all 256 opcode values (0x00..0xFF).
# - Branch instruction: Instruction that conditionally jumps based on flags.
# - Addressing selection: How instruction decides where operand comes from.
# NESdev references:
# - https://www.nesdev.org/wiki/CPU_unofficial_opcodes
# - https://www.nesdev.org/wiki/Cycle_reference_chart

# IDE Static Analysis Hints
if not "CPU6502" in globals():
    from cpu cimport *
    
    # AddressingModes (defined in cpu_addressing_modes.pyx)
    from cpu cimport AddressingMode, NONE, DIRECT, IMMEDIATE, ZEROPAGE, ABSOLUTE, ZEROPAGEX, ZEROPAGEY, ABSOLUTEX, ABSOLUTEY, INDIRECTX, INDIRECTY


cdef struct OpcodeDef:
    AddressingMode mode
    int cycles
    bint page_boundary
    bint rmw

ctypedef void (*OpcodeHandler)(CPU6502)

cdef OpcodeHandler opcode_table[256]
cdef OpcodeDef opcode_defs[256]

cdef void init_opcodes():
    # This initializer is the heart of instruction decoding:
    # 1) opcode_table[byte] points to the function that executes behavior.
    # 2) opcode_defs[byte] stores timing/addressing details for that same byte.
    # Keeping these two arrays aligned makes execution fast and deterministic.
    global opcode_table, opcode_defs
    # Calls, returns, stack and register transfer instructions.
    opcode_table[0x20] = op_JSR; opcode_defs[0x20] = OpcodeDef(mode=ABSOLUTE, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x40] = op_RTI; opcode_defs[0x40] = OpcodeDef(mode=NONE, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x60] = op_RTS; opcode_defs[0x60] = OpcodeDef(mode=NONE, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0xC8] = op_INY; opcode_defs[0xC8] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x88] = op_DEY; opcode_defs[0x88] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xE8] = op_INX; opcode_defs[0xE8] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xCA] = op_DEX; opcode_defs[0xCA] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0xA8] = op_TAY; opcode_defs[0xA8] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x98] = op_TYA; opcode_defs[0x98] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xAA] = op_TAX; opcode_defs[0xAA] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0x8A] = op_TXA; opcode_defs[0x8A] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0xBA] = op_TSX; opcode_defs[0xBA] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x9A] = op_TXS; opcode_defs[0x9A] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0x08] = op_PHP; opcode_defs[0x08] = OpcodeDef(mode=NONE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x28] = op_PLP; opcode_defs[0x28] = OpcodeDef(mode=NONE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x68] = op_PLA; opcode_defs[0x68] = OpcodeDef(mode=NONE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x48] = op_PHA; opcode_defs[0x48] = OpcodeDef(mode=NONE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x24] = op_BIT; opcode_defs[0x24] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x2C] = op_BIT; opcode_defs[0x2C] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x4C] = op_JMP; opcode_defs[0x4C] = OpcodeDef(mode=ABSOLUTE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x6C] = op_JMP; opcode_defs[0x6C] = OpcodeDef(mode=ABSOLUTE, cycles=5, page_boundary=False, rmw=False)
    opcode_table[0xB0] = op_BCS; opcode_defs[0xB0] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x90] = op_BCC; opcode_defs[0x90] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xF0] = op_BEQ; opcode_defs[0xF0] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xD0] = op_BNE; opcode_defs[0xD0] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x70] = op_BVS; opcode_defs[0x70] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x50] = op_BVC; opcode_defs[0x50] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x10] = op_BPL; opcode_defs[0x10] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x30] = op_BMI; opcode_defs[0x30] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x81] = op_STA; opcode_defs[0x81] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x91] = op_STA; opcode_defs[0x91] = OpcodeDef(mode=INDIRECTY, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x95] = op_STA; opcode_defs[0x95] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x99] = op_STA; opcode_defs[0x99] = OpcodeDef(mode=ABSOLUTEY, cycles=5, page_boundary=False, rmw=False)
    opcode_table[0x9D] = op_STA; opcode_defs[0x9D] = OpcodeDef(mode=ABSOLUTEX, cycles=5, page_boundary=False, rmw=False)
    opcode_table[0x85] = op_STA; opcode_defs[0x85] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x8D] = op_STA; opcode_defs[0x8D] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x96] = op_STX; opcode_defs[0x96] = OpcodeDef(mode=ZEROPAGEY, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x86] = op_STX; opcode_defs[0x86] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x8E] = op_STX; opcode_defs[0x8E] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x94] = op_STY; opcode_defs[0x94] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x84] = op_STY; opcode_defs[0x84] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x8C] = op_STY; opcode_defs[0x8C] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x18] = op_CLC; opcode_defs[0x18] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x38] = op_SEC; opcode_defs[0x38] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x58] = op_CLI; opcode_defs[0x58] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x78] = op_SEI; opcode_defs[0x78] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xB8] = op_CLV; opcode_defs[0xB8] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xD8] = op_CLD; opcode_defs[0xD8] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xF8] = op_SED; opcode_defs[0xF8] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xEA] = op_NOP; opcode_defs[0xEA] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x1A] = op_NOP; opcode_defs[0x1A] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x3A] = op_NOP; opcode_defs[0x3A] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x5A] = op_NOP; opcode_defs[0x5A] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x7A] = op_NOP; opcode_defs[0x7A] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xDA] = op_NOP; opcode_defs[0xDA] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xFA] = op_NOP; opcode_defs[0xFA] = OpcodeDef(mode=NONE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xA1] = op_LDA; opcode_defs[0xA1] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0xA5] = op_LDA; opcode_defs[0xA5] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0xA9] = op_LDA; opcode_defs[0xA9] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xAD] = op_LDA; opcode_defs[0xAD] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xB1] = op_LDA; opcode_defs[0xB1] = OpcodeDef(mode=INDIRECTY, cycles=5, page_boundary=True, rmw=False)
    opcode_table[0xB5] = op_LDA; opcode_defs[0xB5] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xB9] = op_LDA; opcode_defs[0xB9] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0xBD] = op_LDA; opcode_defs[0xBD] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0xA0] = op_LDY; opcode_defs[0xA0] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xA4] = op_LDY; opcode_defs[0xA4] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0xAC] = op_LDY; opcode_defs[0xAC] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xB4] = op_LDY; opcode_defs[0xB4] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xBC] = op_LDY; opcode_defs[0xBC] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0xA2] = op_LDX; opcode_defs[0xA2] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0xA6] = op_LDX; opcode_defs[0xA6] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=True)
    opcode_table[0xAE] = op_LDX; opcode_defs[0xAE] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=True)
    opcode_table[0xB6] = op_LDX; opcode_defs[0xB6] = OpcodeDef(mode=ZEROPAGEY, cycles=4, page_boundary=False, rmw=True)
    opcode_table[0xBE] = op_LDX; opcode_defs[0xBE] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=True)
    opcode_table[0x01] = op_ORA; opcode_defs[0x01] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x05] = op_ORA; opcode_defs[0x05] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x09] = op_ORA; opcode_defs[0x09] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x0D] = op_ORA; opcode_defs[0x0D] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x11] = op_ORA; opcode_defs[0x11] = OpcodeDef(mode=INDIRECTY, cycles=5, page_boundary=True, rmw=False)
    opcode_table[0x15] = op_ORA; opcode_defs[0x15] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x19] = op_ORA; opcode_defs[0x19] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x1D] = op_ORA; opcode_defs[0x1D] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x21] = op_AND; opcode_defs[0x21] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x25] = op_AND; opcode_defs[0x25] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x29] = op_AND; opcode_defs[0x29] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x2D] = op_AND; opcode_defs[0x2D] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x31] = op_AND; opcode_defs[0x31] = OpcodeDef(mode=INDIRECTY, cycles=5, page_boundary=True, rmw=False)
    opcode_table[0x35] = op_AND; opcode_defs[0x35] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x39] = op_AND; opcode_defs[0x39] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x3D] = op_AND; opcode_defs[0x3D] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x41] = op_EOR; opcode_defs[0x41] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x45] = op_EOR; opcode_defs[0x45] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x49] = op_EOR; opcode_defs[0x49] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x4D] = op_EOR; opcode_defs[0x4D] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x51] = op_EOR; opcode_defs[0x51] = OpcodeDef(mode=INDIRECTY, cycles=5, page_boundary=True, rmw=False)
    opcode_table[0x55] = op_EOR; opcode_defs[0x55] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x59] = op_EOR; opcode_defs[0x59] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x5D] = op_EOR; opcode_defs[0x5D] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0xE1] = op_SBC; opcode_defs[0xE1] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0xE5] = op_SBC; opcode_defs[0xE5] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0xE9] = op_SBC; opcode_defs[0xE9] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xEB] = op_SBC; opcode_defs[0xEB] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xED] = op_SBC; opcode_defs[0xED] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xF1] = op_SBC; opcode_defs[0xF1] = OpcodeDef(mode=INDIRECTY, cycles=5, page_boundary=True, rmw=False)
    opcode_table[0xF5] = op_SBC; opcode_defs[0xF5] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xF9] = op_SBC; opcode_defs[0xF9] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0xFD] = op_SBC; opcode_defs[0xFD] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x61] = op_ADC; opcode_defs[0x61] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0x65] = op_ADC; opcode_defs[0x65] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0x69] = op_ADC; opcode_defs[0x69] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x6D] = op_ADC; opcode_defs[0x6D] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x71] = op_ADC; opcode_defs[0x71] = OpcodeDef(mode=INDIRECTY, cycles=5, page_boundary=True, rmw=False)
    opcode_table[0x75] = op_ADC; opcode_defs[0x75] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x79] = op_ADC; opcode_defs[0x79] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x7D] = op_ADC; opcode_defs[0x7D] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0x00] = op_BRK; opcode_defs[0x00] = OpcodeDef(mode=NONE, cycles=7, page_boundary=False, rmw=False)
    opcode_table[0xC1] = op_CMP; opcode_defs[0xC1] = OpcodeDef(mode=INDIRECTX, cycles=6, page_boundary=False, rmw=False)
    opcode_table[0xC5] = op_CMP; opcode_defs[0xC5] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0xC9] = op_CMP; opcode_defs[0xC9] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xCD] = op_CMP; opcode_defs[0xCD] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xD1] = op_CMP; opcode_defs[0xD1] = OpcodeDef(mode=INDIRECTY, cycles=5, page_boundary=True, rmw=False)
    opcode_table[0xD5] = op_CMP; opcode_defs[0xD5] = OpcodeDef(mode=ZEROPAGEX, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xD9] = op_CMP; opcode_defs[0xD9] = OpcodeDef(mode=ABSOLUTEY, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0xDD] = op_CMP; opcode_defs[0xDD] = OpcodeDef(mode=ABSOLUTEX, cycles=4, page_boundary=True, rmw=False)
    opcode_table[0xE0] = op_CPX; opcode_defs[0xE0] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xE4] = op_CPX; opcode_defs[0xE4] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0xEC] = op_CPX; opcode_defs[0xEC] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0xC0] = op_CPY; opcode_defs[0xC0] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xC4] = op_CPY; opcode_defs[0xC4] = OpcodeDef(mode=ZEROPAGE, cycles=3, page_boundary=False, rmw=False)
    opcode_table[0xCC] = op_CPY; opcode_defs[0xCC] = OpcodeDef(mode=ABSOLUTE, cycles=4, page_boundary=False, rmw=False)
    opcode_table[0x46] = op_LSR; opcode_defs[0x46] = OpcodeDef(mode=ZEROPAGE, cycles=5, page_boundary=False, rmw=True)
    opcode_table[0x4E] = op_LSR; opcode_defs[0x4E] = OpcodeDef(mode=ABSOLUTE, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x56] = op_LSR; opcode_defs[0x56] = OpcodeDef(mode=ZEROPAGEX, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x5E] = op_LSR; opcode_defs[0x5E] = OpcodeDef(mode=ABSOLUTEX, cycles=7, page_boundary=False, rmw=True)
    opcode_table[0x4A] = op_LSR; opcode_defs[0x4A] = OpcodeDef(mode=DIRECT, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0x06] = op_ASL; opcode_defs[0x06] = OpcodeDef(mode=ZEROPAGE, cycles=5, page_boundary=False, rmw=True)
    opcode_table[0x0E] = op_ASL; opcode_defs[0x0E] = OpcodeDef(mode=ABSOLUTE, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x16] = op_ASL; opcode_defs[0x16] = OpcodeDef(mode=ZEROPAGEX, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x1E] = op_ASL; opcode_defs[0x1E] = OpcodeDef(mode=ABSOLUTEX, cycles=7, page_boundary=False, rmw=True)
    opcode_table[0x0A] = op_ASL; opcode_defs[0x0A] = OpcodeDef(mode=DIRECT, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0x66] = op_ROR; opcode_defs[0x66] = OpcodeDef(mode=ZEROPAGE, cycles=5, page_boundary=False, rmw=True)
    opcode_table[0x6E] = op_ROR; opcode_defs[0x6E] = OpcodeDef(mode=ABSOLUTE, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x76] = op_ROR; opcode_defs[0x76] = OpcodeDef(mode=ZEROPAGEX, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x7E] = op_ROR; opcode_defs[0x7E] = OpcodeDef(mode=ABSOLUTEX, cycles=7, page_boundary=False, rmw=True)
    opcode_table[0x6A] = op_ROR; opcode_defs[0x6A] = OpcodeDef(mode=DIRECT, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0x26] = op_ROL; opcode_defs[0x26] = OpcodeDef(mode=ZEROPAGE, cycles=5, page_boundary=False, rmw=True)
    opcode_table[0x2E] = op_ROL; opcode_defs[0x2E] = OpcodeDef(mode=ABSOLUTE, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x36] = op_ROL; opcode_defs[0x36] = OpcodeDef(mode=ZEROPAGEX, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0x3E] = op_ROL; opcode_defs[0x3E] = OpcodeDef(mode=ABSOLUTEX, cycles=7, page_boundary=False, rmw=True)
    opcode_table[0x2A] = op_ROL; opcode_defs[0x2A] = OpcodeDef(mode=DIRECT, cycles=2, page_boundary=False, rmw=True)
    opcode_table[0xE6] = op_INC; opcode_defs[0xE6] = OpcodeDef(mode=ZEROPAGE, cycles=5, page_boundary=False, rmw=True)
    opcode_table[0xEE] = op_INC; opcode_defs[0xEE] = OpcodeDef(mode=ABSOLUTE, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0xF6] = op_INC; opcode_defs[0xF6] = OpcodeDef(mode=ZEROPAGEX, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0xFE] = op_INC; opcode_defs[0xFE] = OpcodeDef(mode=ABSOLUTEX, cycles=7, page_boundary=False, rmw=True)
    opcode_table[0xC6] = op_DEC; opcode_defs[0xC6] = OpcodeDef(mode=ZEROPAGE, cycles=5, page_boundary=False, rmw=True)
    opcode_table[0xCE] = op_DEC; opcode_defs[0xCE] = OpcodeDef(mode=ABSOLUTE, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0xD6] = op_DEC; opcode_defs[0xD6] = OpcodeDef(mode=ZEROPAGEX, cycles=6, page_boundary=False, rmw=True)
    opcode_table[0xDE] = op_DEC; opcode_defs[0xDE] = OpcodeDef(mode=ABSOLUTEX, cycles=7, page_boundary=False, rmw=True)
    opcode_table[0x80] = op_SKB; opcode_defs[0x80] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x82] = op_SKB; opcode_defs[0x82] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x89] = op_SKB; opcode_defs[0x89] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xC2] = op_SKB; opcode_defs[0xC2] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xE2] = op_SKB; opcode_defs[0xE2] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x0B] = op_ANC; opcode_defs[0x0B] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x2B] = op_ANC; opcode_defs[0x2B] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x4B] = op_ALR; opcode_defs[0x4B] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0x6B] = op_ARR; opcode_defs[0x6B] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    opcode_table[0xAB] = op_ATX; opcode_defs[0xAB] = OpcodeDef(mode=IMMEDIATE, cycles=2, page_boundary=False, rmw=False)
    # Note: Unassigned opcode slots are intentionally left NULL in opcode_table.
    # CPU execute path checks NULL and skips unknown instructions safely.