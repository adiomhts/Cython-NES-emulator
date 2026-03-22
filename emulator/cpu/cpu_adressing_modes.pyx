# Glossary (plain-language terms for this module):
# - Addressing mode: Rule that tells CPU where instruction operand comes from.
# - Immediate: Operand is literal value encoded directly in instruction bytes.
# - Zero page: Fast access to first 256 bytes of memory ($0000-$00FF).
# - Absolute: Full 16-bit address follows instruction.
# - Indexed: Base address adjusted by X or Y register.
# - Indirect: Address is looked up from memory pointer bytes.
# - Direct (accumulator): Operation uses A register as operand target/source.
# NESdev references:
# - https://www.nesdev.org/wiki/CPU_addressing_modes
# - https://www.nesdev.org/wiki/CPU

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
