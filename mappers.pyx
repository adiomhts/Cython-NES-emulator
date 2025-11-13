import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t

cdef class Mapper0:
    def __init__(self, prg_rom, chr_rom):
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom

    cpdef public uint8_t read_prg(self, uint16_t address):
        if address >= 0x8000:
            return self.prg_rom_view[address % len(self.prg_rom_view)]
        return 0

    cpdef public uint8_t read_chr(self, uint16_t address):
        return self.chr_rom_view[address % len(self.chr_rom_view)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        if address >= 0x8000:
            self.prg_rom_view[address % len(self.prg_rom_view)] = value

    cdef void write_chr(self, uint16_t address, uint8_t value):
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value


cdef class Mapper1:
    def __init__(self, prg_rom, chr_rom):
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.prg_bank = 0
        self.chr_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        bank = self.prg_bank * 16384
        return self.prg_rom_view[bank + (address % 16384)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        bank = self.chr_bank * 8192
        return self.chr_rom_view[bank + (address % 8192)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.prg_bank = value & 0x0F

    cdef void write_chr(self, uint16_t address, uint8_t value):
        self.chr_bank = value & 0x1F


cdef class Mapper2:
    def __init__(self, prg_rom, chr_rom):
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.prg_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        bank = self.prg_bank * 16384
        return self.prg_rom_view[bank + (address % 16384)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        return self.chr_rom_view[address % len(self.chr_rom_view)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.prg_bank = value & 0x0F


cdef class Mapper3:
    def __init__(self, prg_rom, chr_rom):
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.chr_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        return self.prg_rom_view[address % len(self.prg_rom_view)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        bank = self.chr_bank * 8192
        return self.chr_rom_view[bank + (address % 8192)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.chr_bank = value & 0x1F


cdef class Mapper4:
    def __init__(self, prg_rom, chr_rom):
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.prg_bank = 0
        self.chr_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        bank = self.prg_bank * 16384
        return self.prg_rom_view[bank + (address % 16384)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        bank = self.chr_bank * 8192
        return self.chr_rom_view[bank + (address % 8192)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.prg_bank = value & 0x0F

    cdef void write_chr(self, uint16_t address, uint8_t value):
        self.chr_bank = value & 0x1F
