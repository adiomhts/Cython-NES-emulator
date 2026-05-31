# Glossary (plain-language terms for this file):
# - Switchable window: Address range whose bank can be changed by game code.
# - Fixed upper bank: Region permanently mapped to last PRG bank.
# - Bank register: Mapper byte storing currently selected bank index.
# - Mapping mode: Rule deciding which ROM chunk is visible at each address.
# NESdev references:
# - https://www.nesdev.org/wiki/UxROM

# IDE Static Analysis Hints
if not "MapperBase" in globals():
    from mappers cimport MapperBase
    from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef class Mapper2(MapperBase):
    """Mapper 2 (UxROM-like): switchable lower PRG bank with fixed CHR view.

    NESdev references:
    - https://www.nesdev.org/wiki/UxROM
    """

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

    cdef uint8_t read_prg(self, uint16_t address):
        """Read PRG from active 16KB bank window.

        Args:
            address: CPU address in cartridge region.

        Returns:
            uint8_t: Byte from selected PRG bank.

        Side Effects:
            None; this is a pure read from the currently selected mapping.
        """
        cdef int prg_banks_16k
        cdef int bank
        cdef int offset

        prg_banks_16k = len(self.prg_rom_view) // 0x4000
        if prg_banks_16k <= 0:
            return 0

        if address < 0xC000:
            # $8000-$BFFF is switchable bank.
            bank = self.prg_bank % prg_banks_16k
            offset = bank * 0x4000 + (address - 0x8000)
        else:
            # $C000-$FFFF is fixed to last bank.
            bank = prg_banks_16k - 1
            offset = bank * 0x4000 + (address - 0xC000)

        return self.prg_rom_view[offset % len(self.prg_rom_view)]

    cdef uint8_t read_chr(self, uint16_t address):
        """Read CHR directly without CHR bank switching.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte from CHR storage.

        Notes:
            UxROM cartridges usually keep CHR fixed (often CHR RAM).
        """
        return self.chr_rom_view[address % len(self.chr_rom_view)]

    cdef void write_prg(self, uint16_t address, uint8_t value):
        """Select switchable UxROM lower 16KB PRG bank.

        Args:
            address: CPU cartridge address.
            value: Bank register value.

        Returns:
            None.

        Side Effects:
            Changes active low PRG bank visible at '$8000-$BFFF'.
        """
        cdef int prg_banks_16k

        prg_banks_16k = len(self.prg_rom_view) // 0x4000
        if prg_banks_16k <= 0:
            self.prg_bank = 0
            return

        # UxROM uses the full byte for bank id (though standard boards only use a few bits). This implementation masks the lower nibble.
        self.prg_bank = <uint8_t>((value & 0x0F) % prg_banks_16k)

    cdef void write_chr(self, uint16_t address, uint8_t value):
        """Handle CHR writes when cartridge uses CHR RAM.

        Args:
            address: PPU CHR address.
            value: Byte to store.

        Returns:
            None.

        Side Effects:
            Stores byte in CHR RAM backing array.
        """
        self.chr_rom_view[address % len(self.chr_rom_view)] = value
