# NES Emulator (Bachelor's Thesis)

A high-performance **Nintendo Entertainment System (NES)** emulator written in **Python** and optimized with **Cython**. This project explores the boundaries of hardware emulation performance within the Python ecosystem.

## Project Overview

This project is my Bachelor's Thesis at **Palacký University Olomouc**. The core challenge is to emulate the intricate timing and hardware interactions of the NES while overcoming the performance limitations of interpreted Python.

By using **Cython**, performance-critical components (instruction decoding, memory mapping, and PPU rendering) are in C-extensions. This bridges the gap between Python's high-level flexibility and C's execution speed.

## Tech Stack

* **Core:** Python 3.10+
* **Optimization:** Cython (C-Extensions)
* **Graphics & Input:** Pygame
* **Data:** NumPy
* **Version Control:** Git

## Media & Demonstration

### Current Rendering State
Below is a demonstration of the current gameplay rendering capabilities.

![NES Emulator Gameplay Preview](example.gif)

## Hardware Implementation Progress

### CPU (Ricoh 2A03)
* [x] Full 6502 instruction set (official opcodes).
* [x] Accurate cycle-by-cycle timing logic.
* [x] Interrupt handling (NMI, IRQ, RESET).

### PPU (Picture Processing Unit)
* [x] Sprite rendering (OAM).
* [x] Scrolling logic and fine X/Y offsets.
* [x] Background rendering (tiles and nametables).

### APU (Audio Processing Unit)
* [x] Pulse 1 & 2 channels.
* [x] Triangle channel.
* [x] Noise channel.
* [x] DMC (Delta Modulation Channel).

### Cartridge & Mappers
* [x] iNES (.nes) file format support.
* [x] Mapper 0 (NROM)
* [x] Mapper 1 (MMC1)
* [x] Mapper 2 (UxROM)
* [x] Mapper 3 (CNROM)
* [-] Mapper 4 (MMC3)

## 📈 Performance & Cython Optimization Strategy

To achieve playable framerates, this emulator leverages **Cython** extensively:
- **C-Level Types & Memory Arrays:** Emulated memory (RAM, VRAM, palettes) uses typed memoryviews, bypassing Python object overhead.
- **Virtual Method Tables (VTable):** Device polymorphism (e.g., Mapper routing) is implemented via `cdef public` classes. This ensures million-times-a-second hardware polling completely bypasses Python's dynamic dispatch.
- **Compiler Directives:** Built with `-O3` and `-flto` while avoiding runtime boundary checks (`boundscheck=False`, `wraparound=False`).

## Roadmap & Current Focus

* **CPU Instruction Fixes:** Debugging edge cases in specific 6502 instructions (e.g., branch delays, indexed addressing) to achieve 100% pass rates on `nes-test-roms`.
* **Cycle-Accurate Interrupt Timing:** Aligning IRQ and NMI timing precisely between the PPU, CPU, and MMC3.
* **Audio Synchronization:** Smoothing out audio buffer delivery to Pygame/SDL to prevent audio crackling.

## Installation & Setup

### Prerequisites
* Python 3.10+
* A C compiler (GCC, Clang, or MSVC) for building C-extensions.

### Build Instructions

# Clone the repository
``` bash
git clone https://github.com/adiomhts/Cython-NES-emulator.git
cd Cython-NES-emulator
```

# Install required packages
``` bash
pip install -r requirements.txt
```

# Compile Cython modules into C-extensions
This will generate .so or .pyd files depending on your OS
``` bash
python setup.py build_ext --inplace
```

# Run the emulator with a ROM file
``` bash
python main.py rom.nes
```

# Optional Qt launcher (ROM picker/input settings)
``` bash
python qt_launcher.py
```

## Author

**Adil Abuzyarov** Computer Science Student at Palacký University Olomouc  
