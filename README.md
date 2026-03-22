# NES Emulator (Bachelor's Thesis) 🎮

A high-performance **Nintendo Entertainment System (NES)** emulator written in **Python** and optimized with **Cython**. This project explores the boundaries of hardware emulation performance within the Python ecosystem.

## 🚀 Project Overview

This project is my Bachelor's Thesis at **Palacký University Olomouc**. The core challenge is to emulate the intricate timing and hardware interactions of the NES while overcoming the performance limitations of interpreted Python.

By using **Cython**, performance-critical components (instruction decoding, memory mapping, and PPU rendering) are in C-extensions. This bridges the gap between Python's high-level flexibility and C's execution speed.

## 🛠️ Tech Stack

* **Core:** Python 3.10+
* **Optimization:** Cython (C-Extensions)
* **Graphics & Input:** Pygame
* **Data:** NumPy
* **Version Control:** Git

## 📺 Media & Demonstration

### Current Rendering State
Below is a demonstration of the current PPU background rendering capabilities.

![NES Emulator Gameplay Preview](example.gif)

*Caption: Current state of the PPU rendering engine (Background tiles and Nametables).*

## ⚙️ Hardware Implementation Progress

### CPU (Ricoh 2A03)
* [x] Full 6502 instruction set (official opcodes).
* [x] Accurate cycle-by-cycle timing logic.
* [x] Interrupt handling (NMI, IRQ, RESET).

### PPU (Picture Processing Unit)
* [x] Sprite rendering (OAM).
* [x] Scrolling logic and fine X/Y offsets.
* [ ] Background rendering (tiles and nametables).

### APU & Mappers
* [ ] Pulse, Triangle, and Noise channels.
* [x] iNES (.nes) file format support.
* [ ] Common Mappers (MMC1, MMC3).

## 📈 Performance & Current Status

The project is under active development. The primary bottleneck remains the main execution loop and PPU synchronization.

## 🗺️ Roadmap (Future Optimizations)

* **Solve visual bugs:** Most of background tiles are displayed with wrong colors, on-screen text issues.
* **Boundary Optimization:** Minimize Python-to-C overhead by keeping the main execution loop entirely within compiled code.
* **60 FPS Target:** Reach a stable 60 FPS.
* **Sound Support:** Implement the APU.

## 🔧 Installation & Setup

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

# Optional Qt launcher (ROM picker + recent games)
``` bash
python qt_launcher.py
```

## 👨‍💻 Author

**Adil Abuzyarov** Computer Science Student at Palacký University Olomouc  
[LinkedIn](https://www.linkedin.com/in/adil-abuzyarov-a55210273/) | [GitHub](https://github.com/adiomhts)
