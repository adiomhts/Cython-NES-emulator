# NESdev references:
# - https://www.nesdev.org/wiki/PPU_rendering
# - https://www.nesdev.org/wiki/PPU_sprite_evaluation

# IDE Static Analysis Hints
if not "PPU" in globals():
    from ppu cimport PPU
    from libc.stdint cimport uint8_t, uint16_t, uint32_t

cpdef void ppu_render_scanline(PPU self, int line):
    """Renders all background pixels for a single visible scanline.

    This is one of the most complex parts of the PPU. It simulates the
    hardware's process of fetching tile data from VRAM to draw the background
    layer pixel by pixel for one horizontal line.

    Args:
        self: The active PPU instance.
        line: The vertical coordinate (row) of the scanline to render (0-239).

    Returns:
        None.

    Side Effects:
        - Writes final RGB pixel data into the `frame_buffer` for the given line.
        - Updates `scanline_bg` with the 2-bit palette index of each background
          pixel. This is used later for sprite priority and sprite 0 hit checks.

    NESdev references:
        https://www.nesdev.org/wiki/PPU_rendering
        https://www.nesdev.org/wiki/PPU_nametables
        https://www.nesdev.org/wiki/PPU_attribute_tables
    """
    # Background rendering can be disabled entirely via a flag in the PPUMASK register.
    if not (self.mask & 0x08):
        return

    # If no graphics data is available (e.g., no cartridge), do nothing.
    if not self._has_chr_source():
        return

    cdef int fine_y, coarse_y_v, nt_select, coarse_x_start, fine_x_start
    cdef int nt_x_base, nt_y_base
    cdef int x, pixel_total, tile_x_offset, pixel_in_tile_x, prev_tile_x_offset
    cdef int current_nt_x, current_nt_y, tile_x, tile_y, current_nt, coarse_x_abs
    cdef int nt_addr, tile_index, tile_offset
    cdef int attr_addr, attr_byte, shift, palette_index
    cdef uint8_t low, high, bit0, bit1, pix
    cdef int pal_idx, pal0
    cdef int bg_pattern_base
    cdef bint palette_empty, tile_valid
    cdef int i
    cdef uint8_t[:] vram = self.vram
    cdef uint8_t[:] palette_ram = self.palette_ram
    cdef uint8_t[:] scanline_bg = self.scanline_bg
    cdef uint8_t[:, :, :] frame_buffer = self.frame_buffer
    cdef int[:, :] nes_palette = self.nes_palette

    # Decode the current VRAM address/scroll register 'v' into its component parts.
    # This register holds all the state needed for scrolling.
    fine_y = (self.v >> 12) & 7           # Fine Y scroll (0-7 pixels within a tile)
    coarse_y_v = (self.v >> 5) & 31       # Coarse Y scroll (which tile row, 0-29)
    nt_select = (self.v >> 10) & 3        # Which nametable (0-3)
    coarse_x_start = self.v & 31          # Coarse X scroll (which tile column, 0-31)
    fine_x_start = self.snap_fine_x       # Fine X scroll (0-7 pixels within a tile), latched from 'x'

    # Determine the base nametable for the start of the scanline.
    nt_x_base = nt_select & 1
    nt_y_base = (nt_select >> 1) & 1
    tile_y = coarse_y_v # The coarse Y position is the tile row we are on.

    # The PPU can draw background tiles from one of two 4KB pages in pattern memory.
    # This is selected by a bit in the PPUCTRL register.
    bg_pattern_base = 0x1000 if (self.ctrl & 0x10) else 0x0000

    # For performance and to handle an edge case, check if the palette is all zeroes.
    palette_empty = True
    for i in range(32):
        if palette_ram[i] != 0:
            palette_empty = False
            break
    # The universal background color is always at the first palette entry.
    pal0 = palette_ram[0] & 0x3F

    # We only need to fetch new tile data every 8 pixels. These variables cache
    # the data for the current tile.
    tile_valid = False
    low = 0
    high = 0
    palette_index = 0
    prev_tile_x_offset = -1

    # Render every visible pixel on the scanline from left to right.
    for x in range(256):
        # Calculate our absolute pixel position, accounting for fine X scroll.
        pixel_total = fine_x_start + x
        # Which 8-pixel-wide tile does this pixel belong to?
        tile_x_offset = pixel_total >> 3
        # Which column (0-7) inside that tile is this pixel?
        pixel_in_tile_x = pixel_total & 7

        # --- TILE FETCH LOGIC ---
        # This block executes only when we cross into a new tile column.
        if tile_x_offset != prev_tile_x_offset:
            prev_tile_x_offset = tile_x_offset

            # Absolute tile column, accounting for nametable wrapping.
            coarse_x_abs = coarse_x_start + tile_x_offset
            tile_x = coarse_x_abs & 31 # Tile X within the current nametable (0-31)
            # Determine the correct nametable, handling horizontal wrapping.
            current_nt_x = nt_x_base ^ ((coarse_x_abs >> 5) & 1)
            current_nt_y = nt_y_base # Vertical wrapping is handled by the v register update.
            current_nt = (current_nt_y * 2) + current_nt_x

            # Get address of the tile ID from the correct nametable.
            nt_addr = self.get_vram_mirror(0x2000 + (current_nt * 0x400) + tile_y * 32 + tile_x)
            tile_index = vram[nt_addr]
            # Calculate the address of the tile's pattern data (graphics).
            tile_offset = bg_pattern_base + tile_index * 16

            tile_valid = True
            # A tile's graphics for one row are stored in two "bitplanes".
            # 'low' plane stores the low bit of the color index, 'high' stores the high bit.
            low = self._read_chr(<uint16_t>(tile_offset + fine_y))
            high = self._read_chr(<uint16_t>(tile_offset + 8 + fine_y))

            # Fetch the palette information for this tile from the Attribute Table.
            # Each attribute byte covers a 4x4 tile area (2x2 attribute cells).
            attr_addr = self.get_vram_mirror(
                0x2000 + (current_nt * 0x400) + 0x3C0 + ((tile_y >> 2) * 8) + (tile_x >> 2)
            )
            attr_byte = vram[attr_addr]
            # Select the correct 2 bits from the attribute byte based on tile position.
            shift = ((tile_y & 0x02) << 1) | (tile_x & 0x02)
            palette_index = (attr_byte >> shift) & 0x03

        # --- PIXEL COLOR DECODING ---
        if tile_valid:
            # Combine the bits from the two bitplanes to get a 2-bit color index (0-3).
            bit0 = (low >> (7 - pixel_in_tile_x)) & 1
            bit1 = (high >> (7 - pixel_in_tile_x)) & 1
            pix = (bit1 << 1) | bit0
        else:
            pix = 0

        # The first 8 pixels on the left can be masked (made transparent).
        if x < 8 and not (self.mask & 0x02):
            pix = 0

        # --- PALETTE LOOKUP ---
        # A pixel value of 0 means "transparent"; use the universal background color.
        if palette_empty or pix == 0:
            pal_idx = pal0
        else:
            # For non-transparent pixels, combine the 2-bit attribute palette index
            # with the 2-bit pixel color to get the final address in palette RAM.
            pal_idx = palette_ram[palette_index * 4 + pix] & 0x3F

        # Store the raw background pixel value (0-3) for sprite rendering logic.
        scanline_bg[x] = pix
        # Convert the final palette index to an RGB color and write to the framebuffer.
        frame_buffer[line, x, 0] = nes_palette[pal_idx, 0]
        frame_buffer[line, x, 1] = nes_palette[pal_idx, 1]
        frame_buffer[line, x, 2] = nes_palette[pal_idx, 2]


cdef int ppu_find_sprite0_hit_x(PPU self, int line):
    """Finds the screen X-coordinate of the first overlap between sprite 0
    and the background.

    This function simulates the PPU's sprite 0 hit detection hardware. It is
    called when sprite 0 is known to be on the current scanline. It fetches
    the sprite's pixel data and checks it, pixel by pixel, against the
    already-rendered background. The first time a non-transparent sprite
    pixel overlaps a non-transparent background pixel, a "hit" occurs.

    Args:
        self: The active PPU instance.
        line: The current scanline index.

    Returns:
        int: The X coordinate (0-255) of the first hit, or -1 if no hit occurs
             on this scanline.

    NESdev reference:
        https://www.nesdev.org/wiki/PPU_sprite_evaluation#Sprite_zero_hits
    """
    cdef int y, x, height, tile_index, attr
    cdef bint flip_x, flip_y
    cdef int scanline_y, tile_row, tile_offset, bank, base_index
    cdef int sprite_table_base
    cdef uint8_t low, high, bit0, bit1, pix
    cdef int col, sx

    # Sprite 0 hit cannot occur if background or sprite rendering is disabled.
    if not self._has_chr_source():
        return -1
    if (self.mask & 0x18) != 0x18:
        return -1

    # Sprite 0's data is always the first 4 bytes in the main OAM.
    y = int(self.oam_data[0]) + 1
    x = int(self.oam_data[3])
    height = 16 if (self.ctrl & 0x20) else 8
    # Early exit if the current scanline is outside the sprite's vertical range.
    if line < y or line >= y + height:
        return -1

    # Decode attributes to find the sprite's pattern data.
    tile_index = int(self.oam_data[1])
    attr = int(self.oam_data[2])
    flip_x = (attr & 0x40) != 0
    flip_y = (attr & 0x80) != 0

    scanline_y = line - y
    if flip_y:
        scanline_y = (height - 1) - scanline_y

    sprite_table_base = 0x1000 if (self.ctrl & 0x08) else 0x0000

    # Get the address of the tile pattern graphics (same logic as sprite render).
    if height == 8:
        tile_row = scanline_y
        tile_offset = sprite_table_base + tile_index * 16
    else:
        bank = (tile_index & 1) * 0x1000
        base_index = tile_index & 0xFE
        if scanline_y < 8:
            tile_row = scanline_y
            tile_offset = bank + base_index * 16
        else:
            tile_row = scanline_y - 8
            tile_offset = bank + (base_index + 1) * 16

    # Fetch the sprite's pattern data for the current row.
    low = self._read_chr(<uint16_t>(tile_offset + tile_row))
    high = self._read_chr(<uint16_t>(tile_offset + 8 + tile_row))

    # Scan the 8 pixels of the sprite pattern.
    for col in range(8):
        # Calculate the pixel's screen X position.
        sx = x + (7 - col if flip_x else col)
        if sx < 0 or sx >= 256:
            continue
        # A hit cannot happen at X=255.
        if sx == 255:
            continue
        # Check if left-edge clipping is enabled for sprites/background.
        if sx < 8 and (self.mask & 0x06) != 0x06:
            continue

        # Is this sprite pixel transparent?
        bit0 = (low >> (7 - col)) & 1
        bit1 = (high >> (7 - col)) & 1
        pix = (bit1 << 1) | bit0
        if pix == 0:
            continue
        
        # Is the background pixel at this location transparent?
        if int(self.scanline_bg[sx]) == 0:
            continue
            
        # Hit! We found an opaque sprite pixel over an opaque background pixel.
        return sx

    return -1 # No hit on this scanline.


cpdef void ppu_sprite_evaluate(PPU self):
    """Finds up to 8 sprites visible on the *next* scanline.

    This simulates the PPU's sprite evaluation phase. It iterates through the
    primary Object Attribute Memory (OAM, 64 sprites) and checks which ones
    fall on the current scanline. The data for the first 8 sprites found are
    copied into a temporary buffer, the "secondary OAM".

    Args:
        self: The active PPU instance.

    Returns:
        None.

    Side Effects:
        - Fills `scanline_oam` (secondary OAM) with data for up to 8 sprites.
        - Sets `sprite_count` to the number of sprites found.
        - Sets the PPU status register's Sprite Overflow flag if more than 8
          sprites are found on the scanline.
        - Tracks if sprite 0 is one of the sprites on the scanline, which is
          needed for sprite 0 hit detection.
    
    NESdev reference:
        https://www.nesdev.org/wiki/PPU_sprite_evaluation
    """
    cdef int oam_idx, y, start, j
    # Sprite height can be 8x8 or 8x16, controlled by a PPUCTRL flag.
    cdef int height = 16 if (self.ctrl & 0x20) else 8
    cdef int found = 0
    cdef bint overflow = False

    # Clear results from the previous scanline.
    self.sprite_count = 0
    self.sprite0_hit = 0
    self.sprite0_in_scanline = -1

    # Iterate through all 64 possible sprites in the main OAM.
    # Each sprite's data takes up 4 bytes.
    for oam_idx in range(0, 256, 4):
        y = int(self.oam_data[oam_idx]) + 1 # Sprite Y coordinate.
        # Check if the current scanline is within the sprite's vertical range.
        if self.scanline >= y and self.scanline < y + height:
            # This sprite is on the current line.
            if found < 8:
                # If we haven't found 8 sprites yet, copy this sprite's data
                # into our secondary OAM for rendering on this line.
                start = found * 4
                for j in range(4):
                    self.scanline_oam[start + j] = self.oam_data[oam_idx + j]
                # Special case: if this is sprite 0, we need to track it
                # for sprite 0 hit detection.
                if oam_idx == 0:
                    self.sprite0_in_scanline = found
                found += 1
            else:
                # If we've already found 8 sprites, we can't draw any more.
                # The real PPU sets an overflow flag in this case.
                overflow = True
    
    self.sprite_count = found
    if overflow:
        self.status |= 0x20 # Set the Sprite Overflow bit in the PPU status register.


cpdef void ppu_sprite_render(PPU self):
    """Renders the 8 sprites in secondary OAM over the background.

    This function iterates through the sprites found during the evaluation
    phase and draws them pixel-by-pixel onto the scanline's framebuffer,
    respecting transparency, priority, and clipping rules.

    Args:
        self: The active PPU instance.

    Returns:
        None.

    Side Effects:
        - Writes final RGB sprite pixel data into the `frame_buffer` for the
          current scanline, potentially overwriting background pixels.
    """
    # Sprite rendering can be disabled entirely via a flag in the PPUMASK register.
    if not self._has_chr_source():
        return
    if not (self.mask & 0x10):
        return

    # Sprite size can be 8x8 or 8x16, controlled by a PPUCTRL flag.
    cdef int height = 16 if (self.ctrl & 0x20) else 8
    cdef int sprite_table_base
    # For 8x8 sprites, the pattern table is selected by a PPUCTRL flag.
    # For 8x16, this bit is ignored and the table comes from the tile index itself.
    sprite_table_base = 0x1000 if (self.ctrl & 0x08) else 0x0000
    cdef int i, base, y, tile_index, attr, x, palette_index
    cdef bint flip_x, flip_y, priority_front
    cdef int scanline_y, tile_row, tile_offset, bank, base_index
    cdef uint8_t low, high, bit0, bit1
    cdef int col, sx, pix, bg_pix, pal_idx

    # Render sprites from last to first (8 down to 1). This correctly handles
    # priority among sprites, as lower-indexed sprites (like sprite 0) are
    # drawn on top of higher-indexed ones.
    for i in range(self.sprite_count - 1, -1, -1):
        base = i * 4
        y = int(self.scanline_oam[base]) + 1
        tile_index = int(self.scanline_oam[base + 1])
        attr = int(self.scanline_oam[base + 2])
        x = int(self.scanline_oam[base + 3])

        # Decode the sprite's attribute byte.
        flip_x = (attr & 0x40) != 0  # Horizontal flip
        flip_y = (attr & 0x80) != 0  # Vertical flip
        palette_index = (attr & 0x3) + 4 # Selects one of the four sprite palettes
        priority_front = (attr & 0x20) == 0 # 0: In front of background, 1: Behind background

        # Which row of the sprite pattern are we drawing?
        scanline_y = self.scanline - y
        if scanline_y < 0 or scanline_y >= height:
            continue

        # Account for vertical flipping.
        if flip_y:
            scanline_y = (height - 1) - scanline_y

        # --- TILE FETCH LOGIC (8x8 vs 8x16) ---
        if height == 8:
            tile_row = scanline_y
            tile_offset = sprite_table_base + tile_index * 16
        else: # 8x16 mode
            # The pattern table is determined by the LSB of the tile index.
            bank = (tile_index & 1) * 0x1000
            # The tile index points to the top tile of a 2-tile pair.
            base_index = tile_index & 0xFE
            if scanline_y < 8: # Top tile
                tile_row = scanline_y
                tile_offset = bank + base_index * 16
            else: # Bottom tile
                tile_row = scanline_y - 8
                tile_offset = bank + (base_index + 1) * 16

        # Fetch the two bitplanes for the sprite tile row.
        low = self._read_chr(<uint16_t>(tile_offset + tile_row))
        high = self._read_chr(<uint16_t>(tile_offset + 8 + tile_row))

        # Draw the 8 pixels of the sprite row.
        for col in range(8):
            # Compute screen X position, accounting for horizontal flip.
            sx = x + (7 - col if flip_x else col)
            if sx < 0 or sx >= 256:
                continue # Clip sprite pixels that are off-screen.
            
            # The first 8 pixels on the left can be masked.
            if sx < 8 and not (self.mask & 0x04):
                continue

            # Combine the bits from the two bitplanes to get a 2-bit color index.
            bit0 = (low >> (7 - col)) & 1
            bit1 = (high >> (7 - col)) & 1
            pix = (bit1 << 1) | bit0

            if pix == 0:
                # Color index 0 is transparent for sprites.
                continue

            # --- PRIORITY LOGIC ---
            # Get the background pixel value that we saved during background render.
            bg_pix = int(self.scanline_bg[sx])

            # Draw the sprite pixel if it has priority OR if the background is transparent.
            if priority_front or bg_pix == 0:
                pal_idx = int(self.palette_ram[palette_index * 4 + pix]) & 0x3F
                self.frame_buffer[self.scanline, sx] = self.nes_palette[pal_idx]


cpdef void ppu_perform_dma(PPU self, uint8_t[:] page):
    """Copies a 256-byte page from CPU memory into the PPU's OAM.

    This is initiated by the CPU writing to the OAMDMA register ($4014).
    This process halts the CPU for over 500 cycles while the transfer occurs.

    Args:
        self: The active PPU instance.
        page: A 256-byte buffer of the source data from the CPU's memory page.

    Returns:
        None.

    Side Effects:
        - Overwrites the entire 256 bytes of `oam_data`.
        - The copy starts at the current `oam_addr`, and this address will
          wrap around if not starting at 0.
    
    NESdev reference:
        https://www.nesdev.org/wiki/PPU_OAM#DMA
    """
    cdef int i
    # The CPU has prepared a 256-byte block of data from the specified page.
    # We now copy it into our OAM.
    for i in range(256):
        # The DMA copy starts at the current OAM address and wraps around the
        # 256-byte OAM memory.
        self.oam_data[self.oam_addr] = page[i]
        self.oam_addr += 1
