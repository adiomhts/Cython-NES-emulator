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

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        if address >= 0x8000:
            self.prg_rom_view[address % len(self.prg_rom_view)] = value

    cpdef public void write_chr(self, uint16_t address, uint8_t value):
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value


cdef class Mapper1:
    """Mapper 1 (MMC1-like) with serial register writes and PRG-RAM support."""

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
            address: CPU address in cartridge window (`$6000-$FFFF`).

        Returns:
            uint8_t: Byte from PRG-RAM (`$6000-$7FFF`) or mapped PRG-ROM bank.
        """
        cdef int prg_banks_16k
        cdef int bank, offset
        cdef int mode

        if 0x6000 <= address < 0x8000:
            return self.prg_ram_view[address - 0x6000]

        prg_banks_16k = len(self.prg_rom_view) // 0x4000
        if prg_banks_16k <= 0:
            return 0

        mode = (self.control >> 2) & 0x03
        if mode == 0 or mode == 1:
            bank = (self.prg_bank_reg & 0x0E) % prg_banks_16k
            if address < 0xC000:
                offset = bank * 0x4000 + (address - 0x8000)
            else:
                offset = ((bank + 1) % prg_banks_16k) * 0x4000 + (address - 0xC000)
        elif mode == 2:
            if address < 0xC000:
                offset = address - 0x8000
            else:
                bank = self.prg_bank_reg % prg_banks_16k
                offset = bank * 0x4000 + (address - 0xC000)
        else:
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
        """
        cdef int chr_len
        cdef int chr_mode
        cdef int bank, offset

        chr_len = len(self.chr_rom_view)
        if chr_len <= 0:
            return 0

        chr_mode = (self.control >> 4) & 0x01
        if chr_mode == 0:
            bank = (self.chr_bank0 & 0x1E) * 0x1000
            offset = bank + (address & 0x1FFF)
        elif address < 0x1000:
            bank = self.chr_bank0 * 0x1000
            offset = bank + address
        else:
            bank = self.chr_bank1 * 0x1000
            offset = bank + (address - 0x1000)

        return self.chr_rom_view[offset % chr_len]

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        """Write MMC1 control stream or PRG-RAM.

        Args:
            address: CPU address in `$6000-$FFFF`.
            value: Value written by CPU.

        Returns:
            None.

        Side Effects:
            Writes PRG-RAM in `$6000-$7FFF` and updates MMC1 serial register
            state for `$8000-$FFFF` control/bank writes.
        """
        cdef uint8_t reg_target, reg_val

        if 0x6000 <= address < 0x8000:
            self.prg_ram_view[address - 0x6000] = value
            return

        if address < 0x8000:
            return

        if value & 0x80:
            self.shift_reg = 0
            self.shift_count = 0
            self.control |= 0x0C
            return

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
        """
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value


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
        cdef int prg_banks_16k
        cdef int bank
        cdef int offset

        prg_banks_16k = len(self.prg_rom_view) // 0x4000
        if prg_banks_16k <= 0:
            return 0

        if address < 0xC000:
            bank = self.prg_bank % prg_banks_16k
            offset = bank * 0x4000 + (address - 0x8000)
        else:
            bank = prg_banks_16k - 1
            offset = bank * 0x4000 + (address - 0xC000)

        return self.prg_rom_view[offset % len(self.prg_rom_view)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR directly without CHR bank switching.

        Args:
            address: PPU address in CHR space.

        Returns:
            uint8_t: Byte from CHR storage.
        """
        return self.chr_rom_view[address % len(self.chr_rom_view)]

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        """Select switchable UxROM lower 16KB PRG bank.

        Args:
            address: CPU cartridge address.
            value: Bank register value.

        Returns:
            None.
        """
        cdef int prg_banks_16k

        prg_banks_16k = len(self.prg_rom_view) // 0x4000
        if prg_banks_16k <= 0:
            self.prg_bank = 0
            return

        self.prg_bank = <uint8_t>((value & 0x0F) % prg_banks_16k)


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
        cdef int chr_banks_8k
        cdef int bank
        cdef int offset

        chr_banks_8k = len(self.chr_rom_view) // 0x2000
        if chr_banks_8k <= 0:
            return 0

        bank = self.chr_bank % chr_banks_8k
        offset = bank * 0x2000 + (address & 0x1FFF)
        return self.chr_rom_view[offset % len(self.chr_rom_view)]

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        """Select active CNROM 8KB CHR bank.

        Args:
            address: CPU cartridge address.
            value: CHR bank register value.

        Returns:
            None.
        """
        cdef int chr_banks_8k

        chr_banks_8k = len(self.chr_rom_view) // 0x2000
        if chr_banks_8k <= 0:
            self.chr_bank = 0
            return

        self.chr_bank = <uint8_t>((value & 0x1F) % chr_banks_8k)


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
        self.bank_select = 0
        self.prg_mode = 0
        self.chr_mode = 0
        self.mirroring = 0
        self.irq_latch = 0
        self.irq_counter = 0
        self.irq_reload = 0
        self.irq_enable = 0
        self.irq_pending = 0
        self.last_a12 = 0
        self.bank_regs[0] = 0
        self.bank_regs[1] = 0
        self.bank_regs[2] = 0
        self.bank_regs[3] = 0
        self.bank_regs[4] = 0
        self.bank_regs[5] = 0
        self.bank_regs[6] = 0
        self.bank_regs[7] = 1

    cdef void _clock_irq_a12(self, uint16_t address):
        cdef uint8_t a12

        a12 = 1 if (address & 0x1000) else 0
        if a12 and not self.last_a12:
            if self.irq_counter == 0 or self.irq_reload:
                self.irq_counter = self.irq_latch
                self.irq_reload = 0
            else:
                self.irq_counter -= 1

            if self.irq_counter == 0 and self.irq_enable:
                self.irq_pending = 1

        self.last_a12 = a12

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG from selected mapper 4 PRG bank.

        Args:
            address: CPU address in cartridge region.

        Returns:
            uint8_t: Byte from selected PRG bank.
        """
        cdef int prg_banks_8k
        cdef int last_bank, last_bank2
        cdef int b6, b7, bank, offset

        prg_banks_8k = len(self.prg_rom_view) // 0x2000
        if prg_banks_8k <= 0:
            return 0

        last_bank = prg_banks_8k - 1
        last_bank2 = last_bank - 1 if last_bank > 0 else 0
        b6 = self.bank_regs[6] % prg_banks_8k
        b7 = self.bank_regs[7] % prg_banks_8k

        if address < 0xA000:
            bank = last_bank2 if self.prg_mode else b6
        elif address < 0xC000:
            bank = b7
        elif address < 0xE000:
            bank = b6 if self.prg_mode else last_bank2
        else:
            bank = last_bank

        offset = bank * 0x2000 + (address & 0x1FFF)
        return self.prg_rom_view[offset % len(self.prg_rom_view)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR from selected mapper 4 CHR bank.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte from selected CHR bank.
        """
        cdef int chr_banks_1k
        cdef int idx, bank, offset
        cdef int r0, r1

        self._clock_irq_a12(address)
        chr_banks_1k = len(self.chr_rom_view) // 0x400
        if chr_banks_1k <= 0:
            return 0

        idx = (address >> 10) & 0x07
        r0 = self.bank_regs[0] & 0xFE
        r1 = self.bank_regs[1] & 0xFE

        if self.chr_mode == 0:
            if idx == 0:
                bank = r0
            elif idx == 1:
                bank = r0 + 1
            elif idx == 2:
                bank = r1
            elif idx == 3:
                bank = r1 + 1
            else:
                bank = self.bank_regs[idx + 2]
        else:
            if idx <= 3:
                bank = self.bank_regs[idx + 2]
            elif idx == 4:
                bank = r0
            elif idx == 5:
                bank = r0 + 1
            elif idx == 6:
                bank = r1
            else:
                bank = r1 + 1

        bank = bank % chr_banks_1k
        offset = bank * 0x400 + (address & 0x03FF)
        return self.chr_rom_view[offset % len(self.chr_rom_view)]

    cpdef public void write_prg(self, uint16_t address, uint8_t value):
        """Handle MMC3 register writes for banking, mirroring, and IRQ control.

        Args:
            address: CPU address in `$8000-$FFFF`.
            value: Register payload.

        Returns:
            None.
        """
        if 0x8000 <= address < 0xA000:
            if (address & 1) == 0:
                self.bank_select = value & 0x07
                self.prg_mode = (value >> 6) & 1
                self.chr_mode = (value >> 7) & 1
            else:
                self.bank_regs[self.bank_select] = value
        elif 0xA000 <= address < 0xC000:
            if (address & 1) == 0:
                self.mirroring = value & 1
        elif 0xC000 <= address < 0xE000:
            if (address & 1) == 0:
                self.irq_latch = value
            else:
                self.irq_reload = 1
        elif 0xE000 <= address <= 0xFFFF:
            if (address & 1) == 0:
                self.irq_enable = 0
                self.irq_pending = 0
            else:
                self.irq_enable = 1

    cpdef public void write_chr(self, uint16_t address, uint8_t value):
        """Write CHR RAM when mapper cartridge provides writable CHR memory.

        Args:
            address: PPU CHR address.
            value: CHR byte value.

        Returns:
            None.
        """
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value
