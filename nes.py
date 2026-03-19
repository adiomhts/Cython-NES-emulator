import pygame
import os
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
        self.rom_path = rom_path
        
        mirroring_mode = self.cartridge.mirroring

        self.cpu = CPU6502()
        self.ppu = PPU(mirroring=mirroring_mode)
        try:
            self.ppu.cpu = self.cpu
        except Exception:
            pass
        try:
            self.ppu.cartridge = self.cartridge
        except Exception:
            pass
        self.apu = APU()
        try:
            self.apu.cpu = self.cpu
        except Exception:
            pass
        self.controller = Controller()
        self.controller2 = Controller()
        try:
            self.ppu.chr_rom = self.cartridge.chr_rom
        except Exception:
            self.ppu.chr_rom = None
        self.cpu.set_peripherals(self.ppu, self.apu, self.controller, self.controller2)
        self.cpu.set_cartridge(self.cartridge)
        self.load_rom()
        self._load_battery_ram()

    def _save_path(self):
        """Build persistent save path for the loaded ROM.

        Args:
            None.

        Returns:
            str: Path to `.sav` file located next to the ROM.
        """
        base, _ = os.path.splitext(self.rom_path)
        return base + ".sav"

    def _load_battery_ram(self):
        """Load battery-backed PRG RAM from disk into `$6000-$7FFF`.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Reads save data from `.sav` file and writes it to CPU RAM window.
        """
        if not getattr(self.cartridge, 'battery_backed', 0):
            return

        save_path = self._save_path()
        if not os.path.exists(save_path):
            return

        with open(save_path, 'rb') as f:
            raw = f.read(0x2000)

        if raw:
            mapper_ram = None
            try:
                mapper_ram = getattr(self.cartridge.mapper_instance, 'prg_ram', None)
            except Exception:
                mapper_ram = None

            if mapper_ram is not None:
                mapper_ram[:len(raw)] = list(raw)
            else:
                self.cpu.memory[0x6000:0x6000 + len(raw)] = list(raw)

    def save_battery_ram(self):
        """Persist battery-backed PRG RAM from `$6000-$7FFF` to disk.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Writes 8KB PRG RAM snapshot to `.sav` file for battery carts.
        """
        if not getattr(self.cartridge, 'battery_backed', 0):
            return

        save_path = self._save_path()
        mapper_ram = None
        try:
            mapper_ram = getattr(self.cartridge.mapper_instance, 'prg_ram', None)
        except Exception:
            mapper_ram = None

        if mapper_ram is not None:
            payload = bytes(mapper_ram[:0x2000])
        else:
            payload = bytes(self.cpu.memory[0x6000:0x8000])

        with open(save_path, 'wb') as f:
            f.write(payload)

    def shutdown(self):
        """Finalize emulator state before application exit.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Saves battery-backed RAM if cartridge supports persistence.
        """
        self.save_battery_ram()

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
