# Glossary (plain-language terms for this module):
# - Flag: One-bit state marker showing result or mode of last CPU operation.
# - Carry flag: Indicates overflow from bit 7 on add, or borrow behavior on subtract.
# - Zero flag: Indicates result value is exactly zero.
# - Negative flag: Mirrors highest bit of result (bit 7), often treated as sign bit.
# - Overflow flag: Indicates signed arithmetic result could not fit in -128..127 range.
# - Interrupt disable flag: Temporarily blocks normal IRQ interrupts.
# - Decimal mode flag: 6502 BCD mode flag (NES CPU keeps it but does not implement decimal math).
# - Break flag: Marker used when BRK/interrupt status is pushed to stack.
# NESdev references:
# - https://www.nesdev.org/wiki/Status_flags
# - https://www.nesdev.org/wiki/CPU

cdef class CPUFlags:
    """Container for 6502 processor status flags.

    Stores carry/zero/interrupt/decimal/break/overflow/negative bits used by
    instruction handlers.

    NESdev references:
    - https://www.nesdev.org/wiki/Status_flags
    - https://www.nesdev.org/wiki/CPU
    """

    cdef public bint negative
    cdef public bint overflow     
    cdef public bint break_source 
    cdef public bint decimal_mode 
    cdef public bint interrupts_disabled 
    cdef public bint zero 
    cdef public bint carry     

    def __init__(self):
        """Initialize all status flags to cleared state.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Sets all internal status-flag booleans to 'False'.

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