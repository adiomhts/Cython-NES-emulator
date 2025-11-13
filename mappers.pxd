# mappers.pxd
from libc.stdint cimport uint8_t, uint16_t

cdef class Mapper0:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper1:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef uint8_t prg_bank
    cdef uint8_t chr_bank

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper2:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef uint8_t prg_bank

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)

cdef class Mapper3:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef uint8_t chr_bank

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)

cdef class Mapper4:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef uint8_t prg_bank
    cdef uint8_t chr_bank

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)
