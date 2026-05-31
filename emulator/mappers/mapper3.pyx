# Glossary (plain-language terms for this file):
# - CHR bank select: Register choosing which graphics chunk PPU sees.
# - Fixed PRG mapping: Program ROM stays static while graphics banks switch.
# - 8KB CHR page: One full pattern-table address space chunk.
# NESdev references:
# - https://www.nesdev.org/wiki/CNROM

# IDE Static Analysis Hints
if not "MapperBase" in globals():
    from mappers cimport MapperBase
    from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef class Mapper3(MapperBase):
    """Mapper 3 (CNROM-like): fixed PRG with switchable CHR bank.

    NESdev references:
    - https://www.nesdev.org/wiki/CNROM
    """

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

        Side Effects:
            None.
        """
        return self.prg_rom_view[address % len(self.prg_rom_view)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR from active CNROM bank.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte from selected CHR bank.

        Side Effects:
            None; selection state comes from previous bank-write command.
        """
        cdef int chr_banks_8k
        cdef int bank
        cdef int offset

        chr_banks_8k = len(self.chr_rom_view) // 0x2000
        if chr_banks_8k <= 0:
            return 0

        bank = self.chr_bank % chr_banks_8k
        # CNROM maps one full 8KB CHR bank into pattern-table space.
        offset = bank * 0x2000 + (address & 0x1FFF)
        return self.chr_rom_view[offset % len(self.chr_rom_view)]

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        """Select active CNROM 8KB CHR bank.

        Args:
            address: CPU cartridge address.
            value: CHR bank register value.

        Returns:
            None.

        Side Effects:
            Updates active CHR bank used by subsequent PPU reads.
        """
        cdef int chr_banks_8k

        chr_banks_8k = len(self.chr_rom_view) // 0x2000
        if chr_banks_8k <= 0:
            self.chr_bank = 0
            return

        # CNROM bank select usually lives in low bits.
        self.chr_bank = <uint8_t>((value & 0x1F) % chr_banks_8k)

    cpdef public void write_chr(self, uint16_t address, uint8_t value):
        """Handle CHR writes when carriage uses CHR RAM.

        Args:
            address: PPU CHR address.
            value: Byte to store.

        Returns:
            None.

        Side Effects:
            Stores byte in CHR RAM backing array.
        """
        self.chr_rom_view[address % len(self.chr_rom_view)] = value
