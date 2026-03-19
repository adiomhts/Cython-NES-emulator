import pygame
from cpu import CPU6502
from ppu import PPU
from apu import APU
from controller import Controller
from cartridge import Cartridge


class NES:
    """Top-level NES system wiring for CPU, PPU, APU, controller, and cartridge.

    This class owns all major emulator subsystems and coordinates timing
    between them on a frame boundary.
    """

    def __init__(self, rom_path):
        """Initialize emulator subsystems and load the selected ROM.

        Args:
            rom_path: Path to a `.nes` ROM file.

        Returns:
            None.

        Side Effects:
            Initializes pygame, creates an output window, loads cartridge data,
            wires CPU/PPU/APU/controller references, maps CHR data into PPU
            context, and resets CPU state through `load_rom`.

        Raises:
            ValueError: If cartridge parser rejects the ROM format.
            OSError: If ROM file cannot be read.
        """
        pygame.init()
        self.screen = pygame.display.set_mode((256, 240))
        pygame.display.set_caption("NES Emulator")
        
        self.cartridge = Cartridge(rom_path) 
        
        mirroring_mode = self.cartridge.mirroring

        self.cpu = CPU6502()
        self.ppu = PPU(mirroring=mirroring_mode)
        try:
            self.ppu.cpu = self.cpu
        except Exception:
            pass
        self.apu = APU()
        try:
            self.apu.cpu = self.cpu
        except Exception:
            pass
        self.controller = Controller()
        try:
            self.ppu.chr_rom = self.cartridge.chr_rom
        except Exception:
            self.ppu.chr_rom = None
        self.cpu.set_peripherals(self.ppu, self.apu, self.controller)
        self.cpu.set_cartridge(self.cartridge)
        self.load_rom()

    def load_rom(self):
        """Map cartridge PRG data into CPU memory according to mapper id.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Writes into CPU memory region `$8000-$FFFF` and calls `CPU.reset()`.

        Raises:
            ValueError: If mapper id is not implemented.
        """
        prg_size = len(self.cartridge.prg_rom)

        if self.cartridge.mapper == 0:
            if prg_size <= 0x4000:
                self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom
                self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom
            else:
                self.cpu.memory[0x8000:0x10000] = self.cartridge.prg_rom

        elif self.cartridge.mapper == 1:
            self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom[:0x4000]
            self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom[-0x4000:]

        elif self.cartridge.mapper == 2:
            self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom[-0x4000:]
            self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom[:0x4000]

        elif self.cartridge.mapper == 3:
            if prg_size <= 0x4000:
                self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom
                self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom
            else:
                self.cpu.memory[0x8000:0x10000] = self.cartridge.prg_rom

        elif self.cartridge.mapper == 4:
            self.cpu.memory[0x8000:0xA000] = self.cartridge.prg_rom[:0x2000]
            self.cpu.memory[0xA000:0xC000] = self.cartridge.prg_rom[-0x4000:-0x2000]
            self.cpu.memory[0xC000:0xE000] = self.cartridge.prg_rom[-0x2000:]
            self.cpu.memory[0xE000:0x10000] = self.cartridge.prg_rom[-0x4000:]

        else:
            raise ValueError(f"Unsupported mapper: {self.cartridge.mapper}")

        self.cpu.reset()

    def render_screen(self):
        """Present current PPU framebuffer to the host window.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Blits a pygame surface and flips the display buffer.
        """
        surface = pygame.surfarray.make_surface(self.ppu.frame_buffer.swapaxes(0, 1))
        self.screen.blit(surface, (0, 0))
        pygame.display.flip()

    def run_frame(self):
        """Run one emulated NTSC frame.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Advances CPU instruction stream, steps PPU at 3x CPU cycle rate,
            advances APU by consumed CPU cycles, and renders the resulting frame.
        """
        frame_cycles = 0
        while frame_cycles < 29780:
            cycles_before = self.cpu.cycles
            
            self.cpu.step()
            
            cycles_diff = self.cpu.cycles - cycles_before
            
            ppu_steps = cycles_diff * 3
            self.ppu.step_many(ppu_steps)
            
            self.apu.step(cycles_diff)
            
            frame_cycles += cycles_diff
            
        self.render_screen()
