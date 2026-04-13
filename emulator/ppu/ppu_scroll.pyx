# Glossary (plain-language terms for this PPU section):
# - Scroll latch: Internal two-write mechanism for '$2005'/'$2006'.
# - Fine Y / coarse Y: Pixel-row / tile-row parts of vertical scroll.
# - Nametable select bits: Choose one of four logical background pages.
# - V increment mode: '$2007' address increment by 1 or 32.
# NESdev references:
# - https://www.nesdev.org/wiki/PPU_scrolling

# IDE Static Analysis Hints
if not "PPU" in globals():
    from ppu cimport PPU

cdef void ppu_increment_v(PPU self):
    # PPUDATA increment mode: +1 across columns or +32 across rows.
    self.v += 32 if (self.ctrl & 0x04) else 1


cdef void ppu_increment_scroll_y(PPU self):
    cdef int y
    # Fine Y is in bits 12-14 of v.
    if (self.v & 0x7000) != 0x7000:
        # If fine Y < 7, advance fine Y only.
        self.v += 0x1000
    else:
        # Fine Y wrapped: clear it and increment coarse Y.
        self.v &= ~0x7000
        y = (self.v & 0x03E0) >> 5
        if y == 29:
            # Coarse Y wraps from 29->0 and flips vertical nametable.
            y = 0
            self.v ^= 0x0800
        elif y == 31:
            # Coarse Y values 30/31 are attribute fetch artifacts.
            y = 0
        else:
            # Regular next tile row.
            y += 1
        # Write coarse Y back into v.
        self.v = (self.v & ~0x03E0) | (y << 5)


cdef void ppu_increment_scroll_x(PPU self):
    # Coarse X occupies low 5 bits of v.
    if (self.v & 0x001F) == 31:
        # Wrap coarse X and switch horizontal nametable.
        self.v &= ~0x001F
        self.v ^= 0x0400
    else:
        # Move to next tile column.
        self.v += 1


cdef void ppu_increment_v_2007(PPU self):
    # During rendering, PPUDATA access triggers scrolling-style increments.
    if (self.mask & 0x18) != 0 and ((0 <= self.scanline < 240) or self.scanline == 261):
        self.increment_scroll_x()
        self.increment_scroll_y()
    else:
        # Outside rendering, use raw increment mode from PPUCTRL.
        self.increment_v()


cdef void ppu_copy_x(PPU self):
    # Copy horizontal scroll bits from t -> v (coarse X + nametable X).
    self.v = (self.v & 0xFBE0) | (self.t & 0x041F)


cdef void ppu_copy_y(PPU self):
    # Copy vertical scroll bits from t -> v (fine/coarse Y + nametable Y).
    self.v = (self.v & 0x841F) | (self.t & 0x7BE0)
