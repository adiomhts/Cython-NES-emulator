import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t

# Glossary (terms used in comments/docstrings in this file):
# - PPU: Picture Processing Unit.
# - VRAM: Video RAM for nametables/attributes in PPU address space.
# - OAM: Object Attribute Memory (sprite list storage).
# - CHR: Pattern table tile/sprite graphics source.
# - NT: Nametable (background tile map page; NT0..NT3 shorthand in comments).
# - Pattern table: 8x8 tile bitplane data region at '$0000-$1FFF'.
# - Attribute table: Per-32x32-pixel palette selectors inside each nametable.
# - VBlank: Vertical blanking interval; frame period where NMI may fire.
# - Fine/coarse scroll: Pixel/tile components of PPU scroll registers.
# - Sprite 0 hit: Status flag when sprite #0 overlaps non-zero background pixel.
# - Universal backdrop: Palette entry used when no bg/sprite pixel is selected.
# - Mirroring mode: Cartridge wiring that maps 4 logical nametables onto 2 RAM pages.
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

    def __init__(self, mirroring=0):
        """Initialize PPU state and memory arrays.

        Args:
            mirroring: Nametable mirroring mode ('0=horizontal', '1=vertical').

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

    cdef inline void increment_v(self):
        ppu_increment_v(self)

    cdef inline void increment_scroll_y(self):
        ppu_increment_scroll_y(self)

    cdef inline void increment_scroll_x(self):
        ppu_increment_scroll_x(self)

    cdef inline void increment_v_2007(self):
        ppu_increment_v_2007(self)

    cdef inline void copy_x(self):
        ppu_copy_x(self)

    cdef inline void copy_y(self):
        ppu_copy_y(self)

    cdef inline int get_vram_mirror(self, int addr):
        return ppu_get_vram_mirror(self, addr)

    cdef inline bint _has_chr_source(self):
        return ppu_has_chr_source(self)

    cdef inline uint8_t _read_chr(self, uint16_t addr):
        return ppu_read_chr(self, addr)

    cdef inline void _write_chr(self, uint16_t addr, uint8_t value):
        ppu_write_chr(self, addr, value)

    cdef inline void _step_core(self):
        ppu_step_core(self)

    cpdef public void step(self):
        ppu_step(self)

    cpdef public void step_many(self, int steps):
        ppu_step_many(self, steps)

    cpdef public void trigger_vblank(self):
        ppu_trigger_vblank(self)

    cpdef public void write_register(self, uint16_t reg, uint8_t value):
        ppu_write_register(self, reg, value)

    cpdef public uint8_t read_register(self, uint16_t reg):
        return ppu_read_register(self, reg)

    cpdef public void render_scanline(self, int line):
        ppu_render_scanline(self, line)

    cdef int _find_sprite0_hit_x(self, int line):
        return ppu_find_sprite0_hit_x(self, line)

    cpdef public void sprite_evaluate(self):
        ppu_sprite_evaluate(self)

    cpdef public void sprite_render(self):
        ppu_sprite_render(self)

    cpdef public void perform_dma(self, uint8_t[:] page):
        ppu_perform_dma(self, page)

include "ppu_scroll.pyx"
include "ppu_memory.pyx"
include "ppu_timing.pyx"
include "ppu_registers.pyx"
include "ppu_rendering.pyx"