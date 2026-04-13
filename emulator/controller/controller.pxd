from libc.stdint cimport uint8_t

cdef class Controller:
    cdef uint8_t buttons
    cdef uint8_t shift_reg
    cdef bint strobe

    cpdef public uint8_t read(self)
    cpdef public void write(self, uint8_t value)
    cpdef public void update(self, list buttons_state)
