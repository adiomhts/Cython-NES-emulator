import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t
from mappers cimport MapperBase

cdef class PPU:
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
    cdef public MapperBase mapper_instance

    cdef inline void increment_v(self)
    cdef inline void increment_scroll_y(self)
    cdef inline void increment_scroll_x(self)
    cdef inline void increment_v_2007(self)
    cdef inline void copy_x(self)
    cdef inline void copy_y(self)
    cdef inline int get_vram_mirror(self, int addr)
    cdef inline bint _has_chr_source(self)
    cdef inline uint8_t _read_chr(self, uint16_t addr)
    cdef inline void _write_chr(self, uint16_t addr, uint8_t value)
    cdef inline void _step_core(self)
    cpdef public void step(self)
    cpdef public void step_many(self, int steps)
    cpdef public void trigger_vblank(self)
    cpdef public void write_register(self, uint16_t reg, uint8_t value)
    cpdef public uint8_t read_register(self, uint16_t reg)
    cpdef public void render_scanline(self, int line)
    cdef int _find_sprite0_hit_x(self, int line)
    cpdef public void sprite_evaluate(self)
    cpdef public void sprite_render(self)
    cpdef public void perform_dma(self, uint8_t [:] page)
