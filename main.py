from nes import NES
import sys

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python main.py <path_to_rom>")
        sys.exit(1)
    
    rom_path = sys.argv[1]
    nes = NES(rom_path)
    while True:
        nes.run_frame()