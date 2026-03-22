# Glossary

This document defines common terms used throughout the Cython NES Emulator codebase, intended for developers who may not be familiar with NES architecture or emulation concepts.

## General Concepts

*   **Emulator**: A program that enables a host computer to behave like another system (in this case, a Nintendo Entertainment System). It reproduces the hardware's behavior in software.
*   **ROM (Read-Only Memory)**: A file containing a copy of the game's data, originally stored on a cartridge. The emulator loads this file to run the game.
*   **Mapper**: A hardware chip on a game cartridge that extends the capabilities of the NES. Mappers allow for games larger than the base NES memory limits by swapping banks of ROM data in and out of the CPU's address space.

## CPU (Central Processing Unit)

*   **CPU**: The "brain" of the console (a Ricoh 2A03, based on the MOS 6502). It executes game logic, performs calculations, and orchestrates the other components.
*   **Instruction Handler**: A function in the code that implements the behavior of a single CPU instruction (e.g., `ADC`, `LDA`).
*   **Register**: A small, high-speed storage location within the CPU. The most important are `A` (Accumulator), `X` and `Y` (Index Registers), `PC` (Program Counter), and `SP` (Stack Pointer).
*   **Stack**: A region of memory used for temporary storage. It's a "Last-In, First-Out" (LIFO) structure, primarily used for saving return addresses when calling subroutines or handling interrupts.
*   **Interrupt**: A signal to the CPU that temporarily halts normal code execution to handle a special event, such as a request from the PPU (NMI) or an external device.
*   **Branch**: An instruction that conditionally changes the flow of code execution by jumping to a nearby address, based on the status of CPU flags.
*   **Bitwise Operation**: An operation that manipulates numbers directly at the level of their individual bits (e.g., AND, OR, XOR).

## PPU (Picture Processing Unit)

*   **PPU**: The graphics chip responsible for everything seen on screen. It renders the background and sprites.
*   **Scanline**: A single horizontal line of pixels on the television screen. The PPU renders the screen one scanline at a time.
*   **Nametable**: A 1KB area of VRAM that acts as a tilemap, defining the layout of the background. It stores an index for which tile to draw in each 8x8 pixel position on the screen.
*   **Attribute Table**: A small table in VRAM that specifies which 4-color palette should be used for each 16x16 pixel area of the background.
*   **Pattern Table**: An area of ROM or RAM containing the actual graphical data for tiles (both background and sprites).
*   **Tile**: A single 8x8 pixel graphical element. The background and all sprites are constructed from tiles.
*   **Bitplane**: A binary layer of tile graphics. A tile's color information is stored in two bitplanes; combining them produces a 2-bit color index (0-3) for each pixel.
*   **Sprite**: A movable graphical object, independent of the background (e.g., the player character, enemies, projectiles).
*   **OAM (Object Attribute Memory)**: A small (256-byte) area of RAM inside the PPU that stores the properties of all 64 sprites, including their Y/X coordinates, tile index, and attributes (palette, priority, flip).
*   **Secondary OAM**: A temporary buffer within the PPU that holds the data for the (up to) 8 sprites that are visible on the *current* scanline.
*   **Sprite Overflow**: A hardware limitation where only the first 8 sprites found on a given scanline can be rendered. A flag is set in a PPU register when this occurs.
*   **Sprite 0 Hit**: A specific hardware event that occurs when the first non-transparent pixel of the first sprite (Sprite 0) overlaps the first non-transparent pixel of the background on a scanline. It is often used by games to time screen effects.
*   **Priority**: A sprite attribute that determines whether it is drawn in front of or behind the background layer.

