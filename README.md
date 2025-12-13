# Cython-Optimized NES Emulator

A work-in-progress project of emulator for the Nintendo Entertainment System (NES) developed primarily in Python and optimized using Cython for performance-critical components.

## Project Goal

The primary goal of this project is to understand and implement low-level computer architecture, specifically the components of the 8-bit NES console, while focusing on performance optimization techniques.

## Implemented Components

* **CPU (6502):** Implemented core instruction set and addressing modes.
* **PPU (Picture Processing Unit):** Logic for background rendering and sprite handling.
* **Cartridge Loading:** Support for iNES file format and initial Mapper implementation (responsible for memory management).

## Why Cython?

Cython was utilized to **bridge the performance gap** inherent in Python for computationally intensive tasks like CPU and PPU cycle emulation. By converting Python code to C extensions, Cython allows for native speed execution of the emulator's core loop, making it a viable solution for real-time emulation.

## Technologies Used

* **Core Logic:** Cython, Python
* **Graphics:** Pygame (for display and input)
* **Build System:** `setup.py` for compiling Cython modules
