from libc.stdint cimport uint8_t, uint16_t

cdef class Mapper0:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cpdef public void write_prg(self, uint16_t address, uint8_t value)
    cpdef public void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper1:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef public object prg_ram
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef unsigned char[:] prg_ram_view
    cdef uint8_t shift_reg
    cdef uint8_t shift_count
    cdef uint8_t control
    cdef uint8_t chr_bank0
    cdef uint8_t chr_bank1
    cdef uint8_t prg_bank_reg

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cpdef public void write_prg(self, uint16_t address, uint8_t value)
    cpdef public void write_chr(self, uint16_t address, uint8_t value)

cdef class Mapper2:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef uint8_t prg_bank

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cpdef public void write_prg(self, uint16_t address, uint8_t value)

cdef class Mapper3:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef uint8_t chr_bank

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cpdef public void write_prg(self, uint16_t address, uint8_t value)

cdef class Mapper4:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef uint8_t bank_select
    cdef uint8_t bank_regs[8]
    cdef uint8_t prg_mode
    cdef uint8_t chr_mode
    cdef uint8_t mirroring
    cdef uint8_t irq_latch
    cdef uint8_t irq_counter
    cdef uint8_t irq_reload
    cdef uint8_t irq_enable
    cdef public uint8_t irq_pending
    cdef uint8_t last_a12

    cdef void _clock_irq_a12(self, uint16_t address)

    cpdef public uint8_t read_prg(self, uint16_t address)
    cpdef public uint8_t read_chr(self, uint16_t address)
    cpdef public void write_prg(self, uint16_t address, uint8_t value)
    cpdef public void write_chr(self, uint16_t address, uint8_t value)
