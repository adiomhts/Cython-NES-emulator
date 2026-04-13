# Glossary (plain-language terms for this PPU section):
# - Mirroring map: Rule that maps logical nametables onto 2KB VRAM.
# - Physical VRAM index: Actual byte index in local `vram` array.
# - CHR source: Cartridge-backed CHR or fallback local CHR storage.
# - Palette mirror: Special mirroring inside '$3F00-$3FFF' palette area.
# NESdev references:
# - https://www.nesdev.org/wiki/Mirroring
# - https://www.nesdev.org/wiki/PPU_memory_map

# IDE Static Analysis Hints
if not "PPU" in globals():
    from ppu cimport PPU
    from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef int ppu_get_vram_mirror(PPU self, int addr):
    cdef int pal_addr, clean_addr, table, offset, bank

    # PPU internal address bus wraps at 14 bits.
    addr = addr & 0x3FFF

    if addr >= 0x3F00:
        # Palette RAM is 32 bytes with mirrored universal background entries.
        pal_addr = addr & 0x1F
        if pal_addr >= 0x10 and (pal_addr & 3) == 0:
            # Hardware mirrors sprite backdrop entries onto bg backdrop slots.
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
            if table == 0 or table == 1:
                bank = 0
            else:
                bank = 1
        elif self.mirroring == 1:
            # Vertical mirroring: NT0/NT2 share, NT1/NT3 share.
            if table == 0 or table == 2:
                bank = 0
            else:
                bank = 1

        # Return physical index into local 2KB VRAM buffer.
        return bank * 0x400 + offset
    return 0


cdef inline bint ppu_has_chr_source(PPU self):
    return self.cartridge is not None or self.chr_rom is not None


cdef inline uint8_t ppu_read_chr(PPU self, uint16_t addr):
    if self.cartridge is not None:
        try:
            return self.cartridge.mapper_instance.read_chr(addr)
        except Exception:
            pass
    if self.chr_rom is not None and addr < len(self.chr_rom):
        return self.chr_rom[addr]
    return 0


cdef inline void ppu_write_chr(PPU self, uint16_t addr, uint8_t value):
    if self.cartridge is not None:
        try:
            self.cartridge.mapper_instance.write_chr(addr, value)
            return
        except Exception:
            pass
    if self.chr_rom is not None and addr < len(self.chr_rom):
        self.chr_rom[addr] = value
