import os
from cpu import CPU6502
from ppu import PPU
from apu import APU
from controller import Controller
from cartridge import Cartridge

# Glossary (terms used in comments/docstrings in this file):
# - CPU: Central Processing Unit (Ricoh 2A03, 6502-like core in NES).
# - PPU: Picture Processing Unit (video generator and VRAM controller).
# - APU: Audio Processing Unit (sound channels + frame sequencer).
# - PRG: Program ROM/RAM mapped into CPU cartridge space.
# - CHR: Character/Pattern data used by PPU tile/sprite fetches.
# - Mapper: Cartridge logic for bank switching and IRQ features.
# - NMI/IRQ: Non-maskable / maskable CPU interrupt lines.
# - RGB: Red/Green/Blue color triplet format used in framebuffer arrays.
# NESdev references:
# - https://www.nesdev.org/wiki/CPU
# - https://www.nesdev.org/wiki/PPU
# - https://www.nesdev.org/wiki/APU
# - https://www.nesdev.org/wiki/Mapper


class NES:
    """Top-level NES system wiring for CPU, PPU, APU, controller, and cartridge.

    This class owns all major emulator subsystems and coordinates timing
    between them on a frame boundary.

    NESdev references:
    - https://www.nesdev.org/wiki
    - https://www.nesdev.org/wiki/CPU
    - https://www.nesdev.org/wiki/PPU
    - https://www.nesdev.org/wiki/APU
    """

    def __init__(self, rom_path):
        """Initialize emulator subsystems and load the selected ROM.

        Args:
            rom_path: Path to a '.nes' ROM file.

        Returns:
            None.

        Side Effects:
            Loads cartridge data, wires CPU/PPU/APU/controller references,
            maps CHR data into PPU context, and resets CPU state through 'load_rom'.

        Raises:
            ValueError: If cartridge parser rejects the ROM format.
            OSError: If ROM file cannot be read.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_memory_map
            https://www.nesdev.org/wiki/Mirroring
            https://www.nesdev.org/wiki/PPU_registers
        """
        # Parse ROM, iNES header, mapper info, and PRG/CHR payloads.
        self.cartridge = Cartridge(rom_path) 
        self.rom_path = rom_path
        
        # Nametable mirroring mode is determined by cartridge header / mapper.
        mirroring_mode = self.cartridge.mirroring

        # Create main hardware blocks.
        self.cpu = CPU6502()
        self.ppu = PPU(mirroring=mirroring_mode)
        # Bind CPU into PPU context so PPU can raise NMI/IRQ-style events.
        self.ppu.cpu = self.cpu
        # Give PPU direct cartridge view for CHR reads where needed.
        self.ppu.cartridge = self.cartridge
        # Create audio unit and connect it to CPU timing domain.
        self.apu = APU()
        self.apu.cpu = self.cpu
        # Two standard gamepads.
        self.controller = Controller()
        self.controller2 = Controller()
        # Expose CHR ROM/RAM to PPU pattern-table fetch path.
        self.ppu.chr_rom = self.cartridge.chr_rom
        # Wire CPU memory-mapped devices and cartridge mapper backend.
        self.cpu.set_peripherals(self.ppu, self.apu, self.controller, self.controller2)
        self.cpu.set_cartridge(self.cartridge)
        # Initialize CPU memory view for initial mapper state.
        self.load_rom()
        # Load persistent PRG RAM if cartridge has battery-backed save support.
        self._load_battery_ram()

    def _save_path(self):
        """Build persistent save path for the loaded ROM.

        Args:
            None.

        Returns:
            str: Path to '.sav' file located next to the ROM.

        NESdev reference:
            https://www.nesdev.org/wiki/INES#Flags_6
        """
        # Save file is colocated with ROM and uses '.sav' extension.
        base, _ = os.path.splitext(self.rom_path)
        return base + ".sav"

    def _load_battery_ram(self):
        """Load battery-backed PRG RAM from disk into '$6000-$7FFF'.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Reads save data from '.sav' file and writes it to CPU RAM window.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_memory_map
            https://www.nesdev.org/wiki/INES#Flags_6
        """
        # Skip if cartridge does not advertise battery-backed persistent RAM.
        if not getattr(self.cartridge, 'battery_backed', 0):
            return

        save_path = self._save_path()
        # No existing save file means clean power-on PRG RAM contents.
        if not os.path.exists(save_path):
            return

        # PRG RAM battery window size is 8KB in this emulator path.
        with open(save_path, 'rb') as f:
            raw = f.read(0x2000)

        if raw:
            mapper_ram = None
            try:
                mapper_ram = getattr(self.cartridge.mapper_instance, 'prg_ram', None)
            except Exception:
                mapper_ram = None

            # Prefer mapper-owned PRG RAM buffer when mapper exposes one.
            if mapper_ram is not None:
                mapper_ram[:len(raw)] = bytearray(raw)
            else:
                # Fallback path writes directly into CPU $6000-$7FFF shadow.
                self.cpu.memory[0x6000:0x6000 + len(raw)] = bytearray(raw)

    def save_battery_ram(self):
        """Persist battery-backed PRG RAM from '$6000-$7FFF' to disk.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Writes 8KB PRG RAM snapshot to '.sav' file for battery carts.

        NESdev references:
            https://www.nesdev.org/wiki/INES#Flags_6
            https://www.nesdev.org/wiki/CPU_memory_map
        """
        # Do nothing for cartridges without battery-backed memory.
        if not getattr(self.cartridge, 'battery_backed', 0):
            return

        save_path = self._save_path()
        mapper_ram = None
        try:
            mapper_ram = getattr(self.cartridge.mapper_instance, 'prg_ram', None)
        except Exception:
            mapper_ram = None

        # Mapper RAM takes priority over generic CPU RAM fallback window.
        if mapper_ram is not None:
            payload = bytes(mapper_ram[:0x2000])
        else:
            payload = bytes(self.cpu.memory[0x6000:0x8000])

        # Persist in one write so save file stays coherent.
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

        NESdev reference:
            https://www.nesdev.org/wiki/INES#Flags_6
        """
        # Current shutdown step is save flush; place future teardown hooks here.
        self.save_battery_ram()

    def load_rom(self):
        """Map cartridge PRG data into CPU memory according to mapper id.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Writes into CPU memory region '$8000-$FFFF' and calls 'CPU.reset()'.

        Raises:
            ValueError: If mapper id is not implemented.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_memory_map
            https://www.nesdev.org/wiki/Mapper
        """
        # Number of PRG bytes determines mirroring/banking decisions.
        prg_size = len(self.cartridge.prg_rom)

        if self.cartridge.mapper == 0:
            # NROM-128 (16KB): mirror bank into both $8000 and $C000 windows.
            if prg_size <= 0x4000:
                self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom
                self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom
            else:
                # NROM-256 (32KB): map full PRG linearly at $8000-$FFFF.
                self.cpu.memory[0x8000:0x10000] = self.cartridge.prg_rom

        elif self.cartridge.mapper == 1:
            # MMC1-style boot mapping: first bank at $8000, last bank fixed at $C000.
            self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom[:0x4000]
            self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom[-0x4000:]

        elif self.cartridge.mapper == 2:
            # UxROM-style: fixed upper bank and switchable lower bank (initially bank 0).
            self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom[-0x4000:]
            self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom[:0x4000]

        elif self.cartridge.mapper == 3:
            # CNROM has CHR switching; PRG mapping is typically NROM-like.
            if prg_size <= 0x4000:
                self.cpu.memory[0x8000:0xC000] = self.cartridge.prg_rom
                self.cpu.memory[0xC000:0x10000] = self.cartridge.prg_rom
            else:
                self.cpu.memory[0x8000:0x10000] = self.cartridge.prg_rom

        elif self.cartridge.mapper == 4:
            # Placeholder MMC3 startup mapping by 8KB banks.
            # Keeps layout valid even for minimal PRG sizes and avoids
            # broadcasting errors when ROM has fewer than 4 x 8KB banks.
            if prg_size < 0x2000 or (prg_size % 0x2000) != 0:
                raise ValueError(f"Invalid PRG size for mapper 4: {prg_size}")

            prg_banks = [
                self.cartridge.prg_rom[i:i + 0x2000]
                for i in range(0, prg_size, 0x2000)
            ]

            bank0 = prg_banks[0]
            bank1 = prg_banks[1] if len(prg_banks) > 1 else prg_banks[0]
            bank2 = prg_banks[-2] if len(prg_banks) > 1 else prg_banks[0]
            bank3 = prg_banks[-1]

            self.cpu.memory[0x8000:0xA000] = bank0
            self.cpu.memory[0xA000:0xC000] = bank1
            self.cpu.memory[0xC000:0xE000] = bank2
            self.cpu.memory[0xE000:0x10000] = bank3

        else:
            raise ValueError(f"Unsupported mapper: {self.cartridge.mapper}")

        # Reset vectors/program counter are reloaded after mapping is ready.
        self.cpu.reset()

    def run_frame(self):
        """Run one emulated NTSC frame.

        Args:
            None.

        Returns:
            numpy.ndarray: The rendered frame buffer (240, 256, 3).

        Side Effects:
            Advances CPU instruction stream, steps PPU at 3x CPU cycle rate,
            advances APU by consumed CPU cycles, and renders the resulting frame.

        NESdev references:
            https://www.nesdev.org/wiki/Cycle_reference_chart
            https://www.nesdev.org/wiki/PPU_frame_timing
            https://www.nesdev.org/wiki/APU
        """
        # Approximate CPU cycles per NTSC frame for pacing in this emulator.
        frame_cycles = 0
        # Continue stepping until the frame cycle budget is consumed.
        while frame_cycles < 29780:
            # Capture cycle counter before running the next CPU instruction.
            cycles_before = self.cpu.cycles
            
            # Execute one CPU instruction.
            self.cpu.step()
            
            # Determine exact cycle cost of that instruction.
            cycles_diff = self.cpu.cycles - cycles_before
            
            # PPU runs 3x the CPU clock, so convert CPU cycles to PPU ticks.
            ppu_steps = cycles_diff * 3
            self.ppu.step_many(ppu_steps)
            
            # APU timing is tracked in CPU cycle domain.
            self.apu.step(cycles_diff)
            
            # Accumulate frame progress in CPU cycles.
            frame_cycles += cycles_diff
            
        return self.ppu.frame_buffer
