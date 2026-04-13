from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as cnp

cdef class Cartridge:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    
    cdef public uint8_t mapper, prg_banks, chr_banks, mirroring, battery_backed
    cdef public object mapper_instance
    cdef uint8_t read_prg(self, uint16_t address)
    cdef uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)
