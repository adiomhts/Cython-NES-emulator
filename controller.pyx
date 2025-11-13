from libc.stdint cimport uint8_t, uint16_t

cdef class Controller:
    cdef public uint8_t state, shift_register

    def __init__(self):
        self.state = 0x00
        self.shift_register = 0x00
    
    def update_state(self, buttons):
        self.state = 0x00
        for i in range(8):
            if buttons[i]:
                self.state |= (1 << i)
        self.shift_register = self.state
    
    def write(self, value):
        if value & 1:
            self.shift_register = self.state
    
    cdef uint8_t read(self):
        cdef uint8_t bit = self.shift_register & 1
        self.shift_register >>= 1
        return bit