# Cython-NES-emulator

## Project Description

This project is a high-performance **Nintendo Entertainment System (NES)** emulator developed as a bachelor's thesis.

The key feature is the use of the **Cython** language to implement performance-critical components, such as the Central Processing Unit (CPU) and Picture Processing Unit (PPU). Cython allows writing code that is syntactically close to Python but compiles it into efficient native C/C++ code, which is essential for accurate and fast emulation of the console's timings.

The goal of the project is to create a functional emulator capable of running commercial NES games.

## Features

The emulator implements the main hardware components of the NES console:

* **Central Processing Unit (CPU):** Emulation of the 8-bit Ricoh 2A03 processor, based on the 6502 architecture.
* **Picture Processing Unit (PPU):** Full implementation of the PPU (`ppu.pyx`), including sprite handling, background rendering, VRAM, and NMI interrupt generation for frame synchronization.
* **Memory and Mappers:** Implementation of the NES memory subsystem (RAM, PRG-ROM, CHR-ROM). Supports common memory mapping schemes (bank controllers) for compatibility with various game ROMs. Mappers 0, 1, 2, 3, and 4 (NROM, MMC1, UNROM, CNROM, MMC3) are included (`mappers.pyx`, `nes.py`).
* **Input:** Handles controller input (`controller.pyx`) and maps it to the virtual NES gamepad using Pygame.
* **Optimization:** The CPU and PPU cores are implemented in Cython to achieve near C-level performance. The main emulation loop is synchronized to 60 frames per second (FPS).

## Technologies Used

* **Cython:** The core language for high-performance modules (`cpu.pyx`, `ppu.pyx`, `mappers.pyx`).
* **Python:** Used for the main logic, ROM loading, and component interaction (`nes.py`, `main.py`). (TODO: rewrite components interaction in Cython for better performance.)
* **Pygame:** Used for window management, graphics output, user input processing, and timing control (60 FPS).
* **NumPy:** Utilized for efficient creation and management of large memory buffers (e.g., for the PPU frame buffer) and arrays, which is optimized by Cython.

## Installation

Follow these steps to set up the project and its dependencies:

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/adiomhts/cython-nes-emulator.git](https://github.com/adiomhts/cython-nes-emulator.git)
    cd cython-nes-emulator
    ```

2.  **Install Python dependencies:**
    You need to install Cython, NumPy, and Pygame:
    ```bash
    pip install cython numpy pygame
    ```

3.  **Compile Cython modules:**
    Use the `setup.py` script to compile the `.pyx` files into native Python extension modules (`.pyd` or `.so`):
    ```bash
    python setup.py build_ext --inplace
    ```

## Usage

An NES ROM file (`.nes`) is required to run the emulator:

```bash
python main.py <path_to_rom>
# Example:
# python main.py games/super_mario_bros.nes
```

## Project Status

The project is currently a work in progress, in line with its purpose as a student project. The provided code is a functional implementation of the emulator core with an emphasis on performance.
