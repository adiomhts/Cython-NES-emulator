# ppu.pyx
import numpy as np
cimport numpy as cnp
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
    
    # VRAM addresses
    cdef uint16_t v, t
    cdef uint8_t write_toggle
    
    # Scroll
    cdef uint8_t scroll_x, scroll_y
    
    # Buffered read
    cdef uint8_t read_buffer
    
    # Sprite evaluation
    cdef uint8_t[:] scanline_oam
    cdef int sprite_count
    cdef uint8_t sprite0_hit
    cdef uint8_t[:] scanline_bg
    cdef int sprite0_in_scanline
    cdef bint _debug_force_palette
    
    # NES palette
    cdef int[:, :] nes_palette
    
    cdef public object chr_rom
    cdef public object cpu

    def __init__(self, mirroring=0):
        self.scanline = 0
        self.cycle = 0
        self.frame_buffer = np.zeros((240, 256, 3), dtype=np.uint8)
        
        self.oam_data = np.zeros(256, dtype=np.uint8)
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
        self.read_buffer = 0
        
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

    # === Helpers ===
    
    cdef void increment_v(self):
        self.v += 32 if (self.ctrl & 0x04) else 1

    cdef void increment_scroll_y(self):
        cdef int y
        if (self.v & 0x7000) != 0x7000:
            self.v += 0x1000
        else:
            self.v &= ~0x7000
            y = (self.v & 0x03E0) >> 5
            if y == 29:
                y = 0
                self.v ^= 0x0800 
            elif y == 31:
                y = 0
            else:
                y += 1
            self.v = (self.v & ~0x03E0) | (y << 5)

    cdef void copy_x(self):
        self.v = (self.v & 0xFBE0) | (self.t & 0x041F)

    cdef void copy_y(self):
        self.v = (self.v & 0x841F) | (self.t & 0x7BE0)

    cdef int get_vram_mirror(self, int addr):
        # Объявления в начале
        cdef int pal_addr, clean_addr, table, offset, bank
        
        addr = addr & 0x3FFF 

        if addr >= 0x3F00:
            pal_addr = addr & 0x1F
            if pal_addr >= 0x10 and (pal_addr & 3) == 0:
                pal_addr -= 0x10
            return pal_addr

        if 0x2000 <= addr < 0x3F00:
            clean_addr = (addr - 0x2000) % 0x1000
            table = clean_addr // 0x400
            offset = clean_addr % 0x400
            bank = 0
            
            if self.mirroring == 0: 
                if table == 0 or table == 1: bank = 0
                else: bank = 1
            elif self.mirroring == 1: 
                if table == 0 or table == 2: bank = 0
                else: bank = 1
            
            return bank * 0x400 + offset
        return 0

    # === STEP ===

    cpdef public void step(self):
        # Все объявления в самом начале
        cdef int spr0_y, spr0_x
        cdef bint rendering_enabled
        
        self.cycle += 1
        
        rendering_enabled = (self.mask & 0x18) != 0
        
        # Sprite 0 Hit
        if rendering_enabled and not self.sprite0_hit:
            spr0_y = self.oam_data[0] + 1
            spr0_x = self.oam_data[3]
            
            if spr0_y <= self.scanline < spr0_y + 8:
                if self.cycle == spr0_x + 2: 
                    self.sprite0_hit = 1
                    self.status |= 0x40

        # Timings
        if self.cycle >= 341:
            self.cycle = 0
            self.scanline += 1
            
            if self.scanline == 241:
                self.trigger_vblank()
            
            elif self.scanline == 261:
                self.vblank_flag = 0
                self.status &= ~0xE0 
                self.sprite0_hit = 0
                if rendering_enabled:
                    self.copy_y()
            
            elif self.scanline >= 262:
                self.scanline = 0
        
        # Pre-render line (261)
        if self.scanline == 261 and rendering_enabled:
            if self.cycle == 256:
                self.increment_scroll_y()
            if self.cycle == 257:
                self.copy_x()
            if self.cycle >= 280 and self.cycle <= 304:
                self.copy_y()

        # Visible lines
        if 0 <= self.scanline < 240:
            if self.cycle == 256:
                self.render_scanline(self.scanline)
                if rendering_enabled:
                    self.increment_scroll_y()
            
            if self.cycle == 257:
                if rendering_enabled:
                    self.copy_x()
                self.sprite_evaluate()
                self.sprite_render()

    cpdef public void trigger_vblank(self):
        self.vblank_flag = 1
        self.status |= 0x80
        try:
            if getattr(self, 'cpu', None) is not None and (self.ctrl & 0x80):
                self.cpu.trigger_interrupt(0) 
        except Exception:
            pass

    # === REGISTERS ===

    cpdef public void write_register(self, uint16_t reg, uint8_t value):
        cdef int addr, phys, pal_addr
        reg = reg & 0x2007
        
        if reg == 0x2000: 
            self.ctrl = value
            self.t = (self.t & 0xF3FF) | ((value & 0x03) << 10)
            
        elif reg == 0x2001: 
            self.mask = value
            
        elif reg == 0x2002: 
            pass
            
        elif reg == 0x2003: 
            self.oam_addr = value
            
        elif reg == 0x2004: 
            self.oam_data[self.oam_addr] = value
            self.oam_addr += 1
            
        elif reg == 0x2005: 
            if self.write_toggle == 0:
                self.scroll_x = value
                self.fine_x = value & 0x07
                self.t = (self.t & 0xFFE0) | (value >> 3)
                self.write_toggle = 1
            else:
                self.scroll_y = value
                self.t = (self.t & 0x8FFF) | ((value & 0x07) << 12)
                self.t = (self.t & 0xFC1F) | ((value & 0xF8) << 2)
                self.write_toggle = 0
                
        elif reg == 0x2006: 
            if self.write_toggle == 0:
                self.t = (self.t & 0x00FF) | ((value & 0x3F) << 8)
                self.write_toggle = 1
            else:
                self.t = (self.t & 0xFF00) | value
                self.v = self.t
                self.write_toggle = 0
                
        elif reg == 0x2007: 
            addr = self.v & 0x3FFF
            if 0x2000 <= addr < 0x3F00:
                phys = self.get_vram_mirror(addr)
                self.vram[phys] = value
            elif 0x3F00 <= addr < 0x4000:
                pal_addr = self.get_vram_mirror(addr)
                self.palette_ram[pal_addr] = value
            self.increment_v()

    cpdef public uint8_t read_register(self, uint16_t reg):
        cdef int addr, pal_addr
        cdef uint8_t ret
        reg = reg & 0x2007
        
        if reg == 0x2002: 
            self.write_toggle = 0
            ret = self.status
            self.status &= ~0x80 
            return ret
            
        elif reg == 0x2004: 
            return self.oam_data[self.oam_addr]
            
        elif reg == 0x2007: 
            addr = self.v & 0x3FFF
            if addr < 0x3F00:
                ret = self.read_buffer
                self.read_buffer = self.vram[self.get_vram_mirror(addr)]
            else:
                pal_addr = self.get_vram_mirror(addr)
                ret = self.palette_ram[pal_addr]
                self.read_buffer = self.vram[self.get_vram_mirror(addr - 1000)]
            self.increment_v()
            return ret
        return 0

    # === RENDERING ===

    cpdef public void render_scanline(self, int line):
        if not (self.mask & 0x08):
            return

        if self.chr_rom is None:
            return

        # Объявляем переменные В НАЧАЛЕ
        cdef int coarse_y, nametable_y, nametable_x, coarse_x_start, fine_y, fine_x
        cdef int start_global_x, x, pixel_x_scroll
        cdef int current_nt_x, tile_x, tile_y, current_nt
        cdef int nt_addr, tile_index, tile_offset
        cdef int attr_addr, attr_byte, shift, palette_index
        cdef uint8_t low, high, bit0, bit1, pix
        cdef int pal_idx
        cdef int bg_pattern_base
        cdef bint palette_empty

        # Инициализация
        coarse_y = (self.v >> 5) & 0x1F
        nametable_y = (self.v >> 11) & 0x01
        nametable_x = (self.v >> 10) & 0x01
        coarse_x_start = (self.v & 0x1F)
        fine_y = (self.v >> 12) & 0x07
        fine_x = self.fine_x

        start_global_x = (nametable_x * 256) + (coarse_x_start * 8)
        bg_pattern_base = 0x1000 if (self.ctrl & 0x10) else 0x0000

        palette_empty = True
        for i in range(32):
            if int(self.palette_ram[i]) != 0:
                palette_empty = False
                break

        for x in range(256):
            pixel_x_scroll = start_global_x + x + fine_x
            
            current_nt_x = (pixel_x_scroll // 256) % 2
            tile_x = (pixel_x_scroll % 256) // 8
            tile_y = coarse_y
            current_nt = (nametable_y * 2) + current_nt_x
            
            nt_addr = self.get_vram_mirror(0x2000 + (current_nt * 0x400) + tile_y * 32 + tile_x)
            tile_index = int(self.vram[nt_addr])
            tile_offset = bg_pattern_base + tile_index * 16

            if tile_offset + 16 > len(self.chr_rom):
                self.scanline_bg[x] = 0
                self.frame_buffer[line, x] = self.nes_palette[self.palette_ram[0] & 0x3F]
                continue

            low = self.chr_rom[tile_offset + fine_y]
            high = self.chr_rom[tile_offset + 8 + fine_y]
            pixel_in_tile_x = (pixel_x_scroll % 8)
            bit0 = (low >> (7 - pixel_in_tile_x)) & 1
            bit1 = (high >> (7 - pixel_in_tile_x)) & 1
            pix = (bit1 << 1) | bit0

            # ВАЖНО: Используем правильную формулу атрибутов (0x23C0)
            attr_addr = self.get_vram_mirror((0x2000 + current_nt * 0x400) + 0x23C0 + (tile_y // 4) * 8 + (tile_x // 4))
            attr_byte = int(self.vram[attr_addr])
            shift = (((tile_y // 2) % 2) * 4) + (((tile_x // 2) % 2) * 2)
            palette_index = (attr_byte >> shift) & 0x03

            if palette_empty and not self._debug_force_palette:
                pal_idx = int(self.palette_ram[0]) & 0x3F
            else:
                if pix == 0:
                    pal_idx = int(self.palette_ram[0]) & 0x3F
                else:
                    pal_idx = int(self.palette_ram[palette_index * 4 + pix]) & 0x3F
            
            self.scanline_bg[x] = pix
            self.frame_buffer[line, x] = self.nes_palette[pal_idx]

    cpdef public void sprite_evaluate(self):
        cdef int oam_idx, y, start, j
        cdef int height = 16 if (self.ctrl & 0x20) else 8
        cdef int found = 0
        cdef bint overflow = False
        
        self.sprite_count = 0
        self.sprite0_hit = 0
        self.sprite0_in_scanline = -1
        
        for oam_idx in range(0, 256, 4):
            y = int(self.oam_data[oam_idx]) + 1
            if self.scanline >= y and self.scanline < y + height:
                if found < 8:
                    start = found * 4
                    for j in range(4):
                        self.scanline_oam[start + j] = self.oam_data[oam_idx + j]
                    if oam_idx == 0:
                        self.sprite0_in_scanline = found
                    found += 1
                else:
                    overflow = True
        self.sprite_count = found
        if overflow:
            self.status |= 0x20

    cpdef public void sprite_render(self):
        if self.chr_rom is None:
            return
            
        cdef int height = 16 if (self.ctrl & 0x20) else 8
        cdef int sprite_table_base = 0x1000 if (self.ctrl & 0x08) else 0x0000
        cdef int i, base, y, tile_index, attr, x, palette_index
        cdef bint flip_x, flip_y, priority_front
        cdef int scanline_y, tile_row, tile_offset, bank, base_index
        cdef uint8_t low, high, bit0, bit1
        cdef int col, sx, pix, bg_pix, pal_idx
        
        for i in range(self.sprite_count - 1, -1, -1):
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
                
            if height == 8:
                tile_row = scanline_y
                if flip_y: tile_row = 7 - scanline_y
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
                if flip_y: tile_row = 7 - tile_row

            if tile_offset + 8 >= len(self.chr_rom):
                continue
                
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
                    
                bg_pix = int(self.scanline_bg[sx])
                
                if self.sprite0_in_scanline == i and bg_pix != 0:
                    self.sprite0_hit = 1
                    
                if priority_front or bg_pix == 0:
                    pal_idx = int(self.palette_ram[palette_index * 4 + pix]) & 0x3F
                    self.frame_buffer[self.scanline, sx] = self.nes_palette[pal_idx]

    cpdef public void perform_dma(self, uint8_t[:] page):
        cdef int i
        for i in range(256):
            self.oam_data[self.oam_addr] = page[i]
            self.oam_addr += 1