"""Cython definitions for NES cartridge mappers.

This file establishes the Virtual Method Table (VTable) interface for all mappers.
By declaring these methods as `cdef` here, the CPU and PPU can bypass Python's 
dynamic dispatch (getattr) and call the C-functions directly, resulting in 
massive performance gains for memory reads/writes.
"""

from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as cnp

cdef class MapperBase:
    """Base class for all Mappers, defining the C-level interface."""
    cdef public object prg_rom
    cdef public object chr_rom
    cdef public uint8_t[:] prg_rom_view
    cdef public uint8_t[:] chr_rom_view
    cdef public uint8_t mirroring
    cdef public bint irq_pending
    cdef void clock_irq(self)
    cdef uint8_t read_prg(self, uint16_t address)
    cdef uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper0(MapperBase):
    cdef uint8_t read_prg(self, uint16_t address)
    cdef uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper1(MapperBase):
    cdef public uint8_t[:] prg_ram
    cdef public uint8_t[:] prg_ram_view
    cdef public uint8_t shift_reg, shift_count, control, chr_bank0, chr_bank1, prg_bank_reg
    cdef uint8_t read_prg(self, uint16_t address)
    cdef uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper2(MapperBase):
    cdef public int prg_bank
    cdef uint8_t read_prg(self, uint16_t address)
    cdef uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper3(MapperBase):
    cdef public int chr_bank
    cdef uint8_t read_prg(self, uint16_t address)
    cdef uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper4(MapperBase):
    cdef public uint8_t[:] prg_ram
    cdef public uint8_t[:] prg_ram_view
    cdef public uint8_t bank_select, prg_mode, chr_mode, irq_latch, irq_counter, irq_reload, irq_enable, last_a12
    cdef public uint8_t bank_regs[8]
    cdef uint8_t read_prg(self, uint16_t address)
    cdef uint8_t read_chr(self, uint16_t address)
    cdef void write_prg(self, uint16_t address, uint8_t value)
    cdef void write_chr(self, uint16_t address, uint8_t value)
    cdef void _clock_irq_a12(self, uint16_t address)
