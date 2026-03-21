import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, int8_t

# Glossary (terms used in comments/docstrings in this file):
# - CPU: Central Processing Unit (Ricoh 2A03, 6502-derived core).
# - PC/SP: Program Counter / Stack Pointer registers.
# - IRQ/NMI: Maskable / non-maskable interrupt request lines.
# - DMA: Direct Memory Access; here OAM DMA via `$4014`.
# - RMW: Read-Modify-Write instruction class with dummy write behavior.
# - Zero page: First 256 bytes (`$0000-$00FF`) with special addressing modes.
# NESdev references:
# - https://www.nesdev.org/wiki/CPU
# - https://www.nesdev.org/wiki/CPU_memory_map
# - https://www.nesdev.org/wiki/CPU_interrupts
# - https://www.nesdev.org/wiki/DMA

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
    """Container for 6502 processor status flags.

    Stores carry/zero/interrupt/decimal/break/overflow/negative bits used by
    instruction handlers.

    NESdev references:
    - https://www.nesdev.org/wiki/Status_flags
    - https://www.nesdev.org/wiki/CPU
    """

    cdef bint negative
    cdef bint overflow     
    cdef bint break_source 
    cdef bint decimal_mode 
    cdef bint interrupts_disabled 
    cdef bint zero 
    cdef bint carry     

    def __init__(self):
        """Initialize all status flags to cleared state.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Sets all internal status-flag booleans to `False`.

        NESdev reference:
            https://www.nesdev.org/wiki/Status_flags
        """
        # N, V, B, D, I, Z, C all start cleared in this local container.
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

cdef class CPU6502:
    pass

ctypedef void (*OpcodeHandler)(CPU6502)

cdef OpcodeHandler opcode_table[256]
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
    cpu.next_byte()
    cpu.set_P(cpu.pop())
    cpu.PC = cpu.pop_word()

cdef void op_RTS(CPU6502 cpu):
    cpu.next_byte()
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
    cpu.push(cpu.get_P() | 0x10)

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
    
    if cpu.current_instruction == 0x4C:
        cpu.PC = cpu.next_word()
    elif cpu.current_instruction == 0x6C:
        off = cpu.next_word()
        
        addr_low = cpu.read_byte(off)
        
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
    cpu.push_word(cpu.PC)
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
    """Ricoh 2A03 CPU core with NES bus mapping and interrupt handling.

    Implements instruction fetch/decode/execute, interrupt sequencing, and
    memory-mapped IO dispatch to PPU/APU/controller/cartridge.

    NESdev references:
    - https://www.nesdev.org/wiki/CPU
    - https://www.nesdev.org/wiki/CPU_memory_map
    - https://www.nesdev.org/wiki/Cycle_reference_chart
    """

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
    cdef object controller2
    cdef object cartridge
    cdef int _debug_instr_printed
    cdef int _debug_instr_limit

    def __init__(self):
        """Create CPU state, opcode tables, and interrupt vectors.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Allocates CPU RAM/memory arrays, initializes status/register fields,
            and prepares opcode metadata used by execution loop.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_power_up_state
            https://www.nesdev.org/wiki/CPU_memory_map
        """
        # 6502 general-purpose registers.
        self.A = <uint8_t>0x00
        self.X = <uint8_t>0x00
        self.Y = <uint8_t>0x00
        # Stack pointer reset default for NES power-up flow.
        self.SP = <uint8_t>0xFD
        self.PC = <uint16_t>0x0000
        # Processor status flags container.
        self.F = CPUFlags()
        self.F.interrupts_disabled = True
        # Full 64KB address space view (used for fallback / mapped regions).
        self.memory = np.full(0x10000, 0x00, dtype=np.uint8)
        # Internal RAM physically 2KB and mirrored through $1FFF.
        self.ram = np.full(0x0800, 0xFF, dtype=np.uint8)
        # Global cycle counter consumed by scheduler and peripherals.
        self.cycles = 0
        self.current_instruction = 0
        self.current_memory_address = 0
        self.has_current_address = False
        # Build opcode dispatch tables exactly once per instance startup.
        init_opcodes()
        # Interrupt vectors: NMI, IRQ/BRK, RESET.
        self.interrupt_vectors[0] = 0xFFFA
        self.interrupt_vectors[1] = 0xFFFE
        self.interrupt_vectors[2] = 0xFFFC
        # Pending interrupt latches.
        self.interrupts[0] = False
        self.interrupts[1] = False
        self.controller2 = None
        self._debug_instr_printed = 0
        self._debug_instr_limit = 50

    cpdef public void reset(self):
        """Reset CPU core state.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Loads PC from RESET vector, resets stack pointer and cycle counter,
            and forces interrupt-disable flag.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_power_up_state
            https://www.nesdev.org/wiki/CPU_interrupts
        """
        # Read reset vector from $FFFC/$FFFD and jump execution there.
        self.PC = self.read_word(self.interrupt_vectors[2])
        # Reset stack pointer and interrupt mask for deterministic startup.
        self.SP = <uint8_t>0xFD
        self.F.interrupts_disabled = True
        self.cycles = 0

    cdef uint8_t fetch(self):
        cdef uint8_t opcode = self.read_byte(self.PC)
        self.PC += 1
        return opcode

    cdef uint8_t read_byte(self, uint16_t address):
        # $0000-$1FFF: internal RAM mirrored every 2KB.
        if 0x0000 <= address <= 0x1FFF:
            return self.ram[address & 0x07FF]
            
        # $2000-$3FFF: PPU registers mirrored every 8 bytes.
        if 0x2000 <= address <= 0x3FFF:
            reg = 0x2000 + (address % 8)
            return self.ppu.read_register(reg)
            
        # $4000-$401F: APU and controller I/O space.
        if 0x4000 <= address <= 0x401F:
            return self.read_io_register(address)

        # $6000-$7FFF: cartridge PRG RAM / save RAM window.
        if 0x6000 <= address <= 0x7FFF:
            if self.cartridge is not None:
                try:
                    if getattr(self.cartridge, 'mapper', 0) == 1:
                        return self.cartridge.mapper_instance.read_prg(address)
                except Exception:
                    pass
            return self.memory[address]
            
        # $8000-$FFFF: cartridge PRG ROM through mapper.
        if 0x8000 <= address <= 0xFFFF:
            return self.cartridge.mapper_instance.read_prg(address)
            
        # Generic fallback for any unmapped path.
        return self.memory[address]

    cdef void write_byte(self, uint16_t address, uint8_t value):
        # PPU register writes.
        if 0x2000 <= address <= 0x3FFF:
            reg = 0x2000 + (address % 8)
            self.ppu.write_register(reg, value)
            return
            
        # APU/controller and DMA register writes.
        if 0x4000 <= address <= 0x401F:
            self.write_io_register(address, value)
            return

        # Internal RAM writes with mirroring.
        if 0x0000 <= address <= 0x1FFF:
            self.ram[address & 0x07FF] = value

        elif 0x6000 <= address <= 0x7FFF:
            # Mapper-specific PRG RAM handling (MMC1 path).
            if self.cartridge is not None:
                try:
                    if getattr(self.cartridge, 'mapper', 0) == 1:
                        self.cartridge.mapper_instance.write_prg(address, value)
                        return
                except Exception:
                    pass
            self.memory[address] = value
            
        elif address >= 0x8000:
            # Writes to PRG area are mapper control writes for many cartridges.
            self.cartridge.mapper_instance.write_prg(address, value)
            
        else:
            self.memory[address] = value

    cdef uint16_t read_word(self, uint16_t address):
        # 6502 words are little-endian: low byte then high byte.
        return <uint16_t>(self.read_byte(address) | (self.read_byte(address + 1) << 8))

    cdef void push(self, uint8_t value):
        # Stack is fixed at page $0100 and grows downward.
        self.write_byte(0x0100 + self.SP, value)
        self.SP -= 1

    cdef uint8_t pop(self):
        # Pop reverses push order and stack grows upward on read.
        self.SP += 1
        return self.read_byte(0x0100 + self.SP)

    cdef void push_word(self, uint16_t value):
        # Push high then low, matching 6502 interrupt/call conventions.
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
        # Fetch one byte at PC and post-increment.
        cdef uint8_t value = self.read_byte(self.PC)
        self.PC += 1
        return value

    cdef uint16_t next_word(self):
        # Fetch little-endian 16-bit operand and advance PC by 2.
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
            # Immediate mode uses operand byte at current PC.
            addr = self.PC
            self.PC += 1
        elif defn.mode == ZEROPAGE:
            # Zero-page addressing wraps within $00xx.
            addr = self.next_byte()
        elif defn.mode == ABSOLUTE:
            # Absolute 16-bit address operand.
            addr = self.next_word()
        elif defn.mode == ZEROPAGEX:
            # Zero-page indexed by X with wrap-around.
            addr = (self.next_byte() + self.X) & 0xFF
        elif defn.mode == ZEROPAGEY:
            # Zero-page indexed by Y with wrap-around.
            addr = (self.next_byte() + self.Y) & 0xFF
        elif defn.mode == ABSOLUTEX:
            # Absolute indexed by X (may incur page-cross cycle).
            addr = self.next_word()
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.X) & 0xFF00):
                self.cycles += 1
            addr += self.X
        elif defn.mode == ABSOLUTEY:
            # Absolute indexed by Y (may incur page-cross cycle).
            addr = self.next_word()
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.Y) & 0xFF00):
                self.cycles += 1
            addr += self.Y
        elif defn.mode == INDIRECTX:
            # (d,X): first index zp pointer by X, then read 16-bit target.
            off = (self.next_byte() + self.X) & 0xFF
            addr = <uint16_t>(self.read_byte(off) | (self.read_byte((off + 1) & 0xFF) << 8))
        elif defn.mode == INDIRECTY:
            # (d),Y: read zp pointer then index final target by Y.
            off = self.next_byte() & 0xFF
            addr = <uint16_t>(self.read_byte(off) | (self.read_byte((off + 1) & 0xFF) << 8))
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.Y) & 0xFF00):
                self.cycles += 1
            addr += self.Y
        else:
            # NONE/direct modes do not resolve a memory address here.
            addr = 0
        return addr

    cdef uint8_t address_read(self):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        if defn.mode == DIRECT:
            # Accumulator-addressed ops read A directly.
            return self.A
        if not self.has_current_address:
            # Resolve once so RMW ops reuse same effective address.
            self.current_memory_address = self.address()
            self.has_current_address = True
        return self.read_byte(self.current_memory_address)

    cdef void address_write(self, uint8_t val):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        if defn.mode == DIRECT:
            # Accumulator-addressed write targets A register directly.
            self.A = val
            self.F.zero = (self.A == 0)
            self.F.negative = (self.A & 0x80) > 0
        else:
            if not self.has_current_address:
                # Ensure same effective address as prior read phase.
                self.current_memory_address = self.address()
                self.has_current_address = True
            if defn.rmw:
                # Emulate dummy write for read-modify-write timing behavior.
                self.write_byte(self.current_memory_address, self.read_byte(self.current_memory_address))
            # Final writeback phase.
            self.write_byte(self.current_memory_address, val)

    cdef void execute(self, uint8_t opcode):
        cdef void (*op_func)(CPU6502)
        # Track opcode so addressing helpers can inspect metadata.
        self.current_instruction = opcode
        # New instruction => no cached effective address yet.
        self.has_current_address = False
        op_func = opcode_table[opcode]
        if op_func != NULL:
            # Base cycles are charged before handler-specific penalties.
            self.cycles += opcode_defs[opcode].cycles
            op_func(self)
        else:
            return

    cpdef public void trigger_interrupt(self, int type):
        """Queue an interrupt request.

        Args:
            type: Interrupt kind identifier (`0=NMI`, `1=IRQ`, `2=RESET`).

        Returns:
            None.

        Side Effects:
            Marks corresponding interrupt slot as pending when allowed by CPU
            interrupt mask rules.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_interrupts
            https://www.nesdev.org/wiki/NMI
        """
        # Interrupt is latched and consumed at the next `step()` boundary.
        self.interrupts[type] = True
        try:
            itype = {0: 'NMI', 1: 'IRQ', 2: 'RESET'}.get(type, str(type))
        except Exception:
            pass

    cdef void write_io_register(self, uint16_t reg, uint8_t val):
        cdef int i
        cdef uint16_t dma_start
        cdef uint8_t[:] dma_buffer 

        if reg == 0x4014:
            # OAM DMA: copy page $xx00-$xxFF into PPU OAM.
            dma_start = <uint16_t>val << 8
            
            dma_buffer = np.zeros(256, dtype=np.uint8)
            
            for i in range(256):
                dma_buffer[i] = self.read_byte(dma_start + i)
            
            if self.ppu is not None:
                self.ppu.perform_dma(dma_buffer)
            
            # DMA stalls CPU for 513 or 514 cycles depending on parity.
            self.cycles += 513
            if self.cycles % 2 == 1:
                self.cycles += 1
                
        elif reg == 0x4016:
            # Controller strobe write is broadcast to both controllers.
            if self.controller is not None:
                self.controller.write(val)
            if self.controller2 is not None:
                self.controller2.write(val)
                
        elif reg <= 0x401F:
            # Remaining IO register writes are delegated to APU.
            if self.apu is not None:
                self.apu.write(reg, val)
        else:
            pass


    cdef uint8_t read_io_register(self, uint16_t reg):
        if reg == 0x4015:
            # APU status register (channel activity + IRQ flags).
            if self.apu is not None:
                return self.apu.read_status()
            return 0

        if reg == 0x4016:
            # Controller 1 serial read.
            if self.controller is not None:
                return self.controller.read()
            return 0x40

        if reg == 0x4017:
            # Controller 2 serial read.
            if self.controller2 is not None:
                return self.controller2.read()
            return 0x40
        # Unimplemented IO reads return open-bus-like zero fallback.
        return 0

    def set_peripherals(self, ppu, apu, controller, controller2=None):
        """Attach memory-mapped peripherals.

        Args:
            ppu: PPU instance handling `$2000-$3FFF` register space.
            apu: APU instance handling `$4000-$4017` register writes.
            controller: Controller instance handling `$4016` reads/writes.
            controller2: Optional controller instance for `$4017` reads.

        Returns:
            None.

        Side Effects:
            Stores references used by `read_byte` and `write_byte` dispatch.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_memory_map
            https://www.nesdev.org/wiki/PPU_registers
        """
        # Keep direct references for fast dispatch in hot read/write paths.
        self.ppu = ppu
        self.apu = apu
        self.controller = controller
        self.controller2 = controller2

    def set_cartridge(self, cartridge):
        """Attach cartridge/mapper backend.

        Args:
            cartridge: Cartridge object exposing mapper read/write operations.

        Returns:
            None.

        Side Effects:
            Stores cartridge reference used by CPU PRG read/write mapping.

        NESdev references:
            https://www.nesdev.org/wiki/Mapper
            https://www.nesdev.org/wiki/CPU_memory_map
        """
        # Mapper object owns bank switching behavior for PRG/CHR accesses.
        self.cartridge = cartridge

    cpdef public void step(self):
        """Execute one CPU step.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Services pending interrupts or fetches/executes one opcode,
            mutating registers, memory, and cycle counter.

        NESdev references:
            https://www.nesdev.org/wiki/Cycle_reference_chart
            https://www.nesdev.org/wiki/CPU_interrupts
        """
        # Mapper (e.g., MMC3) may request IRQ asynchronously.
        if self.cartridge is not None:
            try:
                if getattr(self.cartridge.mapper_instance, 'irq_pending', 0):
                    self.interrupts[1] = True
            except Exception:
                pass

        # Service pending NMI/IRQ before fetching next opcode.
        for i in range(2):
            if self.interrupts[i] and (i == 0 or not self.F.interrupts_disabled):
                # Standard interrupt prologue: push PC/P, load vector, mask IRQ.
                self.push_word(self.PC)
                self.push(self.get_P())
                self.PC = self.read_word(self.interrupt_vectors[i])
                self.F.interrupts_disabled = True
                self.interrupts[i] = False
                return
        # No interrupt taken: execute one opcode.
        opcode = self.fetch()
        self.execute(opcode)