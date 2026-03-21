from libc.stdint cimport uint8_t

# Glossary (terms used in comments/docstrings in this file):
# - Strobe: Controller latch mode controlled by bit0 writes to `$4016`.
# - Shift register: Serial output register read bit-by-bit by CPU.
# - Open bus: Hardware behavior where unrelated bits may retain prior state.
# NESdev references:
# - https://www.nesdev.org/wiki/Controller_reading
# - https://www.nesdev.org/wiki/Standard_controller

cdef class Controller:
    """NES standard controller serial latch and shift-register behavior.

    Emulates the strobe/write and serial read behavior used through register
    `$4016`.

    NESdev references:
    - https://www.nesdev.org/wiki/Controller_reading
    - https://www.nesdev.org/wiki/Standard_controller
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

        NESdev reference:
            https://www.nesdev.org/wiki/Controller_reading
        """
        # Packed live button bits (A..Right).
        self.buttons = 0
        # Shift register exposed over serial reads at $4016/$4017.
        self.shift_reg = 0
        # Strobe high means always return current A button bit.
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

        NESdev references:
            https://www.nesdev.org/wiki/Controller_reading
            https://www.nesdev.org/wiki/Standard_controller#Input
        """
        # Rebuild packed bitfield from current host button snapshot.
        self.buttons = 0
        if len(buttons_state) >= 8:
            # Bit 0: A
            if buttons_state[0]: self.buttons |= 0x01
            # Bit 1: B
            if buttons_state[1]: self.buttons |= 0x02
            # Bit 2: Select
            if buttons_state[2]: self.buttons |= 0x04
            # Bit 3: Start
            if buttons_state[3]: self.buttons |= 0x08
            # Bit 4: Up
            if buttons_state[4]: self.buttons |= 0x10
            # Bit 5: Down
            if buttons_state[5]: self.buttons |= 0x20
            # Bit 6: Left
            if buttons_state[6]: self.buttons |= 0x40
            # Bit 7: Right
            if buttons_state[7]: self.buttons |= 0x80
        
        # With strobe enabled, serial output mirrors live button latch.
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

        NESdev references:
            https://www.nesdev.org/wiki/Controller_reading
            https://www.nesdev.org/wiki/Standard_controller#Input_$4016_Write
        """
        # Bit 0 controls strobe (1=latch repeatedly, 0=shift on reads).
        cdef bint new_strobe = (value & 1) != 0
        
        # Latch buttons when entering strobe mode or while strobe is high.
        if self.strobe or new_strobe:
            self.shift_reg = self.buttons
            
        # Commit new strobe state after optional latch.
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

        NESdev references:
            https://www.nesdev.org/wiki/Controller_reading
            https://www.nesdev.org/wiki/Standard_controller#Input_$4016.2F$4017_Read
        """
        cdef uint8_t ret
        
        # Strobe mode: always expose current A bit (bit 0).
        if self.strobe:
            ret = self.buttons & 1
        else:
            # Shift mode: return low bit, then shift toward next button.
            ret = self.shift_reg & 1
            # Hardware returns 1s after 8 reads; emulate by shifting in 1.
            self.shift_reg = (self.shift_reg >> 1) | 0x80
            
        # Preserve open-bus style high bits with bit 6 set.
        return ret | 0x40