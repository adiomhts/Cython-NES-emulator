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
        
        self.cartridge = Cartridge(rom_path)  # Сначала грузим картридж!
        
        # Читаем зеркалирование из картриджа (бит 0 флага 6)
        # 0 = Horizontal, 1 = Vertical
        mirroring_mode = self.cartridge.mirroring
        
        self.cpu = CPU6502()
        self.ppu = PPU(mirroring=mirroring_mode) # Передаем зеркалирование
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
        frame_cycles = 0
        # 29780 - приблизительное количество тактов CPU в одном кадре NTSC
        while frame_cycles < 29780:
            # 1. Запоминаем текущее количество тактов CPU
            cycles_before = self.cpu.cycles
            
            # 2. Выполняем ОДНУ инструкцию
            self.cpu.step()
            
            # 3. Считаем, сколько тактов она заняла на самом деле
            cycles_diff = self.cpu.cycles - cycles_before
            
            # 4. "Догоняем" PPU: он должен сделать в 3 раза больше шагов
            ppu_steps = cycles_diff * 3
            for _ in range(ppu_steps):
                self.ppu.step()
            
            # 5. APU работает на частоте CPU (синхронно по тактам)
            # (Исправляем ошибку, где передавалось self.cpu.cycles - общее время)
            self.apu.step(cycles_diff)
            
            frame_cycles += cycles_diff
            
        self.render_screen()