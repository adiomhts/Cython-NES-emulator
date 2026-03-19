import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t

cdef class Mapper0:
    """Mapper 0 (NROM): fixed PRG/CHR mapping without bank switching."""

    def __init__(self, prg_rom, chr_rom):
        """Initialize mapper with fixed PRG/CHR memory views.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.

        Side Effects:
            Stores references and creates typed views for fast indexed access.
        """
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG byte from CPU-visible cartridge space.

        Args:
            address: CPU address, expected in `$8000-$FFFF`.

        Returns:
            uint8_t: Byte value from mapped PRG region.
        """
        if address >= 0x8000:
            return self.prg_rom_view[address % len(self.prg_rom_view)]
        return 0

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR byte for PPU pattern-table fetch.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte value from CHR storage.
        """
        return self.chr_rom_view[address % len(self.chr_rom_view)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        if address >= 0x8000:
            self.prg_rom_view[address % len(self.prg_rom_view)] = value

    cdef void write_chr(self, uint16_t address, uint8_t value):
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value


cdef class Mapper1:
    """Mapper 1 (MMC1-like placeholder) with coarse PRG/CHR bank selection."""

    def __init__(self, prg_rom, chr_rom):
        """Initialize mapper state and selected banks.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.

        Side Effects:
            Initializes active PRG/CHR bank selectors.
        """
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.prg_bank = 0
        self.chr_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG from selected 16KB bank.

        Args:
            address: CPU address in cartridge window.

        Returns:
            uint8_t: Byte from active PRG bank.
        """
        bank = self.prg_bank * 16384
        return self.prg_rom_view[bank + (address % 16384)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR from selected 8KB bank.

        Args:
            address: PPU address in CHR space.

        Returns:
            uint8_t: Byte from active CHR bank.
        """
        bank = self.chr_bank * 8192
        return self.chr_rom_view[bank + (address % 8192)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.prg_bank = value & 0x0F

    cdef void write_chr(self, uint16_t address, uint8_t value):
        self.chr_bank = value & 0x1F


cdef class Mapper2:
    """Mapper 2 (UxROM-like): switchable lower PRG bank with fixed CHR view."""

    def __init__(self, prg_rom, chr_rom):
        """Initialize PRG/CHR storage and active PRG bank index.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.
        """
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.prg_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG from active 16KB bank window.

        Args:
            address: CPU address in cartridge region.

        Returns:
            uint8_t: Byte from selected PRG bank.
        """
        bank = self.prg_bank * 16384
        return self.prg_rom_view[bank + (address % 16384)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR directly without CHR bank switching.

        Args:
            address: PPU address in CHR space.

        Returns:
            uint8_t: Byte from CHR storage.
        """
        return self.chr_rom_view[address % len(self.chr_rom_view)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.prg_bank = value & 0x0F


cdef class Mapper3:
    """Mapper 3 (CNROM-like): fixed PRG with switchable CHR bank."""

    def __init__(self, prg_rom, chr_rom):
        """Initialize PRG/CHR buffers and CHR bank state.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.
        """
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.chr_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG from fixed ROM mapping.

        Args:
            address: CPU address in cartridge region.

        Returns:
            uint8_t: Byte from fixed PRG mapping.
        """
        return self.prg_rom_view[address % len(self.prg_rom_view)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR from active CNROM bank.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte from selected CHR bank.
        """
        bank = self.chr_bank * 8192
        return self.chr_rom_view[bank + (address % 8192)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.chr_bank = value & 0x1F


cdef class Mapper4:
    """Mapper 4 (MMC3-like placeholder) with basic PRG/CHR bank selection."""

    def __init__(self, prg_rom, chr_rom):
        """Initialize banked PRG/CHR state for mapper 4 emulation paths.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.
        """
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.prg_bank = 0
        self.chr_bank = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG from selected mapper 4 PRG bank.

        Args:
            address: CPU address in cartridge region.

        Returns:
            uint8_t: Byte from selected PRG bank.
        """
        bank = self.prg_bank * 16384
        return self.prg_rom_view[bank + (address % 16384)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR from selected mapper 4 CHR bank.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte from selected CHR bank.
        """
        bank = self.chr_bank * 8192
        return self.chr_rom_view[bank + (address % 8192)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.prg_bank = value & 0x0F

    cdef void write_chr(self, uint16_t address, uint8_t value):
        self.chr_bank = value & 0x1F
