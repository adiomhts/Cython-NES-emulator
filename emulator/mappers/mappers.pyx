from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as cnp

# Glossary (terms used in comments/docstrings in this file):
# - Mapper: Cartridge logic controlling PRG/CHR mapping and optional IRQs.
# - PRG/CHR bank: Switchable ROM/RAM window in CPU/PPU cartridge space.
# - MMC1/MMC3: Nintendo mapper ASIC families (Mapper 1 / Mapper 4 behavior).
# - A12: PPU address line used by MMC3 IRQ edge detector.
# - IRQ latch/counter: MMC3 scanline-ish interrupt timing mechanism.
# - Cartridge board: Physical PCB inside game cartridge that contains ROM and mapper chip.
# - Bank switching: Technique that swaps visible memory windows so small CPU can access large ROM.
# - Fixed bank: ROM region that stays mapped to one address window all the time.
# - Switchable bank: ROM region selected dynamically by writes to mapper registers.
# - Mirroring mode: How background nametable memory is electrically connected/wrapped.
# - PRG RAM: Writable cartridge memory for saves or runtime variables.
# - CHR RAM: Writable graphics memory used when cartridge has no CHR ROM.
# - Edge detector: Logic that triggers action when signal changes from low to high.
# - Open bus behavior: Hardware quirk where some reads return stale/undefined values.
# - Slot/window: Address range currently exposing one selected bank of a larger ROM.
# NESdev references:
# - https://www.nesdev.org/wiki/Mapper
# - https://www.nesdev.org/wiki/MMC1
# - https://www.nesdev.org/wiki/MMC3

cdef class MapperBase:
    """Base class defining common mapper structure and memory buffers."""

    cpdef public void clock_irq(self):
        pass

include "mapper0.pyx"
include "mapper1.pyx"
include "mapper2.pyx"
include "mapper3.pyx"
include "mapper4.pyx"
