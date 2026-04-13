# Glossary (plain-language terms for this file):
# - Serial register write: Hardware command assembled bit-by-bit over several writes.
# - PRG-RAM: Writable cartridge memory used for saves/runtime state.
# - 16KB/32KB mode: Size of PRG chunk currently switched into CPU space.
# - Even-aligned bank: Bank index forced to even value so adjacent pair can be mapped.
# - Control register: Mapper mode register deciding PRG/CHR banking behavior.
# NESdev references:
# - https://www.nesdev.org/wiki/MMC1

# IDE Static Analysis Hints
if not "MapperBase" in globals():
    from mappers cimport MapperBase
    from libc.stdint cimport uint8_t, uint16_t
    import numpy as np

    

cdef class Mapper1(MapperBase):
    """Mapper 1 (MMC1-like) with serial register writes and PRG-RAM support.

    NESdev references:
    - https://www.nesdev.org/wiki/Mapper_001
    - https://www.nesdev.org/wiki/MMC1
    """

    def __init__(self, prg_rom, chr_rom):
        """Initialize mapper state and selected banks.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.

        Side Effects:
            Allocates PRG-RAM and resets serial register state.
        """
        # ROM/RAM buffers plus serial shift-register state.
        self.prg_rom = prg_rom
        self.chr_rom = chr_rom
        self.prg_ram = np.zeros(0x2000, dtype=np.uint8)
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom
        self.prg_ram_view = self.prg_ram
        self.shift_reg = 0
        self.shift_count = 0
        self.control = 0x0C
        self.chr_bank0 = 0
        self.chr_bank1 = 0
        self.prg_bank_reg = 0

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG-RAM/PRG-ROM using MMC1 banking rules.

        Args:
            address: CPU address in cartridge window ('$6000-$FFFF').

        Returns:
            uint8_t: Byte from PRG-RAM ('$6000-$7FFF') or mapped PRG-ROM bank.

        NESdev references:
            https://www.nesdev.org/wiki/MMC1
            https://www.nesdev.org/wiki/CPU_memory_map
        """
        cdef int prg_banks_16k
        cdef int bank, offset
        cdef int mode

        if 0x6000 <= address < 0x8000:
            # Separate writable PRG-RAM window used by saves/runtime state.
            return self.prg_ram_view[address - 0x6000]

        prg_banks_16k = len(self.prg_rom_view) // 0x4000
        if prg_banks_16k <= 0:
            return 0

        mode = (self.control >> 2) & 0x03
        if mode == 0 or mode == 1:
            # 32KB PRG banking (two adjacent 16KB banks).
            bank = (self.prg_bank_reg & 0x0E) % prg_banks_16k
            if address < 0xC000:
                offset = bank * 0x4000 + (address - 0x8000)
            else:
                offset = ((bank + 1) % prg_banks_16k) * 0x4000 + (address - 0xC000)
        elif mode == 2:
            # Fix first bank at $8000, switch bank at $C000.
            if address < 0xC000:
                offset = address - 0x8000
            else:
                bank = self.prg_bank_reg % prg_banks_16k
                offset = bank * 0x4000 + (address - 0xC000)
        else:
            # Switch bank at $8000, fix last bank at $C000.
            if address < 0xC000:
                bank = self.prg_bank_reg % prg_banks_16k
                offset = bank * 0x4000 + (address - 0x8000)
            else:
                offset = (prg_banks_16k - 1) * 0x4000 + (address - 0xC000)

        return self.prg_rom_view[offset % len(self.prg_rom_view)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR using MMC1 8KB/4KB bank mode.

        Args:
            address: PPU address in CHR space.

        Returns:
            uint8_t: Byte from active CHR bank.

        NESdev references:
            https://www.nesdev.org/wiki/MMC1
            https://www.nesdev.org/wiki/PPU_pattern_tables
        """
        cdef int chr_len
        cdef int chr_mode
        cdef int bank, offset

        chr_len = len(self.chr_rom_view)
        if chr_len <= 0:
            return 0

        chr_mode = (self.control >> 4) & 0x01
        if chr_mode == 0:
            # 8KB CHR mode: one even-aligned bank covers full pattern space.
            bank = (self.chr_bank0 & 0x1E) * 0x1000
            offset = bank + (address & 0x1FFF)
        elif address < 0x1000:
            # 4KB CHR mode: lower pattern-table half.
            bank = self.chr_bank0 * 0x1000
            offset = bank + address
        else:
            # 4KB CHR mode: upper pattern-table half.
            bank = self.chr_bank1 * 0x1000
            offset = bank + (address - 0x1000)

        return self.chr_rom_view[offset % chr_len]

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        """Write MMC1 control stream or PRG-RAM.

        Args:
            address: CPU address in '$6000-$FFFF'.
            value: Value written by CPU.

        Returns:
            None.

        Side Effects:
            Writes PRG-RAM in '$6000-$7FFF' and updates MMC1 serial register
            state for '$8000-$FFFF' control/bank writes.

        Notes:
            MMC1 does not accept full command in one write; five writes are
            needed to fully load one internal register.
        """
        cdef uint8_t reg_target, reg_val

        if 0x6000 <= address < 0x8000:
            # PRG-RAM region is directly writable.
            self.prg_ram_view[address - 0x6000] = value
            return

        if address < 0x8000:
            return

        if value & 0x80:
            # Reset command: clear shift register and restore safe control bits.
            self.shift_reg = 0
            self.shift_count = 0
            self.control |= 0x0C
            return

        # Serial protocol: 5 writes accumulate one internal register payload.
        self.shift_reg |= (value & 1) << self.shift_count
        self.shift_count += 1

        if self.shift_count < 5:
            return

        reg_val = self.shift_reg & 0x1F
        reg_target = (address >> 13) & 0x03
        if reg_target == 0:
            self.control = reg_val
        elif reg_target == 1:
            self.chr_bank0 = reg_val
        elif reg_target == 2:
            self.chr_bank1 = reg_val
        else:
            self.prg_bank_reg = reg_val & 0x0F

        self.shift_reg = 0
        self.shift_count = 0

    cpdef public void write_chr(self, uint16_t address, uint8_t value):
        """Write CHR RAM when cartridge exposes writable CHR storage.

        Args:
            address: PPU CHR address.
            value: CHR byte value.

        Returns:
            None.

        Side Effects:
            Updates CHR RAM contents on cartridges that expose writable CHR.
        """
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value
