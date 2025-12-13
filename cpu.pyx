# cpu.pyx
import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, int8_t

cdef enum AddressingMode:
    NONE = 0
    DIRECT = 1
    IMMEDIATE = 2
    ZEROPAGE = 3
    ABSOLUTE = 4
    ZEROPAGEX = 5
    ZEROPAGEY = 6
    ABSOLUTEX = 7
    ABSOLUTEY = 8
    INDIRECTX = 9
    INDIRECTY = 10

cdef class CPUFlags:
    cdef bint negative
    cdef bint overflow     
    cdef bint break_source 
    cdef bint decimal_mode 
    cdef bint interrupts_disabled 
    cdef bint zero 
    cdef bint carry     

    def __init__(self):
        self.negative = False
        self.overflow = False
        self.break_source = False
        self.decimal_mode = False
        self.interrupts_disabled = False
        self.zero = False
        self.carry = False

cdef struct OpcodeDef:
    AddressingMode mode
    int cycles
    bint page_boundary
    bint rmw

cdef void (*opcode_table[256])(CPU6502)  
cdef OpcodeDef opcode_defs[256]

cdef void init_opcodes():
    global opcode_table, opcode_defs
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

cdef void op_JSR(CPU6502 cpu):
    cpu.push_word(cpu.PC + 1)
    cpu.PC = cpu.next_word()

cdef void op_RTI(CPU6502 cpu):
    cpu.next_byte()  # Dummy fetch
    cpu.set_P(cpu.pop())
    cpu.PC = cpu.pop_word()

cdef void op_RTS(CPU6502 cpu):
    cpu.next_byte()  # Dummy fetch
    cpu.PC = cpu.pop_word() + 1

cdef void op_INY(CPU6502 cpu):
    cpu.Y += 1
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_DEY(CPU6502 cpu):
    cpu.Y -= 1
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_INX(CPU6502 cpu):
    cpu.X += 1
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_DEX(CPU6502 cpu):
    cpu.X -= 1
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_TAY(CPU6502 cpu):
    cpu.Y = cpu.A
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_TYA(CPU6502 cpu):
    cpu.A = cpu.Y
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_TAX(CPU6502 cpu):
    cpu.X = cpu.A
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_TXA(CPU6502 cpu):
    cpu.A = cpu.X
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_TSX(CPU6502 cpu):
    cpu.X = cpu.SP
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_TXS(CPU6502 cpu):
    cpu.SP = cpu.X

cdef void op_PHP(CPU6502 cpu):
    cpu.push(cpu.get_P() | 0x10)  # BreakSourceBit

cdef void op_PLP(CPU6502 cpu):
    cpu.set_P(cpu.pop() & ~0x10)

cdef void op_PLA(CPU6502 cpu):
    cpu.A = cpu.pop()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_PHA(CPU6502 cpu):
    cpu.push(cpu.A)

cdef void op_BIT(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read()
    cpu.F.overflow = (val & 0x40) > 0
    cpu.F.zero = (val & cpu.A) == 0
    cpu.F.negative = (val & 0x80) > 0

cdef void op_BRANCH(CPU6502 cpu, bint cond):
    cdef int8_t offset = cpu.next_sbyte()
    if cond:
        cpu.PC = <uint16_t>(cpu.PC + offset)
        cpu.cycles += 1

cdef void op_JMP(CPU6502 cpu):
    cdef uint16_t off
    cdef uint16_t addr_low, addr_high
    
    if cpu.current_instruction == 0x4C: # Absolute
        cpu.PC = cpu.next_word()
    elif cpu.current_instruction == 0x6C: # Indirect
        off = cpu.next_word()
        
        # Читаем младший байт адреса перехода
        addr_low = cpu.read_byte(off)
        
        # Читаем старший байт с эмуляцией аппаратного бага 6502:
        # Если указатель находится на границе страницы (например $30FF),
        # то старший байт берется не из $3100, а из $3000 (заворот внутри страницы).
        if (off & 0x00FF) == 0x00FF:
            addr_high = cpu.read_byte(off & 0xFF00)
        else:
            addr_high = cpu.read_byte(off + 1)
            
        cpu.PC = <uint16_t>(addr_low | (addr_high << 8))

cdef void op_BCS(CPU6502 cpu):
    op_BRANCH(cpu, cpu.F.carry)

cdef void op_BCC(CPU6502 cpu):
    op_BRANCH(cpu, not cpu.F.carry)

cdef void op_BEQ(CPU6502 cpu):
    op_BRANCH(cpu, cpu.F.zero)

cdef void op_BNE(CPU6502 cpu):
    op_BRANCH(cpu, not cpu.F.zero)

cdef void op_BVS(CPU6502 cpu):
    op_BRANCH(cpu, cpu.F.overflow)

cdef void op_BVC(CPU6502 cpu):
    op_BRANCH(cpu, not cpu.F.overflow)

cdef void op_BPL(CPU6502 cpu):
    op_BRANCH(cpu, not cpu.F.negative)

cdef void op_BMI(CPU6502 cpu):
    op_BRANCH(cpu, cpu.F.negative)

cdef void op_STA(CPU6502 cpu):
    cpu.address_write(cpu.A)

cdef void op_STX(CPU6502 cpu):
    cpu.address_write(cpu.X)

cdef void op_STY(CPU6502 cpu):
    cpu.address_write(cpu.Y)

cdef void op_CLC(CPU6502 cpu):
    cpu.F.carry = False

cdef void op_SEC(CPU6502 cpu):
    cpu.F.carry = True

cdef void op_CLI(CPU6502 cpu):
    cpu.F.interrupts_disabled = False

cdef void op_SEI(CPU6502 cpu):
    cpu.F.interrupts_disabled = True

cdef void op_CLV(CPU6502 cpu):
    cpu.F.overflow = False

cdef void op_CLD(CPU6502 cpu):
    cpu.F.decimal_mode = False

cdef void op_SED(CPU6502 cpu):
    cpu.F.decimal_mode = True

cdef void op_NOP(CPU6502 cpu):
    pass

cdef void op_LDA(CPU6502 cpu):
    cpu.A = cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_LDY(CPU6502 cpu):
    cpu.Y = cpu.address_read()
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_LDX(CPU6502 cpu):
    cpu.X = cpu.address_read()
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_ORA(CPU6502 cpu):
    cpu.A |= cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_AND(CPU6502 cpu):
    cpu.A &= cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_EOR(CPU6502 cpu):
    cpu.A ^= cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_SBC(CPU6502 cpu):
    cdef uint8_t val = ~cpu.address_read()
    cdef int nA = <int8_t>cpu.A + <int8_t>val + (1 if cpu.F.carry else 0)
    cpu.F.overflow = nA < -128 or nA > 127
    cpu.F.carry = (cpu.A + val + (1 if cpu.F.carry else 0)) > 0xFF
    cpu.A = <uint8_t>(nA & 0xFF)
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_ADC(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read()
    cdef int nA = <int8_t>cpu.A + <int8_t>val + (1 if cpu.F.carry else 0)
    cpu.F.overflow = nA < -128 or nA > 127
    cpu.F.carry = (cpu.A + val + (1 if cpu.F.carry else 0)) > 0xFF
    cpu.A = <uint8_t>(nA & 0xFF)
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_BRK(CPU6502 cpu):
    cpu.next_byte()
    cpu.push(cpu.get_P() | 0x10)
    cpu.F.interrupts_disabled = True
    cpu.PC = cpu.read_word(0xFFFE)

cdef void op_CMP(CPU6502 cpu):
    cdef uint8_t reg = cpu.A
    cdef long d = reg - <int>cpu.address_read()
    cpu.F.negative = (d & 0x80) > 0 and d != 0
    cpu.F.carry = d >= 0
    cpu.F.zero = d == 0

cdef void op_CPX(CPU6502 cpu):
    cdef uint8_t reg = cpu.X
    cdef long d = reg - <int>cpu.address_read()
    cpu.F.negative = (d & 0x80) > 0 and d != 0
    cpu.F.carry = d >= 0
    cpu.F.zero = d == 0

cdef void op_CPY(CPU6502 cpu):
    cdef uint8_t reg = cpu.Y
    cdef long d = reg - <int>cpu.address_read()
    cpu.F.negative = (d & 0x80) > 0 and d != 0
    cpu.F.carry = d >= 0
    cpu.F.zero = d == 0

cdef void op_LSR(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read()
    cpu.F.carry = (val & 0x01) > 0
    val >>= 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_ASL(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read()
    cpu.F.carry = (val & 0x80) > 0
    val <<= 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_ROR(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read()
    cdef bint c = cpu.F.carry
    cpu.F.carry = (val & 0x01) > 0
    val >>= 1
    if c:
        val |= 0x80
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_ROL(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read()
    cdef bint c = cpu.F.carry
    cpu.F.carry = (val & 0x80) > 0
    val <<= 1
    if c:
        val |= 0x01
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_INC(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read() + 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_DEC(CPU6502 cpu):
    cdef uint8_t val = cpu.address_read() - 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_SKB(CPU6502 cpu):
    cpu.next_byte()

cdef void op_ANC(CPU6502 cpu):
    cpu.A &= cpu.address_read()
    cpu.F.carry = cpu.F.negative

cdef void op_ALR(CPU6502 cpu):
    cpu.A &= cpu.address_read()
    cpu.F.carry = (cpu.A & 0x01) > 0
    cpu.A >>= 1
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_ARR(CPU6502 cpu):
    cpu.A &= cpu.address_read()
    cdef bint c = cpu.F.carry
    cpu.F.carry = (cpu.A & 0x01) > 0
    cpu.A >>= 1
    if c:
        cpu.A |= 0x80
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_ATX(CPU6502 cpu):
    cpu.A |= cpu.read_byte(0xEE)
    cpu.A &= cpu.address_read()
    cpu.X = cpu.A

cdef class CPU6502:
    cdef uint8_t A
    cdef uint8_t X
    cdef uint8_t Y
    cdef uint8_t SP
    cdef uint16_t PC
    cdef CPUFlags F
    cdef public cnp.ndarray memory
    cdef cnp.ndarray ram
    cdef public int cycles
    cdef uint8_t current_instruction
    cdef uint16_t current_memory_address
    cdef bint has_current_address
    cdef uint16_t interrupt_vectors[3]
    cdef bint interrupts[2]
    cdef object ppu
    cdef object apu
    cdef object controller
    cdef object cartridge
    cdef int _debug_instr_printed
    cdef int _debug_instr_limit

    def __init__(self):
        self.A = <uint8_t>0x00
        self.X = <uint8_t>0x00
        self.Y = <uint8_t>0x00
        self.SP = <uint8_t>0xFD
        self.PC = <uint16_t>0x0000
        self.F = CPUFlags()
        self.F.interrupts_disabled = True
        self.memory = np.zeros(0x10000, dtype=np.uint8)
        self.ram = np.zeros(0x0800, dtype=np.uint8)
        self.cycles = 0
        self.current_instruction = 0
        self.current_memory_address = 0
        self.has_current_address = False
        init_opcodes()
        self.interrupt_vectors[0] = 0xFFFA  # NMI
        self.interrupt_vectors[1] = 0xFFFE  # IRQ
        self.interrupt_vectors[2] = 0xFFFC  # RESET
        self.interrupts[0] = False
        self.interrupts[1] = False
        # Debug: how many instructions we've printed
        self._debug_instr_printed = 0
        self._debug_instr_limit = 50
        # self.reset()

    cpdef public void reset(self):
        self.PC = self.read_word(self.interrupt_vectors[2])
        self.SP = <uint8_t>0xFD
        self.F.interrupts_disabled = True
        self.cycles = 0

    cdef uint8_t fetch(self):
        cdef uint8_t opcode = self.read_byte(self.PC)
        self.PC += 1
        return opcode

    cdef uint8_t read_byte(self, uint16_t address):
        # 1. RAM
        if 0x0000 <= address <= 0x1FFF:
            return self.ram[address & 0x07FF]
            
        # 2. PPU
        if 0x2000 <= address <= 0x3FFF:
            reg = 0x2000 + (address % 8)
            return self.ppu.read_register(reg)
            
        # 3. APU / IO - ЭТОГО НЕ БЫЛО!
        if 0x4000 <= address <= 0x401F:
            return self.read_io_register(address)
            
        # 4. Cartridge (PRG-ROM)
        if 0x8000 <= address <= 0xFFFF:
            return self.cartridge.mapper_instance.read_prg(address)
            
        # 5. Остальная память
        return self.memory[address]

    cdef void write_byte(self, uint16_t address, uint8_t value):
        # 1. PPU Registers ($2000-$3FFF)
        if 0x2000 <= address <= 0x3FFF:
            reg = 0x2000 + (address % 8)
            self.ppu.write_register(reg, value)
            return
            
        # 2. APU / IO Registers ($4000-$401F) - ЭТОГО НЕ БЫЛО!
        if 0x4000 <= address <= 0x401F:
            self.write_io_register(address, value)
            return

        # 3. RAM ($0000-$1FFF)
        if 0x0000 <= address <= 0x1FFF:
            self.ram[address & 0x07FF] = value
            
        # 4. Cartridge / Mapper (PRG-ROM обычно Read-Only, но мапперы перехватывают запись)
        elif address >= 0x8000:
            self.cartridge.mapper_instance.write_prg(address, value)
            
        # 5. Остальная память
        else:
            self.memory[address] = value

    cdef uint16_t read_word(self, uint16_t address):
        return <uint16_t>(self.read_byte(address) | (self.read_byte(address + 1) << 8))

    cdef void push(self, uint8_t value):
        self.write_byte(0x0100 + self.SP, value)
        self.SP -= 1

    cdef uint8_t pop(self):
        self.SP += 1
        return self.read_byte(0x0100 + self.SP)

    cdef void push_word(self, uint16_t value):
        self.push(<uint8_t>(value >> 8))
        self.push(<uint8_t>(value & 0xFF))

    cdef uint16_t pop_word(self):
        return <uint16_t>(self.pop() | (self.pop() << 8))

    cdef uint8_t get_P(self):
        return <uint8_t>(
            (self.F.carry << 0) |
            (self.F.zero << 1) |
            (self.F.interrupts_disabled << 2) |
            (self.F.decimal_mode << 3) |
            (self.F.break_source << 4) |
            (1 << 5) |
            (self.F.overflow << 6) |
            (self.F.negative << 7)
        )

    cdef void set_P(self, uint8_t value):
        self.F.carry = (value & 0x01) > 0
        self.F.zero = (value & 0x02) > 0
        self.F.interrupts_disabled = (value & 0x04) > 0
        self.F.decimal_mode = (value & 0x08) > 0
        self.F.break_source = (value & 0x10) > 0
        self.F.overflow = (value & 0x40) > 0
        self.F.negative = (value & 0x80) > 0

    cdef uint8_t next_byte(self):
        cdef uint8_t value = self.read_byte(self.PC)
        self.PC += 1
        return value

    cdef uint16_t next_word(self):
        cdef uint16_t value = self.read_word(self.PC)
        self.PC += 2
        return value

    cdef int8_t next_sbyte(self):
        return <int8_t>self.next_byte()

    cdef uint16_t address(self):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        cdef uint16_t addr
        cdef uint8_t off
        if defn.mode == IMMEDIATE:
            addr = self.PC
            self.PC += 1
        elif defn.mode == ZEROPAGE:
            addr = self.next_byte()
        elif defn.mode == ABSOLUTE:
            addr = self.next_word()
        elif defn.mode == ZEROPAGEX:
            addr = (self.next_byte() + self.X) & 0xFF
        elif defn.mode == ZEROPAGEY:
            addr = (self.next_byte() + self.Y) & 0xFF
        elif defn.mode == ABSOLUTEX:
            addr = self.next_word()
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.X) & 0xFF00):
                self.cycles += 1
            addr += self.X
        elif defn.mode == ABSOLUTEY:
            addr = self.next_word()
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.Y) & 0xFF00):
                self.cycles += 1
            addr += self.Y
        elif defn.mode == INDIRECTX:
            off = (self.next_byte() + self.X) & 0xFF
            addr = <uint16_t>(self.read_byte(off) | (self.read_byte((off + 1) & 0xFF) << 8))
        elif defn.mode == INDIRECTY:
            off = self.next_byte() & 0xFF
            addr = <uint16_t>(self.read_byte(off) | (self.read_byte((off + 1) & 0xFF) << 8))
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.Y) & 0xFF00):
                self.cycles += 1
            addr += self.Y
        else:
            addr = 0  # Для DIRECT и NONE адрес не нужен
        return addr

    cdef uint8_t address_read(self):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        if defn.mode == DIRECT:
            return self.A
        if not self.has_current_address:
            self.current_memory_address = self.address()
            self.has_current_address = True
        return self.read_byte(self.current_memory_address)

    cdef void address_write(self, uint8_t val):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        if defn.mode == DIRECT:
            self.A = val
            self.F.zero = (self.A == 0)
            self.F.negative = (self.A & 0x80) > 0
        else:
            if not self.has_current_address:
                self.current_memory_address = self.address()
                self.has_current_address = True
            if defn.rmw:
                self.write_byte(self.current_memory_address, self.read_byte(self.current_memory_address))
            self.write_byte(self.current_memory_address, val)

    cdef void execute(self, uint8_t opcode):
        cdef void (*op_func)(CPU6502)
        self.current_instruction = opcode
        self.has_current_address = False
        op_func = opcode_table[opcode]
        if op_func != NULL:
            # Debug print first few instructions
            # try:
            #     if self._debug_instr_printed < self._debug_instr_limit:
            #         print(f"CPU exec PC={self.PC:04X} opcode={opcode:02X}")
            #         self._debug_instr_printed += 1
            # except Exception:
            #     pass
            self.cycles += opcode_defs[opcode].cycles
            op_func(self)
        else:
            # print(f"Warning: Unsupported opcode {opcode:02x} at PC={self.PC:04x}")
            # Choose to skip, halt, or treat as NOP:
            # For now, treat as NOP (no operation)
            return

    cpdef public void trigger_interrupt(self, int type):  # type: 0=NMI, 1=IRQ, 2=RESET
        if not self.F.interrupts_disabled or type == 0:
            self.interrupts[type] = True
            try:
                itype = {0: 'NMI', 1: 'IRQ', 2: 'RESET'}.get(type, str(type))
                # print(f"CPU: interrupt requested {itype} (type={type})")
            except Exception:
                pass

    cdef void write_io_register(self, uint16_t reg, uint8_t val):
        cdef int i
        cdef uint16_t dma_start
        # Используем numpy для создания временного буфера (или можно добавить поле в класс для скорости)
        cdef uint8_t[:] dma_buffer 

        if reg == 0x4014: # OAM DMA
            # 1. Вычисляем стартовый адрес: val * 256
            dma_start = <uint16_t>val << 8
            
            # 2. Создаем буфер для передачи
            # (Важно: создаем новый массив, чтобы передать memoryview)
            dma_buffer = np.zeros(256, dtype=np.uint8)
            
            # 3. Читаем 256 байт из памяти CPU (с учетом всех мапперов и RAM)
            for i in range(256):
                dma_buffer[i] = self.read_byte(dma_start + i)
            
            # 4. Передаем заполненный буфер в PPU
            if self.ppu is not None:
                self.ppu.perform_dma(dma_buffer)
            
            # 5. Эмуляция задержки CPU (513 или 514 циклов)
            self.cycles += 513
            if self.cycles % 2 == 1:
                self.cycles += 1
                
        elif reg == 0x4016: # Controller Strobe
            if self.controller is not None:
                self.controller.write(val)
                
        elif reg <= 0x401F: # APU Registers
            if self.apu is not None:
                self.apu.write(reg, val)
        else:
            # Другие регистры (не реализованы или не нужны)
            pass


    cdef uint8_t read_io_register(self, uint16_t reg):
        if reg == 0x4016:
            if self.controller is not None:
                return self.controller.read()
        return 0

    def set_peripherals(self, ppu, apu, controller):
        self.ppu = ppu
        self.apu = apu
        self.controller = controller

    def set_cartridge(self, cartridge):
        self.cartridge = cartridge

    cpdef public void step(self):
        # Interrupt handling
        for i in range(2):
            if self.interrupts[i]:
                # try:
                #     itype = {0: 'NMI', 1: 'IRQ'}.get(i, str(i))
                #     print(f"CPU: servicing interrupt {itype} (vector @ {self.interrupt_vectors[i]:04X})")
                # except Exception:
                #     pass
                self.push_word(self.PC)
                self.push(self.get_P())
                self.PC = self.read_word(self.interrupt_vectors[i])
                # try:
                #     # Dump first bytes at the interrupt handler PC for inspection
                #     dump = []
                #     for off in range(16):
                #         dump.append(f"{self.read_byte((self.PC + off) & 0xFFFF):02X}")
                #     print(f"CPU: interrupt handler @ {self.PC:04X} bytes: {' '.join(dump)}")
                # except Exception:
                #     pass
                self.F.interrupts_disabled = True
                self.interrupts[i] = False
                return
        opcode = self.fetch()
        self.execute(opcode)