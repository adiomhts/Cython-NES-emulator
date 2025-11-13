import pygame
import numpy as np
from cpu import CPU6502
from ppu import PPU
from apu import APU
from controller import Controller
from cartridge import Cartridge


class NES:
    def __init__(self, rom_path):
        pygame.init()
        self.screen = pygame.display.set_mode((256, 240))
        pygame.display.set_caption("NES Emulator")
        
        self.cpu = CPU6502()
        self.ppu = PPU(mirroring=0)
        # Allow PPU to trigger CPU interrupts (NMI)
        try:
            self.ppu.cpu = self.cpu
        except Exception:
            pass
        self.apu = APU()
        self.controller = Controller()
        self.cartridge = Cartridge(rom_path)
        # Give PPU access to CHR ROM for scanline rendering
        try:
            self.ppu.chr_rom = self.cartridge.chr_rom
        except Exception:
            self.ppu.chr_rom = None
        self.cpu.set_peripherals(self.ppu, self.apu, self.controller)
        self.cpu.set_cartridge(self.cartridge)
        self.frame_time = 1.0 / 60.0
        self.load_rom()

    def load_rom(self):
        # Загружает PRG-ROM и CHR-ROM в память в зависимости от маппера
        prg_size = len(self.cartridge.prg_rom)

        if self.cartridge.mapper == 0:  # NROM (Mapper 0)
            # Если PRG-ROM <= 16 KB, дублируем его во вторую половину
            if prg_size <= 0x4000:
                self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom
                self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom
            else:
                self.cpu.memory[0x8000:0x10000] = self.cartridge.prg_rom

        elif self.cartridge.mapper == 1:  # MMC1 (Mapper 1)
            # MMC1 поддерживает переключение банков, загружаем первый банк по умолчанию
            self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom[:0x4000]
            self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom[-0x4000:]  # Последний банк фиксирован

        elif self.cartridge.mapper == 2:  # UNROM (Mapper 2)
            # Последний банк фиксирован (0xC000-0x10000)
            self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom[-0x4000:]
            # Первый банк загружается динамически (по умолчанию - первый)
            self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom[:0x4000]

        elif self.cartridge.mapper == 3:  # CNROM (Mapper 3)
            # Работает как NROM, но с переключаемыми CHR банками
            if prg_size <= 0x4000:
                self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom
                self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom
            else:
                self.cpu.memory[0x8000:0x10000] = self.cartridge.prg_rom

        elif self.cartridge.mapper == 4:  # MMC3 (Mapper 4)
            # MMC3 имеет сложное управление PRG банками, загружаем последние 2 банка по умолчанию
            self.cpu.memory[0x8000:0xA000] = self.cartridge.prg_rom[:0x2000]
            self.cpu.memory[0xA000:0xC000] = self.cartridge.prg_rom[-0x4000:-0x2000]
            self.cpu.memory[0xC000:0xE000] = self.cartridge.prg_rom[-0x2000:]
            self.cpu.memory[0xE000:0x10000] = self.cartridge.prg_rom[-0x4000:]  # Фиксированный последний банк

        else:
            raise ValueError(f"Unsupported mapper: {self.cartridge.mapper}")

        self.cpu.reset()

    def render_screen(self):
        # PPU.frame_buffer is (240,256,3) (height,width,channels) — pygame wants (width,height,3)
        surface = pygame.surfarray.make_surface(self.ppu.frame_buffer.swapaxes(0, 1))
        self.screen.blit(surface, (0, 0))
        pygame.display.flip()

    def run_frame(self):
        for _ in range(29780):  # Один кадр NES занимает ~29780 тактов
            self.cpu.step()
            # NES PPU runs at 3x the CPU clock: run 3 PPU cycles per CPU cycle
            for _ in range(3):
                self.ppu.step()
            # Update APU with the CPU cycles that have passed
            self.apu.step(self.cpu.cycles)
        # Frame is rendered incrementally during ppu.step(); just blit the current buffer
        self.render_screen()