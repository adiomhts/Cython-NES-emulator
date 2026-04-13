# Glossary (plain-language terms for this file):
# - Rising edge: Signal transition from 0 to 1 used as hardware trigger.
# - IRQ latch/counter: Pair of registers controlling when interrupt fires.
# - Inverted CHR mode: Alternate slot layout where 1KB and 2KB regions swap.
# - Fixed last bank: Top program window permanently mapped to last PRG bank.
# - Register pair write: Even address selects command, odd writes command data.
# NESdev references:
# - https://www.nesdev.org/wiki/MMC3

# IDE Static Analysis Hints
if not "MapperBase" in globals():
    from mappers cimport MapperBase
    from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef class Mapper4(MapperBase):
    """Mapper 4 (MMC3-like) with PRG/CHR banking and IRQ logic.

    NESdev references:
    - https://www.nesdev.org/wiki/Mapper_004
    - https://www.nesdev.org/wiki/MMC3
    """

    def __init__(self, prg_rom, chr_rom):
        """Initialize banked PRG/CHR state for mapper 4 emulation paths.

        Args:
            prg_rom: PRG ROM byte array.
            chr_rom: CHR ROM/RAM byte array.

        Returns:
            None.

        Side Effects:
            Initializes bank registers, IRQ latches/counters, and mirroring bit.
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
        """Clock MMC3 IRQ counter on PPU A12 rising edge.

        Args:
            address: Current CHR fetch address from PPU.

        Returns:
            None.

        Side Effects:
            Updates internal IRQ counter/latch and may set `irq_pending`.
        """
        cdef uint8_t a12

        # A12 bit toggles when PPU fetches from upper/lower pattern halves.
        a12 = 1 if (address & 0x1000) else 0
        if a12 and not self.last_a12:
            # Rising edge is the moment MMC3 updates its IRQ counter.
            if self.irq_counter == 0 or self.irq_reload:
                # Reload path copies latch into counter.
                self.irq_counter = self.irq_latch
                self.irq_reload = 0
            else:
                # Normal path decrements counter.
                self.irq_counter -= 1

            if self.irq_counter == 0 and self.irq_enable:
                # CPU will consume this pending IRQ on next instruction boundary.
                self.irq_pending = 1

        # Store previous A12 level to detect next edge.
        self.last_a12 = a12

    cpdef public uint8_t read_prg(self, uint16_t address):
        """Read PRG from selected mapper 4 PRG bank.

        Args:
            address: CPU address in cartridge region.

        Returns:
            uint8_t: Byte from selected PRG bank.

        NESdev references:
            https://www.nesdev.org/wiki/MMC3
            https://www.nesdev.org/wiki/CPU_memory_map
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
            # First 8KB slot swaps with bank register 6 depending on PRG mode.
            bank = last_bank2 if self.prg_mode else b6
        elif address < 0xC000:
            # Second slot always follows bank register 7.
            bank = b7
        elif address < 0xE000:
            # Third slot is complement of first slot (mode-dependent).
            bank = b6 if self.prg_mode else last_bank2
        else:
            # Last slot fixed to last bank.
            bank = last_bank

        offset = bank * 0x2000 + (address & 0x1FFF)
        return self.prg_rom_view[offset % len(self.prg_rom_view)]

    cpdef public uint8_t read_chr(self, uint16_t address):
        """Read CHR from selected mapper 4 CHR bank.

        Args:
            address: PPU CHR address.

        Returns:
            uint8_t: Byte from selected CHR bank.

        NESdev references:
            https://www.nesdev.org/wiki/MMC3
            https://www.nesdev.org/wiki/PPU_pattern_tables
        """
        cdef int chr_banks_1k
        cdef int idx, bank, offset
        cdef int r0, r1

        # MMC3 IRQ logic is tied to A12 transitions during CHR fetches.
        self._clock_irq_a12(address)
        chr_banks_1k = len(self.chr_rom_view) // 0x400
        if chr_banks_1k <= 0:
            return 0

        idx = (address >> 10) & 0x07
        r0 = self.bank_regs[0] & 0xFE
        r1 = self.bank_regs[1] & 0xFE

        if self.chr_mode == 0:
            # Normal CHR mode: 2KB pairs first, then four 1KB slots.
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
            # Inverted CHR mode swaps high/low slot arrangement.
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
            address: CPU address in '$8000-$FFFF'.
            value: Register payload.

        Returns:
            None.

        NESdev references:
            https://www.nesdev.org/wiki/MMC3
            https://www.nesdev.org/wiki/Mapper_004
        """
        if 0x8000 <= address < 0xA000:
            if (address & 1) == 0:
                # Even write: choose bank register and mode bits.
                self.bank_select = value & 0x07
                self.prg_mode = (value >> 6) & 1
                self.chr_mode = (value >> 7) & 1
            else:
                # Odd write: payload for selected bank register.
                self.bank_regs[self.bank_select] = value
        elif 0xA000 <= address < 0xC000:
            if (address & 1) == 0:
                # Mirroring control for supported board variants.
                self.mirroring = value & 1
        elif 0xC000 <= address < 0xE000:
            if (address & 1) == 0:
                # IRQ latch update.
                self.irq_latch = value
            else:
                # Request reload on next A12 edge.
                self.irq_reload = 1
        elif 0xE000 <= address <= 0xFFFF:
            if (address & 1) == 0:
                # Disable IRQ and clear pending level.
                self.irq_enable = 0
                self.irq_pending = 0
            else:
                # Enable IRQ generation.
                self.irq_enable = 1

    cpdef public void write_chr(self, uint16_t address, uint8_t value):
        """Write CHR RAM when mapper cartridge provides writable CHR memory.

        Args:
            address: PPU CHR address.
            value: CHR byte value.

        Returns:
            None.

        Side Effects:
            Mutates CHR RAM data if cartridge provides writable CHR storage.
        """
        if len(self.chr_rom_view) > 0:
            self.chr_rom_view[address % len(self.chr_rom_view)] = value
