import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t

# Glossary (terms used in comments/docstrings in this file):
# - PPU: Picture Processing Unit.
# - VRAM: Video RAM for nametables/attributes in PPU address space.
# - OAM: Object Attribute Memory (sprite list storage).
# - CHR: Pattern table tile/sprite graphics source.
# - NT: Nametable (background tile map page; NT0..NT3 shorthand in comments).
# - VBlank: Vertical blanking interval; frame period where NMI may fire.
# - Fine/coarse scroll: Pixel/tile components of PPU scroll registers.
# - Sprite 0 hit: Status flag when sprite #0 overlaps non-zero background pixel.
# - PPUCTRL/PPUMASK/PPUSTATUS: Core PPU control/mask/status registers.
# NESdev references:
# - https://www.nesdev.org/wiki/PPU
# - https://www.nesdev.org/wiki/PPU_registers
# - https://www.nesdev.org/wiki/PPU_rendering
# - https://www.nesdev.org/wiki/PPU_sprite_evaluation

cdef class PPU:
    """NES PPU core: registers, VRAM mirroring, and scanline-based rendering.

    Owns rendering buffers, PPU registers, OAM state, and timing counters used
    to emulate visible scanlines and vblank behavior.

    NESdev references:
    - https://www.nesdev.org/wiki/PPU
    - https://www.nesdev.org/wiki/PPU_registers
    - https://www.nesdev.org/wiki/PPU_rendering
    """

    cdef int scanline, cycle
    cdef public object frame_buffer
    cdef public uint8_t[:] oam_data
    cdef public uint8_t[:] vram
    cdef public uint8_t[:] palette_ram
    cdef uint8_t mirroring, vblank_flag
    
    cdef public uint8_t ctrl, mask, status, oam_addr, fine_x
    
    cdef uint16_t v, t
    cdef uint8_t write_toggle
    
    cdef uint8_t scroll_x, scroll_y

    cdef uint8_t snap_fine_x

    cdef uint8_t read_buffer
    
    cdef uint8_t[:] scanline_oam
    cdef int sprite_count
    cdef uint8_t sprite0_hit
    cdef int sprite0_hit_x
    cdef uint8_t[:] scanline_bg
    cdef int sprite0_in_scanline
    cdef bint odd_frame
    
    cdef int[:, :] nes_palette
    
    cdef public object chr_rom
    cdef public object cpu
    cdef public object cartridge

    def __init__(self, mirroring=0):
        """Initialize PPU state and memory arrays.

        Args:
            mirroring: Nametable mirroring mode (`0=horizontal`, `1=vertical`).

        Returns:
            None.

        Side Effects:
            Allocates framebuffer, OAM/VRAM/palette storage, and resets PPU
            register/timing state.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_power_up_state
            https://www.nesdev.org/wiki/Mirroring
        """
        # PPU timing starts at pre-render / initial internal coordinates.
        self.scanline = 0
        self.cycle = 0
        # 256x240 RGB framebuffer exposed to host renderer.
        self.frame_buffer = np.zeros((240, 256, 3), dtype=np.uint8)
        
        # OAM sprite table, nametable VRAM, and palette RAM.
        self.oam_data = np.full(256, 0xFF, dtype=np.uint8)
        self.vram = np.zeros(2048, dtype=np.uint8)
        self.palette_ram = np.zeros(32, dtype=np.uint8)
        
        self.mirroring = mirroring
        self.vblank_flag = 0
        self.ctrl = 0
        self.mask = 0
        self.status = 0
        self.oam_addr = 0
        self.fine_x = 0
        
        self.v = 0
        self.t = 0
        self.write_toggle = 0 
        
        self.scroll_x = 0
        self.scroll_y = 0
        self.snap_fine_x = 0
        self.read_buffer = 0
        
        self.scanline_oam = np.zeros(32, dtype=np.uint8)
        self.sprite_count = 0
        self.sprite0_hit = 0
        self.sprite0_hit_x = -1
        self.nes_palette = np.array([
            [124,124,124],[0,0,252],[0,0,188],[68,40,188],[148,0,132],[168,0,32],[168,16,0],[136,20,0],
            [80,48,0],[0,120,0],[0,104,0],[0,88,0],[0,64,88],[0,0,0],[0,0,0],[0,0,0],
            [188,188,188],[0,120,248],[0,88,248],[104,68,252],[216,0,204],[228,0,88],[248,56,0],[228,92,16],
            [172,124,0],[0,184,0],[0,168,0],[0,168,68],[0,136,136],[0,0,0],[0,0,0],[0,0,0],
            [248,248,248],[60,188,252],[104,136,252],[152,120,248],[248,120,248],[248,88,152],[248,120,88],[252,160,68],
            [248,184,0],[184,248,24],[88,216,84],[88,248,152],[0,232,216],[120,120,120],[0,0,0],[0,0,0],
            [252,252,252],[168,228,252],[184,184,248],[216,184,248],[248,184,248],[248,168,216],[240,208,176],[252,224,168],
            [248,216,120],[216,248,120],[184,248,184],[184,248,216],[0,252,252],[248,216,248],[0,0,0],[0,0,0]
        ], dtype=np.int32)
        self.chr_rom = None
        self.cartridge = None
        self.scanline_bg = np.zeros(256, dtype=np.uint8)
        self.sprite0_in_scanline = -1
        self.odd_frame = False

    
    cdef void increment_v(self):
        # PPUDATA increment mode: +1 across columns or +32 across rows.
        self.v += 32 if (self.ctrl & 0x04) else 1

    cdef void increment_scroll_y(self):
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

    cdef void increment_scroll_x(self):
        # Coarse X occupies low 5 bits of v.
        if (self.v & 0x001F) == 31:
            # Wrap coarse X and switch horizontal nametable.
            self.v &= ~0x001F
            self.v ^= 0x0400
        else:
            # Move to next tile column.
            self.v += 1

    cdef void increment_v_2007(self):
        # During rendering, PPUDATA access triggers scrolling-style increments.
        if (self.mask & 0x18) != 0 and ((0 <= self.scanline < 240) or self.scanline == 261):
            self.increment_scroll_x()
            self.increment_scroll_y()
        else:
            # Outside rendering, use raw increment mode from PPUCTRL.
            self.increment_v()

    cdef void copy_x(self):
        # Copy horizontal scroll bits from t -> v (coarse X + nametable X).
        self.v = (self.v & 0xFBE0) | (self.t & 0x041F)

    cdef void copy_y(self):
        # Copy vertical scroll bits from t -> v (fine/coarse Y + nametable Y).
        self.v = (self.v & 0x841F) | (self.t & 0x7BE0)

    cdef int get_vram_mirror(self, int addr):
        cdef int pal_addr, clean_addr, table, offset, bank
        
        # PPU internal address bus wraps at 14 bits.
        addr = addr & 0x3FFF 

        if addr >= 0x3F00:
            # Palette RAM is 32 bytes with mirrored universal background entries.
            pal_addr = addr & 0x1F
            if pal_addr >= 0x10 and (pal_addr & 3) == 0:
                pal_addr -= 0x10
            return pal_addr

        if 0x2000 <= addr < 0x3F00:
            # Collapse $2000-$2FFF and mirrored $3000-$3EFF into 4 nametable pages.
            clean_addr = (addr - 0x2000) % 0x1000
            table = clean_addr // 0x400
            offset = clean_addr % 0x400
            bank = 0
            
            if self.mirroring == 0: 
                # Horizontal mirroring: NT0/NT1 share, NT2/NT3 share.
                if table == 0 or table == 1: bank = 0
                else: bank = 1
            elif self.mirroring == 1: 
                # Vertical mirroring: NT0/NT2 share, NT1/NT3 share.
                if table == 0 or table == 2: bank = 0
                else: bank = 1
            
            # Return physical index into local 2KB VRAM buffer.
            return bank * 0x400 + offset
        return 0

    cdef inline bint _has_chr_source(self):
        return self.cartridge is not None or self.chr_rom is not None

    cdef inline uint8_t _read_chr(self, uint16_t addr):
        if self.cartridge is not None:
            try:
                return self.cartridge.mapper_instance.read_chr(addr)
            except Exception:
                pass
        if self.chr_rom is not None and addr < len(self.chr_rom):
            return self.chr_rom[addr]
        return 0

    cdef inline void _write_chr(self, uint16_t addr, uint8_t value):
        if self.cartridge is not None:
            try:
                self.cartridge.mapper_instance.write_chr(addr, value)
                return
            except Exception:
                pass
        if self.chr_rom is not None and addr < len(self.chr_rom):
            self.chr_rom[addr] = value


    cdef void _step_core(self):
        cdef bint rendering_enabled
        cdef int i, pal_idx_line
        
        # Advance one PPU cycle each call.
        self.cycle += 1
        # Rendering is enabled if background and/or sprites are enabled.
        rendering_enabled = (self.mask & 0x18) != 0

        if self.cycle == 1:
            # Snapshot fine X used by scanline renderer for stable fetch origin.
            self.snap_fine_x = self.fine_x
            if 0 <= self.scanline < 240:
                # Visible scanlines only.
                if rendering_enabled and (self.mask & 0x08):
                    # Render background when enabled.
                    self.render_scanline(self.scanline)
                else:
                    # Fill with universal backdrop when background is disabled.
                    pal_idx_line = self.palette_ram[0] & 0x3F
                    for i in range(256):
                        self.frame_buffer[self.scanline, i, 0] = self.nes_palette[pal_idx_line, 0]
                        self.frame_buffer[self.scanline, i, 1] = self.nes_palette[pal_idx_line, 1]
                        self.frame_buffer[self.scanline, i, 2] = self.nes_palette[pal_idx_line, 2]

                    # Clear bg coverage map so sprites behave as "in front".
                    for i in range(256):
                        self.scanline_bg[i] = 0

                if (self.mask & 0x18) == 0x18:
                    # Pre-compute first x where sprite 0 hit can occur on this line.
                    self.sprite0_hit_x = self._find_sprite0_hit_x(self.scanline)
                else:
                    # Hit detection only valid when both bg and sprites are enabled.
                    self.sprite0_hit_x = -1

        if rendering_enabled and not self.sprite0_hit and self.sprite0_hit_x >= 0:
            # PPU sets sprite0-hit slightly after pixel fetch point.
            if self.cycle == self.sprite0_hit_x + 2:
                self.sprite0_hit = 1
                self.status |= 0x40

        # Odd-frame cycle skip on pre-render line when rendering is enabled.
        if self.scanline == 261 and self.cycle == 339 and rendering_enabled and self.odd_frame:
            self.cycle = 0
            self.scanline = 0
            self.odd_frame = False
            return

        # End-of-scanline timing.
        if self.cycle >= 341:
            self.cycle = 0
            self.scanline += 1
            
            if self.scanline == 241:
                # Enter VBlank at line 241.
                self.trigger_vblank()
            
            elif self.scanline == 261:
                # Pre-render line: clear vblank/sprite flags.
                self.vblank_flag = 0
                self.status &= ~0xE0 
                self.sprite0_hit = 0
            
            elif self.scanline >= 262:
                # Wrap to next frame and toggle odd/even frame parity.
                self.scanline = 0
                self.odd_frame = not self.odd_frame
        
        if self.scanline == 261 and rendering_enabled:
            if self.cycle == 256:
                # Vertical increment at end of tile row.
                self.increment_scroll_y()
            if self.cycle == 257:
                # Reload horizontal scroll for next scanline.
                self.copy_x()
            if self.cycle >= 280 and self.cycle <= 304:
                # Pre-render reload of vertical scroll bits.
                self.copy_y()

        if 0 <= self.scanline < 240:
            if self.cycle == 256:
                if rendering_enabled:
                    # Visible-line vertical increment point.
                    self.increment_scroll_y()
            
            if self.cycle == 257:
                if rendering_enabled:
                    # Reload horizontal bits and then evaluate/render sprites.
                    self.copy_x()
                    self.sprite_evaluate()
                    self.sprite_render()

    cpdef public void step(self):
        """Advance PPU timing by one step.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            May change scanline/cycle counters, vblank flags, and render output
            depending on current timing position.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_frame_timing
            https://www.nesdev.org/wiki/PPU_rendering
        """
        # One master PPU tick.
        self._step_core()

    cpdef public void step_many(self, int steps):
        """Advance PPU by multiple timing steps.

        Args:
            steps: Number of internal `_step_core` iterations.

        Returns:
            None.

        Side Effects:
            Same state effects as repeated `step()` calls.

        NESdev reference:
            https://www.nesdev.org/wiki/PPU_frame_timing
        """
        cdef int i
        # Fast loop for CPU-to-PPU 3:1 stepping.
        for i in range(steps):
            self._step_core()

    cpdef public void trigger_vblank(self):
        """Enter vblank state and optionally trigger NMI.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Sets vblank status bit and can queue CPU NMI when enabled by
            `PPUCTRL` bit 7.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS
            https://www.nesdev.org/wiki/NMI
        """
        # Set vblank status latch.
        self.vblank_flag = 1
        self.status |= 0x80
        try:
            # Generate NMI when enabled in PPUCTRL.
            if getattr(self, 'cpu', None) is not None and (self.ctrl & 0x80):
                self.cpu.trigger_interrupt(0) 
        except Exception:
            pass


    cpdef public void write_register(self, uint16_t reg, uint8_t value):
        """Handle CPU write to PPU register space.

        Args:
            reg: CPU-visible PPU register address (including mirrors).
            value: Byte value to write.

        Returns:
            None.

        Side Effects:
            Updates PPU registers and/or memory, scroll/address latches, OAM,
            and VRAM increment behavior according to target register.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_registers
            https://www.nesdev.org/wiki/PPU_scrolling
        """
        cdef int addr, phys, pal_addr
        # Collapse mirrors to canonical $2000-$2007 range.
        reg = reg & 0x2007
        
        if reg == 0x2000: 
            # PPUCTRL write, including base nametable bits into temp VRAM addr.
            self.ctrl = value
            self.t = (self.t & 0xF3FF) | ((value & 0x03) << 10)
            
        elif reg == 0x2001: 
            # PPUMASK controls render enable, clipping, emphasis.
            self.mask = value
            
        elif reg == 0x2002: 
            # PPUSTATUS is read-only; writes are ignored.
            pass
            
        elif reg == 0x2003: 
            # OAMADDR selects next OAM byte for $2004 reads/writes.
            self.oam_addr = value
            
        elif reg == 0x2004: 
            # OAMDATA write and auto-increment address.
            self.oam_data[self.oam_addr] = value
            self.oam_addr += 1
            
        elif reg == 0x2005: 
            if self.write_toggle == 0:
                # First write: horizontal scroll + fine X.
                self.scroll_x = value
                self.fine_x = value & 0x07
                self.t = (self.t & 0xFFE0) | (value >> 3)
                self.write_toggle = 1
            else:
                # Second write: vertical scroll components into t.
                self.scroll_y = value
                self.t = (self.t & 0x8FFF) | ((value & 0x07) << 12)
                self.t = (self.t & 0xFC1F) | ((value & 0xF8) << 2)
                self.write_toggle = 0
                
        elif reg == 0x2006: 
            if self.write_toggle == 0:
                # First write: high byte of VRAM address (6 bits used).
                self.t = (self.t & 0x00FF) | ((value & 0x3F) << 8)
                self.write_toggle = 1
            else:
                # Second write: low byte, then transfer full t -> v.
                self.t = (self.t & 0xFF00) | value
                self.v = self.t
                self.write_toggle = 0
                
        elif reg == 0x2007: 
            # PPUDATA write to CHR/nametable/palette spaces with mirroring.
            addr = self.v & 0x3FFF
            if addr < 0x2000:
                self._write_chr(<uint16_t>addr, value)
            elif addr < 0x3F00:
                phys = self.get_vram_mirror(addr)
                self.vram[phys] = value
            elif addr < 0x4000:
                pal_addr = self.get_vram_mirror(addr)
                self.palette_ram[pal_addr] = value
            self.increment_v_2007()

    cpdef public uint8_t read_register(self, uint16_t reg):
        """Handle CPU read from PPU register space.

        Args:
            reg: CPU-visible PPU register address (including mirrors).

        Returns:
            uint8_t: Register value with correct buffered-read semantics for
            `$2007` and status behavior for `$2002`.

        Side Effects:
            Can clear vblank status on `$2002`, mutate read buffer, and advance
            internal VRAM address.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_registers
            https://www.nesdev.org/wiki/PPU_scrolling
        """
        cdef int addr, pal_addr
        cdef uint8_t ret
        # Collapse mirrors to canonical $2000-$2007 range.
        reg = reg & 0x2007
        
        if reg == 0x2002: 
            # Reading status resets write latch and clears vblank bit.
            self.write_toggle = 0
            ret = self.status
            self.status &= ~0x80 
            return ret
            
        elif reg == 0x2004: 
            # OAMDATA read at current OAMADDR.
            return self.oam_data[self.oam_addr]
            
        elif reg == 0x2007: 
            # PPUDATA buffered-read behavior depends on address region.
            addr = self.v & 0x3FFF
            if addr < 0x2000:
                # Pattern-table reads are delayed by one read.
                ret = self.read_buffer
                self.read_buffer = self._read_chr(<uint16_t>addr)
            elif addr < 0x3F00:
                # Nametable reads are also buffered.
                ret = self.read_buffer
                self.read_buffer = self.vram[self.get_vram_mirror(addr)]
            else:
                # Palette reads are immediate; buffer is filled from mirrored NT.
                pal_addr = self.get_vram_mirror(addr)
                ret = self.palette_ram[pal_addr]
                self.read_buffer = self.vram[self.get_vram_mirror(addr - 0x1000)]
            # Auto-increment v after read.
            self.increment_v_2007()
            return ret
        return 0


    cpdef public void render_scanline(self, int line):
        """Render background pixels for one scanline.

        Args:
            line: Visible scanline index in framebuffer (`0-239`).

        Returns:
            None.

        Side Effects:
            Writes RGB pixels into framebuffer row and updates per-pixel
            background coverage map used for sprite priority/hit logic.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_rendering
            https://www.nesdev.org/wiki/PPU_nametables
        """
        # Background rendering can be masked off via PPUMASK bit 3.
        if not (self.mask & 0x08):
            return

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

        # Decode current VRAM scrolling state into coarse/fine components.
        fine_y        = (self.v >> 12) & 7
        coarse_y_v    = (self.v >> 5)  & 31
        nt_select     = (self.v >> 10) & 3
        coarse_x_start = self.v & 31
        fine_x_start  = self.snap_fine_x

        # Base nametable selection.
        nt_x_base = nt_select & 1
        nt_y_base = (nt_select >> 1) & 1
        tile_y    = coarse_y_v

        # Background pattern table base comes from PPUCTRL bit 4.
        bg_pattern_base = 0x1000 if (self.ctrl & 0x10) else 0x0000

        # Detect all-zero palette RAM edge case and keep deterministic output.
        palette_empty = True
        for i in range(32):
            if palette_ram[i] != 0:
                palette_empty = False
                break
        # Universal background color index.
        pal0 = palette_ram[0] & 0x3F

        # Cached tile fetch values reused for 8 pixels.
        tile_valid = False
        low = 0
        high = 0
        palette_index = 0
        prev_tile_x_offset = -1

        # Render every visible x coordinate.
        for x in range(256):
            # Convert pixel position to tile-relative coordinates with fine X.
            pixel_total     = fine_x_start + x
            tile_x_offset   = pixel_total >> 3
            pixel_in_tile_x = pixel_total & 7

            if tile_x_offset != prev_tile_x_offset:
                # Entered a new tile: fetch tile index/pattern/attribute once.
                prev_tile_x_offset = tile_x_offset

                coarse_x_abs  = coarse_x_start + tile_x_offset
                tile_x        = coarse_x_abs & 31
                current_nt_x  = nt_x_base ^ ((coarse_x_abs >> 5) & 1)
                current_nt_y  = nt_y_base
                current_nt    = (current_nt_y * 2) + current_nt_x

                # Read tile id from mirrored nametable.
                nt_addr = self.get_vram_mirror(0x2000 + (current_nt * 0x400) + tile_y * 32 + tile_x)
                tile_index  = vram[nt_addr]
                tile_offset = bg_pattern_base + tile_index * 16

                tile_valid = True
                # Load bitplanes for current fine Y row.
                low  = self._read_chr(<uint16_t>(tile_offset + fine_y))
                high = self._read_chr(<uint16_t>(tile_offset + 8 + fine_y))

                # Read 2-bit palette selector from attribute table quadrant.
                attr_addr = self.get_vram_mirror(
                    0x2000 + (current_nt * 0x400) + 0x3C0 + ((tile_y >> 2) * 8) + (tile_x >> 2)
                )
                attr_byte     = vram[attr_addr]
                shift         = ((tile_y & 0x02) << 1) | (tile_x & 0x02)
                palette_index = (attr_byte >> shift) & 0x03

            if tile_valid:
                # Extract per-pixel color index (0..3) from two bitplanes.
                bit0 = (low  >> (7 - pixel_in_tile_x)) & 1
                bit1 = (high >> (7 - pixel_in_tile_x)) & 1
                pix  = (bit1 << 1) | bit0
            else:
                pix = 0

            # Left-edge background mask (first 8 pixels).
            if x < 8 and not (self.mask & 0x02):
                pix = 0

            if palette_empty or pix == 0:
                # Transparent/background pixel uses universal backdrop color.
                pal_idx = pal0
            else:
                # Non-zero pixel selects palette entry 1..3 within sub-palette.
                pal_idx = palette_ram[palette_index * 4 + pix] & 0x3F
            
            # Store bg coverage for sprite priority and sprite0-hit checks.
            scanline_bg[x] = pix
            # Write final RGB to framebuffer.
            frame_buffer[line, x, 0] = nes_palette[pal_idx, 0]
            frame_buffer[line, x, 1] = nes_palette[pal_idx, 1]
            frame_buffer[line, x, 2] = nes_palette[pal_idx, 2]

    cdef int _find_sprite0_hit_x(self, int line):
        cdef int y, x, height, tile_index, attr
        cdef bint flip_x, flip_y
        cdef int scanline_y, tile_row, tile_offset, bank, base_index
        cdef int sprite_table_base
        cdef uint8_t low, high, bit0, bit1, pix
        cdef int col, sx

        # Need CHR source and both bg/sprite rendering enabled.
        if not self._has_chr_source():
            return -1
        if (self.mask & 0x18) != 0x18:
            return -1

        # Sprite 0 data is always first 4 bytes in OAM.
        y = int(self.oam_data[0]) + 1
        x = int(self.oam_data[3])
        height = 16 if (self.ctrl & 0x20) else 8
        # Early out if current scanline is outside sprite vertical range.
        if line < y or line >= y + height:
            return -1

        tile_index = int(self.oam_data[1])
        attr = int(self.oam_data[2])
        flip_x = (attr & 0x40) != 0
        flip_y = (attr & 0x80) != 0

        # Resolve sprite row considering vertical flip.
        scanline_y = line - y
        if flip_y:
            scanline_y = (height - 1) - scanline_y

        # Sprite pattern table base from PPUCTRL bit 3 (8x8 mode).
        sprite_table_base = 0x1000 if (self.ctrl & 0x08) else 0x0000

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

        # Fetch sprite pattern row bitplanes.
        low = self._read_chr(<uint16_t>(tile_offset + tile_row))
        high = self._read_chr(<uint16_t>(tile_offset + 8 + tile_row))

        # Scan visible sprite pixels to find first overlapping non-zero bg pixel.
        for col in range(8):
            sx = x + (7 - col if flip_x else col)
            if sx < 0 or sx >= 256:
                continue
            if sx == 255:
                continue
            if sx < 8 and (self.mask & 0x06) != 0x06:
                continue

            bit0 = (low >> (7 - col)) & 1
            bit1 = (high >> (7 - col)) & 1
            pix = (bit1 << 1) | bit0
            if pix == 0:
                continue
            if int(self.scanline_bg[sx]) == 0:
                continue
            # First valid overlap x becomes sprite-0-hit trigger location.
            return sx

        return -1

    cpdef public void sprite_evaluate(self):
        """Select up to 8 visible sprites for current scanline.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Populates scanline sprite buffer, updates sprite count, tracks sprite
            0 presence, and sets overflow status when applicable.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_OAM
            https://www.nesdev.org/wiki/PPU_sprite_evaluation
        """
        cdef int oam_idx, y, start, j
        cdef int height = 16 if (self.ctrl & 0x20) else 8
        cdef int found = 0
        cdef bint overflow = False
        
        # Reset per-line sprite cache and flags.
        self.sprite_count = 0
        self.sprite0_hit = 0
        self.sprite0_in_scanline = -1
        
        # Walk full primary OAM (64 sprites * 4 bytes).
        for oam_idx in range(0, 256, 4):
            y = int(self.oam_data[oam_idx]) + 1
            if self.scanline >= y and self.scanline < y + height:
                if found < 8:
                    # Copy sprite into secondary scanline OAM (up to 8 sprites).
                    start = found * 4
                    for j in range(4):
                        self.scanline_oam[start + j] = self.oam_data[oam_idx + j]
                    if oam_idx == 0:
                        # Remember where sprite 0 landed inside scanline buffer.
                        self.sprite0_in_scanline = found
                    found += 1
                else:
                    # More than 8 in range sets sprite overflow flag.
                    overflow = True
        self.sprite_count = found
        if overflow:
            self.status |= 0x20

    cpdef public void sprite_render(self):
        """Composite sprite pixels for current scanline.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Writes sprite RGB values into framebuffer according to transparency,
            priority, clipping, and palette rules.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_rendering
            https://www.nesdev.org/wiki/PPU_OAM
        """
        if not self._has_chr_source():
            return
        if not (self.mask & 0x10):
            return
            
        # Sprite size from PPUCTRL bit 5.
        cdef int height = 16 if (self.ctrl & 0x20) else 8
        cdef int sprite_table_base
        # Sprite pattern table in 8x8 mode.
        sprite_table_base = 0x1000 if (self.ctrl & 0x08) else 0x0000
        cdef int i, base, y, tile_index, attr, x, palette_index
        cdef bint flip_x, flip_y, priority_front
        cdef int scanline_y, tile_row, tile_offset, bank, base_index
        cdef uint8_t low, high, bit0, bit1
        cdef int col, sx, pix, bg_pix, pal_idx
        
        # Render back-to-front by iterating secondary OAM in reverse.
        for i in range(self.sprite_count - 1, -1, -1):
            base = i * 4
            y = int(self.scanline_oam[base]) + 1
            tile_index = int(self.scanline_oam[base + 1])
            attr = int(self.scanline_oam[base + 2])
            x = int(self.scanline_oam[base + 3])
            
            # Decode sprite attributes.
            flip_x = (attr & 0x40) != 0
            flip_y = (attr & 0x80) != 0
            palette_index = (attr & 0x3) + 4
            priority_front = (attr & 0x20) == 0
            
            scanline_y = self.scanline - y
            # Skip sprites not covering this scanline.
            if scanline_y < 0 or scanline_y >= height:
                continue
                
            if flip_y:
                scanline_y = (height - 1) - scanline_y

            # Resolve sprite tile address for 8x8/8x16 modes.
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

            # Fetch sprite row bitplanes.
            low = self._read_chr(<uint16_t>(tile_offset + tile_row))
            high = self._read_chr(<uint16_t>(tile_offset + 8 + tile_row))
            
            for col in range(8):
                # Compute screen x accounting for horizontal flip.
                sx = x + (7 - col if flip_x else col)
                if sx < 0 or sx >= 256:
                    continue
                # Left-edge sprite mask from PPUMASK bit 2.
                if sx < 8 and not (self.mask & 0x04):
                    continue
                    
                bit0 = (low >> (7 - col)) & 1
                bit1 = (high >> (7 - col)) & 1
                pix = (bit1 << 1) | bit0
                
                if pix == 0:
                    # Color index 0 is transparent for sprites.
                    continue
                    
                bg_pix = int(self.scanline_bg[sx])
                
                if priority_front or bg_pix == 0:
                    # Draw sprite pixel in front, or when bg is transparent.
                    pal_idx = int(self.palette_ram[palette_index * 4 + pix]) & 0x3F
                    self.frame_buffer[self.scanline, sx] = self.nes_palette[pal_idx]

    cpdef public void perform_dma(self, uint8_t[:] page):
        """Copy one 256-byte page into OAM (DMA behavior).

        Args:
            page: 256-byte source buffer prepared by CPU bus reads.

        Returns:
            None.

        Side Effects:
            Overwrites OAM contents starting at current OAM address.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_OAM
            https://www.nesdev.org/wiki/DMA
        """
        cdef int i
        # CPU provides exactly 256 bytes from the selected memory page.
        for i in range(256):
            # DMA writes into OAM starting from current OAMADDR and wrapping.
            self.oam_data[self.oam_addr] = page[i]
            self.oam_addr += 1