from libc.stdint cimport uint8_t

cdef class Controller:
    """NES standard controller serial latch and shift-register behavior.

    Emulates the strobe/write and serial read behavior used through register
    `$4016`.
    """

    cdef uint8_t buttons
    cdef uint8_t shift_reg
    cdef bint strobe

    def __init__(self):
        """Initialize controller internal state.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Resets button bitfield, serial shift register, and strobe mode.
        """
        self.buttons = 0
        self.shift_reg = 0
        self.strobe = False

    def update(self, list buttons_state):
        """Update live button state from host input.

        Args:
            buttons_state: Sequence-like list of at least 8 truthy/falsy values
                in NES order `[A, B, Select, Start, Up, Down, Left, Right]`.

        Returns:
            None.

        Side Effects:
            Packs host input into `buttons` bitfield and, when strobe is active,
            updates the exposed shift register immediately.
        """
        self.buttons = 0
        if len(buttons_state) >= 8:
            if buttons_state[0]: self.buttons |= 0x01
            if buttons_state[1]: self.buttons |= 0x02
            if buttons_state[2]: self.buttons |= 0x04
            if buttons_state[3]: self.buttons |= 0x08
            if buttons_state[4]: self.buttons |= 0x10
            if buttons_state[5]: self.buttons |= 0x20
            if buttons_state[6]: self.buttons |= 0x40
            if buttons_state[7]: self.buttons |= 0x80
        
        if self.strobe:
            self.shift_reg = self.buttons

    cpdef public void write(self, uint8_t value):
        """Handle CPU write to controller strobe register `$4016`.

        Args:
            value: Raw 8-bit value written by CPU; bit 0 controls strobe.

        Returns:
            None.

        Side Effects:
            Updates strobe mode and latches current button state into
            `shift_reg` when required.
        """
        cdef bint new_strobe = (value & 1) != 0
        
        if self.strobe or new_strobe:
            self.shift_reg = self.buttons
            
        self.strobe = new_strobe

    cpdef public uint8_t read(self):
        """Read one serial controller bit.

        Args:
            None.

        Returns:
            uint8_t: Value with bit 0 set to current controller serial output
            and open-bus style high bits represented as `0x40`.

        Side Effects:
            In non-strobe mode, shifts `shift_reg` right after each read.
        """
        cdef uint8_t ret
        
        if self.strobe:
            ret = self.buttons & 1
        else:
            ret = self.shift_reg & 1
            self.shift_reg = (self.shift_reg >> 1) | 0x80
            
        return ret | 0x40