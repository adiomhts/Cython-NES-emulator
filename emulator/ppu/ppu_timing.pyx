# Glossary (plain-language terms for this PPU section):
# - Scanline: One horizontal row of pixels/timing events.
# - Dot/Cycle: One PPU timing step within a scanline.
# - VBlank NMI: Interrupt sent to CPU at frame blank period start.
# - Odd-frame skip: One-cycle skip on pre-render line for NTSC timing.
# NESdev references:
# - https://www.nesdev.org/wiki/PPU_frame_timing
# - https://www.nesdev.org/wiki/NMI

cdef void ppu_step_core(PPU self):
    cdef bint rendering_enabled
    cdef int i, pal_idx_line

    self.cycle += 1
    rendering_enabled = (self.mask & 0x18) != 0

    if self.cycle == 1:
        self.snap_fine_x = self.fine_x
        if 0 <= self.scanline < 240:
            if rendering_enabled and (self.mask & 0x08):
                self.render_scanline(self.scanline)
            else:
                pal_idx_line = self.palette_ram[0] & 0x3F
                for i in range(256):
                    self.frame_buffer[self.scanline, i, 0] = self.nes_palette[pal_idx_line, 0]
                    self.frame_buffer[self.scanline, i, 1] = self.nes_palette[pal_idx_line, 1]
                    self.frame_buffer[self.scanline, i, 2] = self.nes_palette[pal_idx_line, 2]
                for i in range(256):
                    self.scanline_bg[i] = 0

            if (self.mask & 0x18) == 0x18:
                self.sprite0_hit_x = self._find_sprite0_hit_x(self.scanline)
            else:
                self.sprite0_hit_x = -1

    if rendering_enabled and not self.sprite0_hit and self.sprite0_hit_x >= 0:
        if self.cycle == self.sprite0_hit_x + 2:
            self.sprite0_hit = 1
            self.status |= 0x40

    if self.scanline == 261 and self.cycle == 339 and rendering_enabled and self.odd_frame:
        self.cycle = 0
        self.scanline = 0
        self.odd_frame = False
        return

    if self.cycle >= 341:
        self.cycle = 0
        self.scanline += 1

        if self.scanline == 241:
            self.trigger_vblank()
        elif self.scanline == 261:
            self.vblank_flag = 0
            self.status &= ~0xE0
            self.sprite0_hit = 0
        elif self.scanline >= 262:
            self.scanline = 0
            self.odd_frame = not self.odd_frame

    if self.scanline == 261 and rendering_enabled:
        if self.cycle == 256:
            self.increment_scroll_y()
        if self.cycle == 257:
            self.copy_x()
        if self.cycle >= 280 and self.cycle <= 304:
            self.copy_y()

    if 0 <= self.scanline < 240:
        if self.cycle == 256:
            if rendering_enabled:
                self.increment_scroll_y()

        if self.cycle == 257:
            if rendering_enabled:
                self.copy_x()
                self.sprite_evaluate()
                self.sprite_render()


cpdef void ppu_step(PPU self):
    """Advance PPU by one internal timing tick.

    Args:
        self: Active PPU instance.

    Returns:
        None.

    Side Effects:
        Advances scanline/cycle counters, can trigger rendering work,
        sprite evaluation, vblank status updates, and optional NMI.

    NESdev references:
        https://www.nesdev.org/wiki/PPU_frame_timing
        https://www.nesdev.org/wiki/PPU_rendering
    """
    self._step_core()


cpdef void ppu_step_many(PPU self, int steps):
    """Advance PPU by multiple timing ticks.

    Args:
        self: Active PPU instance.
        steps: Number of internal timing ticks to execute.

    Returns:
        None.

    Side Effects:
        Same effects as repeating `ppu_step` in a loop; used by CPU-to-PPU
        stepping paths that need to process many ticks quickly.

    NESdev reference:
        https://www.nesdev.org/wiki/PPU_frame_timing
    """
    cdef int i
    for i in range(steps):
        self._step_core()


cpdef void ppu_trigger_vblank(PPU self):
    """Set vblank status and optionally trigger CPU NMI.

    Args:
        self: Active PPU instance.

    Returns:
        None.

    Side Effects:
        Sets `vblank_flag`, sets `PPUSTATUS` vblank bit, and if `PPUCTRL`
        NMI-enable bit is set, requests an NMI on the attached CPU.

    NESdev references:
        https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS
        https://www.nesdev.org/wiki/NMI
    """
    self.vblank_flag = 1
    self.status |= 0x80
    try:
        if getattr(self, 'cpu', None) is not None and (self.ctrl & 0x80):
            self.cpu.trigger_interrupt(0)
    except Exception:
        pass
