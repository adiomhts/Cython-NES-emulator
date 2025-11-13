import numpy as np
from libc.stdint cimport uint8_t, uint16_t

cdef class PPU:
    # Core state
    cdef int scanline, cycle
    cdef public object frame_buffer
    cdef public uint8_t[:] oam_data
    cdef public uint8_t[:] vram
    cdef public uint8_t[:] palette_ram
    cdef uint8_t mirroring, vblank_flag
    # Registers
    cdef public uint8_t ctrl, mask, status, oam_addr, fine_x
    cdef uint16_t vram_addr, temp_vram_addr
    cdef uint8_t write_toggle
    # Scroll
    cdef uint8_t scroll_x, scroll_y
    # Buffered read for $2007
    cdef uint8_t read_buffer
    # Internal latches
    cdef uint16_t v, t
    cdef uint8_t x
    cdef uint8_t address_latch
    # Sprite evaluation
    cdef uint8_t[:] scanline_oam
    cdef int sprite_count
    cdef uint8_t sprite0_hit
    cdef uint8_t[:] scanline_bg
    cdef int sprite0_in_scanline
    cdef bint _debug_force_palette
    # NES palette (real values, 64 colors)
    cdef int[:, :] nes_palette
    cdef public object chr_rom
    cdef public object cpu
    cdef int diag_name_write_count
    cdef int diag_palette_write_count
    cdef int diag_render_sample_count
    cdef int diag_render_sample_limit
    cdef public object diag_sprite_events
    cdef int diag_sprite_event_count
    cdef int diag_sprite_event_limit

    def __init__(self, mirroring=0):
        self.scanline = 0
        self.cycle = 0
        self.frame_buffer = np.zeros((240, 256, 3), dtype=np.uint8)
        self.oam_data = np.zeros(256, dtype=np.uint8)
        self.vram = np.zeros(2048, dtype=np.uint8)
        # Default palette RAM (start zero, games will write real values). Fallback rendering will show tiles if empty.
        self.palette_ram = np.zeros(32, dtype=np.uint8)
        self.mirroring = mirroring
        self.vblank_flag = 0
        self.ctrl = 0
        self.mask = 0
        self.status = 0
        self.oam_addr = 0
        self.fine_x = 0
        self.vram_addr = 0
        self.temp_vram_addr = 0
        self.write_toggle = 0
        self.scroll_x = 0
        self.scroll_y = 0
        self.read_buffer = 0
        self.v = 0
        self.t = 0
        self.x = 0
        self.address_latch = 0
        self.scanline_oam = np.zeros(32, dtype=np.uint8)
        self.sprite_count = 0
        self.sprite0_hit = 0
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
        self.scanline_bg = np.zeros(256, dtype=np.uint8)
        self.sprite0_in_scanline = -1
        self._debug_force_palette = False
        # Diagnostic counters to avoid flooding logs
        self.diag_name_write_count = 0
        self.diag_palette_write_count = 0
        self.diag_render_sample_count = 0
        # Limit how many tiles we sample and print per run to avoid huge logs
        self.diag_render_sample_limit = 4
        # Sprite diagnostic event capture (small Python list of tuples)
        self.diag_sprite_events = []
        self.diag_sprite_event_count = 0
        self.diag_sprite_event_limit = 64

    cpdef public void step(self):
        # Full scanline/cycle logic, including background/sprite fetches, scroll reloads, NMI, etc.
        # 262 scanlines, 341 cycles per scanline
        # Pre-render line: scanline -1 (here, 261)
        # Visible: 0-239, Post-render: 240, VBlank: 241-260
        self.cycle += 1
        if self.cycle >= 341:
            self.cycle = 0
            self.scanline += 1
            if self.scanline == 241:
                self.trigger_vblank()
            elif self.scanline == 261:
                # Pre-render line: clear VBlank, sprite 0 hit, sprite overflow
                self.vblank_flag = 0
                self.status &= ~0x80
                self.sprite0_hit = 0
                self.status &= ~0x40
                self.status &= ~0x20
            elif self.scanline >= 262:
                self.scanline = 0
        # Visible scanlines: 0-239
        if 0 <= self.scanline < 240:
            # Render the whole scanline once the background fetches are complete (cycle 256)
            if self.cycle == 256:
                self.render_scanline(self.scanline)
                # After background for the scanline is ready, overlay sprites
                self.sprite_render()
            # Sprite evaluation for next scanline occurs at cycle 257
            if self.cycle == 257:
                self.sprite_evaluate()
        # Sprite 0 hit detection (simple version)
        if self.sprite0_hit:
            self.status |= 0x40
        # Sprite overflow flag (simple version)
        if self.sprite_count > 8:
            self.status |= 0x20

    cpdef public void trigger_vblank(self):
        self.vblank_flag = 1
        self.status |= 0x80  # Set VBlank flag
        # Diagnostic: dump palette RAM when VBlank starts
        try:
            # show nonzero entries compactly
            nonzero = [(i, int(self.palette_ram[i])) for i in range(32) if int(self.palette_ram[i]) != 0]
            # print(f"PPU VBlank: palette nonzero entries: {nonzero}")
        except Exception:
            pass
        # If NMI is enabled in PPUCTRL ($2000 bit 7), trigger CPU NMI
        try:
            if getattr(self, 'cpu', None) is not None and (self.ctrl & 0x80):
                # CPU.trigger_interrupt(0) is NMI
                try:
                    self.cpu.trigger_interrupt(0)
                    # print('PPU: triggered NMI on CPU')
                except Exception:
                    pass
        except Exception:
            pass

    cdef int get_vram_mirror(self, int addr):
        # NES VRAM mirroring logic, including $3000–$3EFF
        addr = addr & 0x3FFF
        if 0x2000 <= addr < 0x3F00:
            nt = (addr - 0x2000) // 0x400
            offset = addr & 0x3FF
            # Horizontal mirroring: NT0/NT1 -> A, NT2/NT3 -> B
            # Vertical mirroring: NT0/NT2 -> A, NT1/NT3 -> B
            if self.mirroring == 0:  # Horizontal
                bank = (nt >> 1) & 1
                return bank * 0x400 + offset
            else:  # Vertical
                bank = nt & 1
                return bank * 0x400 + offset
        elif 0x3F00 <= addr < 0x4000:
            # Palette RAM mirroring
            pal_addr = (addr - 0x3F00) & 0x1F
            if pal_addr in [0x10, 0x14, 0x18, 0x1C]:
                pal_addr -= 0x10
            return pal_addr
        return 0

    cpdef public void write_register(self, uint16_t reg, uint8_t value):
        reg = reg & 0x2007  # Mirror every 8 bytes
        if reg == 0x2000:
            self.ctrl = value
            self.t = (self.t & 0xF3FF) | ((value & 0x03) << 10)
        elif reg == 0x2001:
            self.mask = value
        elif reg == 0x2002:
            self.status = value
        elif reg == 0x2003:
            self.oam_addr = value
        elif reg == 0x2004:
            self.oam_data[self.oam_addr] = value
            self.oam_addr += 1
        elif reg == 0x2005:
            if self.address_latch == 0:
                self.scroll_x = value
                self.x = value & 0x07
                self.t = (self.t & 0xFFE0) | (value >> 3)
                self.address_latch = 1
            else:
                self.scroll_y = value
                self.t = (self.t & 0x8FFF) | ((value & 0x07) << 12)
                self.t = (self.t & 0xFC1F) | ((value & 0xF8) << 2)
                self.address_latch = 0
        elif reg == 0x2006:
            if self.address_latch == 0:
                self.t = (self.t & 0x00FF) | ((value & 0x3F) << 8)
                self.address_latch = 1
                # try:
                #     print(f"PPU: write $2006 high -> t={self.t:#06x} (value={value:#04x}) @ scanline {self.scanline} cycle {self.cycle}")
                # except Exception:
                #     pass
            else:
                self.t = (self.t & 0xFF00) | value
                self.v = self.t
                self.vram_addr = self.v
                self.address_latch = 0
                # try:
                #     print(f"PPU: write $2006 low -> v={self.v:#06x} (value={value:#04x}) @ scanline {self.scanline} cycle {self.cycle}")
                # except Exception:
                #     pass
        elif reg == 0x2007:
            addr = self.vram_addr & 0x3FFF
            if 0x2000 <= addr < 0x3F00:
                phys = self.get_vram_mirror(addr)
                try:
                    # Include CPU PC if available for tracing origin
                    cpu_pc = getattr(getattr(self, 'cpu', None), 'PC', None)
                    # if cpu_pc is not None:
                    #     print(f"PPU: write $2007 -> vram[{addr:#06x}] (phys {phys:#06x}) = {value:#04x} @ scanline {self.scanline} cycle {self.cycle} (CPU.PC={cpu_pc:#06x})")
                    # else:
                    #     print(f"PPU: write $2007 -> vram[{addr:#06x}] (phys {phys:#06x}) = {value:#04x} @ scanline {self.scanline} cycle {self.cycle}")
                except Exception:
                    pass
                self.vram[phys] = value
                # Always log the first N name-table writes so we can catch the offending one
                try:
                    if self.diag_name_write_count < 200:
                        neigh_start = max(0, phys - 4)
                        neigh_end = min(len(self.vram), phys + 5)
                        neigh = [int(x) for x in self.vram[neigh_start:neigh_end]]
                        #  print(f"PPU-DIAG: name-table write #{self.diag_name_write_count} phys={phys:#04x} addr={addr:#06x} value={value:#04x} neigh={neigh} @ scanline {self.scanline} cycle {self.cycle}")
                        self.diag_name_write_count += 1
                except Exception:
                    pass
                # Conditional diagnostic: if a large tile index was written into name-table VRAM
                try:
                    chr = getattr(self, 'chr_rom', None)
                    if chr is not None and (int(value) * 16) >= len(chr):
                        # Log concise context to help track down bad writes
                        neigh_start = max(0, phys - 4)
                        neigh_end = min(len(self.vram), phys + 5)
                        neigh = [int(x) for x in self.vram[neigh_start:neigh_end]]
                        #  print(f"PPU-DIAG: suspicious tile write at vram phys {phys:#04x} (addr {addr:#06x}) = {value:#04x}; chr_len={len(chr)}; neigh={neigh} @ scanline {self.scanline} cycle {self.cycle}")
                except Exception:
                    pass
            elif 0x3F00 <= addr < 0x4000:
                pal_addr = self.get_vram_mirror(addr)
                # Log palette writes for debugging/diagnostics
                # try:
                #     #  print(f"PPU: write palette [{pal_addr:#04x}] = {value:#04x} @ scanline {self.scanline} cycle {self.cycle}")
                # except Exception:
                #     pass
                self.palette_ram[pal_addr] = value
                # Also log the first several palette writes with CPU PC and neighbor context
                try:
                    cpu_pc = getattr(getattr(self, 'cpu', None), 'PC', None)
                    if self.diag_palette_write_count < 64:
                        neigh_start = max(0, pal_addr - 4)
                        neigh_end = min(32, pal_addr + 5)
                        neigh = [int(x) for x in self.palette_ram[neigh_start:neigh_end]]
                        # if cpu_pc is not None:
                            #  print(f"PPU-DIAG: palette write #{self.diag_palette_write_count} addr={addr:#06x} pal={pal_addr:#04x} value={value:#04x} neigh={neigh} (CPU.PC={cpu_pc:#06x}) @ scanline {self.scanline} cycle {self.cycle}")
                        # else:
                            #  print(f"PPU-DIAG: palette write #{self.diag_palette_write_count} addr={addr:#06x} pal={pal_addr:#04x} value={value:#04x} neigh={neigh} @ scanline {self.scanline} cycle {self.cycle}")
                        self.diag_palette_write_count += 1
                except Exception:
                    pass
            self.vram_addr += 1 if (self.ctrl & 0x04) == 0 else 32

    cpdef public uint8_t read_register(self, uint16_t reg):
        reg = reg & 0x2007
        if reg == 0x2002:
            self.address_latch = 0
            ret = self.status
            self.status &= ~0x80  # Clear VBlank
            return ret
        elif reg == 0x2004:
            return self.oam_data[self.oam_addr]
        elif reg == 0x2007:
            addr = self.vram_addr & 0x3FFF
            if addr < 0x3F00:
                ret = self.read_buffer
                self.read_buffer = self.vram[self.get_vram_mirror(addr)]
            else:
                pal_addr = self.get_vram_mirror(addr)
                ret = self.palette_ram[pal_addr]
                self.read_buffer = self.vram[self.get_vram_mirror(addr - 0x1000)]
            self.vram_addr += 1 if (self.ctrl & 0x04) == 0 else 32
            return ret
        return 0

    cpdef public void render_frame(self, chr_rom):
        # Keep a reference to CHR so scanline rendering/sprites can access it
        self.chr_rom = chr_rom
        # Fast full-frame render (tile-based). Useful for non-cycle-accurate rendering / debug.
        cdef int tile_y, tile_x, row, col
        cdef int nt_addr, tile_index, tile_offset, attr_addr, attr_byte, palette_index
        cdef uint8_t pixel_value, bit0, bit1
        for tile_y in range(30):
            for tile_x in range(32):
                nt_addr = self.get_vram_mirror(0x2000 + tile_y * 32 + tile_x)
                tile_index = self.vram[nt_addr]
                tile_offset = tile_index * 16
                if tile_offset + 16 > len(chr_rom):
                    try:
                        # Log out-of-range tile reads: name-table addr and nearby vram
                        neigh_start = max(0, nt_addr - 4)
                        neigh_end = min(len(self.vram), nt_addr + 5)
                        neigh = [int(x) for x in self.vram[neigh_start:neigh_end]]
                        # print(f"PPU-DIAG: render_frame oob: nt_addr={nt_addr:#06x} tile_index={tile_index} tile_offset={tile_offset} chr_len={len(chr_rom)} neigh={neigh}")
                    except Exception:
                        pass
                    continue
                tile_data = chr_rom[tile_offset:tile_offset + 16]
                # Attribute table decoding
                attr_addr = self.get_vram_mirror(0x23C0 + ((tile_y // 4) * 8) + (tile_x // 4))
                attr_byte = self.vram[attr_addr]
                shift = ((tile_y % 4) // 2) * 4 + ((tile_x % 4) // 2) * 2
                palette_index = (attr_byte >> shift) & 0x03
                for row in range(8):
                    low_byte = tile_data[row]
                    high_byte = tile_data[row + 8]
                    for col in range(8):
                        bit0 = (low_byte >> (7 - col)) & 1
                        bit1 = (high_byte >> (7 - col)) & 1
                        pixel_value = (bit1 << 1) | bit0
                        color_index = self.palette_ram[palette_index * 4 + pixel_value] & 0x3F
                        color = self.nes_palette[color_index]
                        screen_x = tile_x * 8 + col
                        screen_y = tile_y * 8 + row
                        if 0 <= screen_x < 256 and 0 <= screen_y < 240:
                            self.frame_buffer[screen_y, screen_x] = color

    cpdef public void sprite_evaluate(self):
        # Evaluate sprites for the next scanline (NES: max 8 sprites per scanline)
        self.sprite_count = 0
        self.sprite0_hit = 0
        self.sprite0_in_scanline = -1
        height = 16 if (self.ctrl & 0x20) else 8
        found = 0
        overflow = False
        for oam_idx in range(0, 256, 4):
            y = int(self.oam_data[oam_idx]) + 1
            if self.scanline >= y and self.scanline < y + height:
                if found < 8:
                    # Copy sprite data to scanline_oam
                    start = found * 4
                    for j in range(4):
                        self.scanline_oam[start + j] = self.oam_data[oam_idx + j]
                    if oam_idx == 0:
                        self.sprite0_in_scanline = found
                    found += 1
                else:
                    overflow = True
                # continue scanning to mimic hardware overflow behavior
        self.sprite_count = found
        if overflow:
            self.status |= 0x20

    cpdef public void sprite_render(self):
        # Render sprites for the current scanline. Uses self.chr_rom and self.scanline_bg
        if self.chr_rom is None:
            return
        height = 16 if (self.ctrl & 0x20) else 8
        sprite_table_base = 0x1000 if (self.ctrl & 0x08) else 0x0000
        for i in range(self.sprite_count):
            base = i * 4
            y = int(self.scanline_oam[base])
            tile_index = int(self.scanline_oam[base + 1])
            attr = int(self.scanline_oam[base + 2])
            x = int(self.scanline_oam[base + 3])
            flip_x = (attr & 0x40) != 0
            flip_y = (attr & 0x80) != 0
            palette_index = (attr & 0x3) + 4
            priority_front = (attr & 0x20) == 0
            scanline_y = self.scanline - y
            if scanline_y < 0 or scanline_y >= height:
                continue
            # For 8x8 sprites; for 8x16 we'd need to select bank
            # Determine correct tile offset depending on sprite height
            if height == 8:
                tile_row = scanline_y
                if flip_y:
                    tile_row = 7 - scanline_y
                tile_offset = sprite_table_base + tile_index * 16
                if tile_offset + 8 >= len(self.chr_rom):
                    continue
                low = self.chr_rom[tile_offset + tile_row]
                high = self.chr_rom[tile_offset + 8 + tile_row]
            else:
                # 8x16: pattern table selected by low bit of tile_index
                bank = (tile_index & 1) * 0x1000
                base_index = tile_index & 0xFE
                # top or bottom tile depending on row
                if scanline_y < 8:
                    tile_row = scanline_y
                    tile_offset = bank + base_index * 16
                else:
                    tile_row = scanline_y - 8
                    tile_offset = bank + (base_index + 1) * 16
                if tile_offset + 8 >= len(self.chr_rom):
                    continue
                if flip_y:
                    tile_row = (7 - tile_row)
                low = self.chr_rom[tile_offset + tile_row]
                high = self.chr_rom[tile_offset + 8 + tile_row]
            for col in range(8):
                sx = x + (7 - col if flip_x else col)
                if sx < 0 or sx >= 256:
                    continue
                bit0 = (low >> (7 - col)) & 1
                bit1 = (high >> (7 - col)) & 1
                pix = (bit1 << 1) | bit0
                if pix == 0:
                    continue
                # Background pixel value for priority decision
                bg_pix = int(self.scanline_bg[sx])
                # Sprite palette lookup
                pal_idx = int(self.palette_ram[palette_index * 4 + pix]) & 0x3F
                color = self.nes_palette[pal_idx]
                # Sprite 0 hit: if this sprite originated from OAM index 0
                if self.sprite0_in_scanline == i and bg_pix != 0:
                    # Set sprite0 hit flag
                    self.sprite0_hit = 1
                    self.status |= 0x40
                # Draw depending on priority: front sprites always draw over background
                if priority_front or bg_pix == 0:
                    # Capture a small number of sprite overlay events for diagnostics
                    try:
                        if self.diag_sprite_event_count < self.diag_sprite_event_limit:
                            # (scanline, screen_x, sprite_index, sprite_palette, pix, pal_idx)
                            self.diag_sprite_events.append((int(self.scanline), int(sx), int(i), int(palette_index), int(pix), int(pal_idx)))
                            self.diag_sprite_event_count += 1
                    except Exception:
                        pass
                    self.frame_buffer[self.scanline, sx] = color

    cpdef public void render_scanline(self, int line):
        # Render background for a single scanline into frame_buffer and scanline_bg
        if self.chr_rom is None:
            return
        cdef bint palette_empty = True
        for i in range(32):
            if int(self.palette_ram[i]) != 0:
                palette_empty = False
                break
        cdef int x
        for x in range(256):
            tile_x = x // 8
            tile_y = line // 8
            nt_addr = self.get_vram_mirror(0x2000 + tile_y * 32 + tile_x)
            tile_index = int(self.vram[nt_addr])
            tile_offset = tile_index * 16
            pixel_in_tile_x = x & 7
            pixel_in_tile_y = line & 7
            if tile_offset + 16 > len(self.chr_rom):
                try:
                    neigh_start = max(0, nt_addr - 4)
                    neigh_end = min(len(self.vram), nt_addr + 5)
                    neigh = [int(x) for x in self.vram[neigh_start:neigh_end]]
                    # print(f"PPU-DIAG: render_scanline oob: nt_addr={nt_addr:#06x} tile_index={tile_index} tile_offset={tile_offset} chr_len={len(self.chr_rom)} neigh={neigh} @ line={line}")
                except Exception:
                    pass
                # fallback to color 0
                self.scanline_bg[x] = 0
                self.frame_buffer[line, x] = self.nes_palette[self.palette_ram[0] & 0x3F]
                continue
            low = self.chr_rom[tile_offset + pixel_in_tile_y]
            high = self.chr_rom[tile_offset + 8 + pixel_in_tile_y]
            bit0 = (low >> (7 - pixel_in_tile_x)) & 1
            bit1 = (high >> (7 - pixel_in_tile_x)) & 1
            pix = (bit1 << 1) | bit0
            # Attribute
            attr_addr = self.get_vram_mirror(0x23C0 + ((tile_y // 4) * 8) + (tile_x // 4))
            attr_byte = int(self.vram[attr_addr])
            shift = ((tile_y % 4) // 2) * 4 + ((tile_x % 4) // 2) * 2
            palette_index = (attr_byte >> shift) & 0x03
            # Diagnostic: sample a few tiles to inspect attribute/palette/CHR bytes
            try:
                # Sample more tiles across the top-left area and also periodically across the width
                # to get a broader picture of attribute/palette mapping.
                # We sample at the top-left pixel of a tile (pixel_in_tile_x==0 and pixel_in_tile_y==0)
                if self.diag_render_sample_count < self.diag_render_sample_limit and pixel_in_tile_x == 0 and pixel_in_tile_y == 0:
                    # Collect CHR bytes for this tile (if present)
                    if tile_offset + 16 <= len(self.chr_rom):
                        tile_bytes = [int(b) for b in self.chr_rom[tile_offset:tile_offset + 16]]
                    else:
                        tile_bytes = []
                    # Gather palette RAM entries for the selected palette (4 entries)
                    pal_entries = []
                    base = palette_index * 4
                    for pi in range(4):
                        idx = base + pi
                        if 0 <= idx < 32:
                            pal_entries.append(int(self.palette_ram[idx]))
                        else:
                            pal_entries.append(None)
                    # Also grab the universal background color (palette_ram[0]) and full palette slice
                    try:
                        bg0 = int(self.palette_ram[0])
                        full_pal = [int(x) for x in self.palette_ram]
                    except Exception:
                        bg0 = None
                        full_pal = []
                    cpu_pc = getattr(getattr(self, 'cpu', None), 'PC', None)
                    if cpu_pc is not None:
                        print(f"PPU-DIAG-RENDER tile({tile_x},{tile_y}) nt={nt_addr:#06x} tile_index={tile_index} tile_offset={tile_offset} attr_addr={attr_addr:#04x} attr_byte={attr_byte:#04x} palette_index={palette_index} pal_entries={pal_entries} bg0={bg0} chr_first8={tile_bytes[:8]} (CPU.PC={cpu_pc:#06x})")
                    else:
                        print(f"PPU-DIAG-RENDER tile({tile_x},{tile_y}) nt={nt_addr:#06x} tile_index={tile_index} tile_offset={tile_offset} attr_addr={attr_addr:#04x} attr_byte={attr_byte:#04x} palette_index={palette_index} pal_entries={pal_entries} bg0={bg0} chr_first8={tile_bytes[:8]}")
                    self.diag_render_sample_count += 1
            except Exception:
                pass
            if palette_empty and not self._debug_force_palette:
                # Conservative fallback when palette RAM truly empty: use universal background color
                pal_idx = int(self.palette_ram[0]) & 0x3F
            else:
                pal_idx = int(self.palette_ram[palette_index * 4 + pix]) & 0x3F
            self.scanline_bg[x] = pix
            self.frame_buffer[line, x] = self.nes_palette[pal_idx]

    cpdef public void render_debug_chr(self):
        # Visualize CHR tiles directly (ignores palette RAM). Useful to debug CHR/VRAM loading.
        if self.chr_rom is None:
            return
        # Layout: draw 16x16 tiles per pattern table (256 tiles) per table
        tiles_per_row = 16
        for tile_idx in range(min(256, len(self.chr_rom) // 16)):
            tile_x = (tile_idx % tiles_per_row) * 8
            tile_y = (tile_idx // tiles_per_row) * 8
            tile_offset = tile_idx * 16
            for row in range(8):
                low = int(self.chr_rom[tile_offset + row])
                high = int(self.chr_rom[tile_offset + 8 + row])
                for col in range(8):
                    bit0 = (low >> (7 - col)) & 1
                    bit1 = (high >> (7 - col)) & 1
                    pix = (bit1 << 1) | bit0
                    # Map 2-bit pixel to visible colors
                    map_idx = [0, 21, 42, 63][pix] & 0x3F
                    color = self.nes_palette[map_idx]
                    sx = tile_x + col
                    sy = tile_y + row
                    if 0 <= sx < 256 and 0 <= sy < 240:
                        self.frame_buffer[sy, sx] = color
    cpdef void render_pixel(self, int x, int y):
        # Render a single pixel, including background and sprite priority
        # Background
        tile_x = x // 8
        tile_y = y // 8
        nt_addr = self.get_vram_mirror(0x2000 + tile_y * 32 + tile_x)
        tile_index = self.vram[nt_addr]
        tile_offset = tile_index * 16
        # Attribute table decoding
        attr_addr = self.get_vram_mirror(0x23C0 + ((tile_y // 4) * 8) + (tile_x // 4))
        attr_byte = self.vram[attr_addr]
        shift = ((tile_y % 4) // 2) * 4 + ((tile_x % 4) // 2) * 2
        palette_index = (attr_byte >> shift) & 0x03
        # Fetch tile data
        # For now, assume CHR ROM is not available here
        # Use a dummy pattern
        pixel_value = 0
        color_index = self.palette_ram[palette_index * 4 + pixel_value] & 0x3F
        color = self.nes_palette[color_index]
        # Sprite priority (stub)
        # TODO: Blend sprite pixel if nonzero, handle priority
        self.frame_buffer[y, x] = color

    cpdef public void perform_dma(self, uint8_t[:] page):
        for i in range(256):
            self.oam_data[i] = page[i]