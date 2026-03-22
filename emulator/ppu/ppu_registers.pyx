# Glossary (plain-language terms for this PPU section):
# - Buffered read: '$2007' returns delayed data for most regions.
# - Write toggle: Alternating first/second write state for '$2005'/'$2006'.
# - OAMADDR/OAMDATA: Sprite memory pointer/data registers.
# - Canonical register: Mirrored register collapsed to '$2000-$2007'.
# NESdev references:
# - https://www.nesdev.org/wiki/PPU_registers
# - https://www.nesdev.org/wiki/PPU_scrolling

cpdef void ppu_write_register(PPU self, uint16_t reg, uint8_t value):
    """Handles CPU writes to the eight memory-mapped PPU registers.

    These registers control all aspects of the PPU's operation. They are
    mirrored every 8 bytes from $2000-$3FFF in the CPU's address space.

    Args:
        self: The active PPU instance.
        reg: The CPU-visible register address ($2000-$2007, mirrored).
        value: The byte value written by the CPU.

    Side Effects:
        Modifies PPU control state, scrolling latches, memory pointers, and
        VRAM/OAM/palette data. Many writes have complex side effects on
        internal PPU state, especially the scrolling registers.
    """
    cdef int addr, phys, pal_addr
    # PPU registers are mirrored every 8 bytes. We only care about the lowest 3 bits.
    reg = reg & 0x2007

    if reg == 0x2000:  # PPUCTRL
        # This register controls core PPU functions.
        self.ctrl = value
        # Update the nametable select bits in the temporary scroll register 't'.
        self.t = (self.t & 0xF3FF) | ((value & 0x03) << 10)
    elif reg == 0x2001:  # PPUMASK
        # This register controls the rendering of sprites and background.
        self.mask = value
    elif reg == 0x2002:  # PPUSTATUS
        # This register is read-only. Writes have no effect.
        pass
    elif reg == 0x2003:  # OAMADDR
        # Sets the address for OAM (sprite memory) reads/writes.
        self.oam_addr = value
    elif reg == 0x2004:  # OAMDATA
        # Writes a byte to OAM at the current OAM address, then increments the address.
        self.oam_data[self.oam_addr] = value
        self.oam_addr += 1
    elif reg == 0x2005:  # PPUSCROLL
        # This register is written to twice to set scroll X and Y positions.
        # A 'write toggle' (w) tracks which write is which.
        if self.write_toggle == 0:
            # First write: sets horizontal scroll.
            self.scroll_x = value
            self.fine_x = value & 0x07  # Bottom 3 bits are fine X scroll.
            self.t = (self.t & 0xFFE0) | (value >> 3)  # Top 5 bits are coarse X scroll.
            self.write_toggle = 1
        else:
            # Second write: sets vertical scroll.
            self.scroll_y = value
            self.t = (self.t & 0x8FFF) | ((value & 0x07) << 12)  # Fine Y scroll
            self.t = (self.t & 0xFC1F) | ((value & 0xF8) << 2)   # Coarse Y scroll
            self.write_toggle = 0
    elif reg == 0x2006:  # PPUADDR
        # This register is written to twice to set the VRAM address for reads/writes.
        if self.write_toggle == 0:
            # First write: sets the high byte of the VRAM address.
            self.t = (self.t & 0x00FF) | ((value & 0x3F) << 8)
            self.write_toggle = 1
        else:
            # Second write: sets the low byte.
            self.t = (self.t & 0xFF00) | value
            # The full address is then copied from the temporary register 't'
            # to the main VRAM address register 'v'.
            self.v = self.t
            self.write_toggle = 0
    elif reg == 0x2007:  # PPUDATA
        # Writes a byte to VRAM/Palette RAM at the address set via PPUADDR.
        addr = self.v & 0x3FFF
        if addr < 0x2000:
            # Write to CHR ROM/RAM (Pattern Tables)
            self._write_chr(<uint16_t>addr, value)
        elif addr < 0x3F00:
            # Write to VRAM (Nametables)
            phys = self.get_vram_mirror(addr)
            self.vram[phys] = value
        elif addr < 0x4000:
            # Write to Palette RAM
            pal_addr = self.get_vram_mirror(addr)
            self.palette_ram[pal_addr] = value
        
        # After a write, the VRAM address is incremented by 1 or 32,
        # depending on a flag in PPUCTRL.
        self.increment_v_2007()


cpdef uint8_t ppu_read_register(PPU self, uint16_t reg):
    """Handles CPU reads from the eight memory-mapped PPU registers.

    These registers provide status information and allow access to PPU memory.
    They are mirrored every 8 bytes from $2000-$3FFF in the CPU's address space.

    Args:
        self: The active PPU instance.
        reg: The CPU-visible register address ($2000-$2007, mirrored).

    Returns:
        uint8_t: The value of the requested register, subject to PPU-specific
                 rules like read buffering.

    Side Effects:
        Reading certain registers has side effects. Reading $2002 (PPUSTATUS)
        clears the VBlank flag and resets the scroll/address write toggle.
        Reading $2007 (PPUDATA) involves an internal read buffer.
    """
    cdef int addr, pal_addr
    cdef uint8_t ret
    # PPU registers are mirrored every 8 bytes. We only care about the lowest 3 bits.
    reg = reg & 0x2007

    if reg == 0x2002:  # PPUSTATUS
        # Reading the status register has side effects.
        # 1. The scroll/address write toggle is reset.
        self.write_toggle = 0
        ret = self.status
        # 2. The VBlank flag (bit 7) is cleared after being read.
        self.status &= ~0x80
        return ret
    elif reg == 0x2004:  # OAMDATA
        # Reads the byte from OAM at the current OAM address.
        return self.oam_data[self.oam_addr]
    elif reg == 0x2007:  # PPUDATA
        # Reading from VRAM via this register has a delay of one read.
        # The first read loads the data into an internal buffer, and the CPU
        # receives the *previous* contents of that buffer.
        addr = self.v & 0x3FFF
        if addr < 0x2000:
            # Read from CHR ROM/RAM (Pattern Tables)
            ret = self.read_buffer
            self.read_buffer = self._read_chr(<uint16_t>addr)
        elif addr < 0x3F00:
            # Read from VRAM (Nametables)
            ret = self.read_buffer
            self.read_buffer = self.vram[self.get_vram_mirror(addr)]
        else:
            # Exception: Palette RAM reads are not buffered. The data is returned
            # immediately. The read buffer is still updated, but with a "mirror"
            # of nametable data from under the palette.
            pal_addr = self.get_vram_mirror(addr)
            ret = self.palette_ram[pal_addr]
            self.read_buffer = self.vram[self.get_vram_mirror(addr - 0x1000)]
        
        # After a read, the VRAM address is incremented by 1 or 32,
        # depending on a flag in PPUCTRL.
        self.increment_v_2007()
        return ret
    
    # Other registers ($2000, $2001, $2003, $2005, $2006) are write-only.
    # Reading from them typically returns the last value on the data bus,
    # which can be complex to emulate. Returning 0 is a common simplification.
    return 0
