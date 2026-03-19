import pygame
import sys
from nes import NES

"""CLI entrypoint for launching the NES emulator with a ROM path.

This module parses command-line arguments, creates the emulator instance,
translates host keyboard input to NES controller buttons, and drives the
frame loop at approximately 60 FPS.
"""

KEY_MAP = {
    'A': pygame.K_z,
    'B': pygame.K_x,
    'SELECT': pygame.K_RSHIFT,
    'START': pygame.K_RETURN,
    'UP': pygame.K_UP,
    'DOWN': pygame.K_DOWN,
    'LEFT': pygame.K_LEFT,
    'RIGHT': pygame.K_RIGHT
}

def main():
    """Run the interactive emulator loop.

    Args:
        None.

    Returns:
        None.

    Side Effects:
        Initializes and uses pygame subsystems, creates a window, reads user
        input events, updates window caption with measured FPS, and advances
        emulation until quit.

    Raises:
        SystemExit: If ROM path argument is not provided.
    """
    if len(sys.argv) < 2:
        print("Usage: python main.py <path_to_rom>")
        sys.exit(1)

    rom_path = sys.argv[1]
    nes = NES(rom_path)
    
    clock = pygame.time.Clock()
    running = True

    print("Emulator started. Controls: Arrows=Move, Z=A, X=B, Enter=Start, RShift=Select")

    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False

        keys = pygame.key.get_pressed()
        
        input_state = [
            keys[KEY_MAP['A']],
            keys[KEY_MAP['B']],
            keys[KEY_MAP['SELECT']],
            keys[KEY_MAP['START']],
            keys[KEY_MAP['UP']],
            keys[KEY_MAP['DOWN']],
            keys[KEY_MAP['LEFT']],
            keys[KEY_MAP['RIGHT']]
        ]
        
        if hasattr(nes, 'controller') and nes.controller:
            nes.controller.update(input_state)

        nes.run_frame()
        
        clock.tick(60)
        
        pygame.display.set_caption(f"NES Emulator - {clock.get_fps():.2f} FPS")

    pygame.quit()


if __name__ == "__main__":
    main()
