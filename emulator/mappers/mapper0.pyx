# Glossary (plain-language terms for this file):
# - Fixed mapping: Address windows always point to same ROM bytes.
# - Bank window: CPU/PPU address range exposing part of larger ROM.
# - CHR RAM cartridge: Board where graphics data is writable at runtime.
# - Mirroring by modulo: Wrapping addresses when ROM is smaller than window.
# NESdev references:
# - https://www.nesdev.org/wiki/NROM

# IDE Static Analysis Hints
if not "MapperBase" in globals():
    from mappers cimport MapperBase
    from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef class Mapper0(MapperBase):
    """Mapper 0 (NROM): fixed PRG/CHR mapping without bank switching.

    NESdev references:
    - https://www.nesdev.org/wiki/NROM
    """

    def __init__(self, prg_rom, chr_rom):
        """Initialize mapper with fixed PRG/CHR memory views.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.

        Side Effects:
            Stores references and creates typed views for fast indexed access.

        NESdev reference:
            https://www.nesdev.org/wiki/NROM
        """
        # NROM has no bank registers; map data directly.
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG byte from CPU-visible cartridge space.

        Args:
            address: CPU address, expected in '$8000-$FFFF'.

        Returns:
            uint8_t: Byte value from mapped PRG region.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_memory_map
            https://www.nesdev.org/wiki/NROM
        """
        # NROM mirrors by modulo when only one 16KB bank exists.
        if address >= 0x8000:
            return self.prg_rom_view[address % len(self.prg_rom_view)]
        return 0

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR byte for PPU pattern-table fetch.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte value from CHR storage.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_pattern_tables
            https://www.nesdev.org/wiki/NROM
        """
        return self.chr_rom_view[address % len(self.chr_rom_view)]

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        """Handle PRG writes in NROM context.

        Args:
            address: CPU cartridge address.
            value: Byte written by CPU.

        Returns:
            None.

        Side Effects:
            Some ROM hacks/tests expect writable behavior; this path mirrors
            writes into backing array even though original NROM PRG is ROM.
        """
        # NROM usually ignores PRG writes; this path allows RAM-like behavior.
        if address >= 0x8000:
            self.prg_rom_view[address % len(self.prg_rom_view)] = value

    cpdef public void write_chr(self, uint16_t address, uint8_t value):
        """Write CHR byte when cartridge uses CHR RAM.

        Args:
            address: PPU CHR address.
            value: Byte to store.

        Returns:
            None.

        Side Effects:
            Mutates CHR backing memory for CHR-RAM cartridges.
        """
        # CHR writes are meaningful only for CHR-RAM cartridges.
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value
