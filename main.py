import pygame
import sys
from nes import NES

# Glossary (terms used in comments/docstrings in this file):
# - CLI: Command-Line Interface (launching emulator with arguments).
# - OS: Operating System event queue handled by pygame.
# - ROM: Read-Only Memory image of a game cartridge (`.nes` file format).
# - FPS: Frames Per Second; host-side render/update frequency metric.
# - NTSC: TV timing standard used by original NES frame cadence.
# - SDL: Simple DirectMedia Layer backend used under pygame.
# NESdev references:
# - https://www.nesdev.org/wiki/Nesdev_Wiki
# - https://www.nesdev.org/wiki/NTSC_video

"""CLI entrypoint for launching the NES emulator with a ROM path.

This module parses command-line arguments, creates the emulator instance,
translates host keyboard input to NES controller buttons, and drives the
frame loop at approximately 60 FPS.

NESdev references:
- https://www.nesdev.org/wiki/Nesdev_Wiki
- https://www.nesdev.org/wiki/Controller_reading
- https://www.nesdev.org/wiki/NTSC_video
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

KEY_MAP_P2 = {
    'A': pygame.K_u,
    'B': pygame.K_o,
    'SELECT': pygame.K_RCTRL,
    'START': pygame.K_RALT,
    'UP': pygame.K_i,
    'DOWN': pygame.K_k,
    'LEFT': pygame.K_j,
    'RIGHT': pygame.K_l
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

    NESdev references:
        https://www.nesdev.org/wiki/Controller_reading
        https://www.nesdev.org/wiki/Cycle_reference_chart
    """
    # CLI contract: the first argument after script name is expected to be
    # a valid path to a `.nes` ROM image.
    if len(sys.argv) < 2:
        print("Usage: python main.py <path_to_rom>")
        sys.exit(1)

    # Instantiate and fully wire the emulator state from the selected ROM.
    rom_path = sys.argv[1]
    nes = NES(rom_path)
    
    # Host-side frame limiter used to keep real-time pacing close to NTSC.
    clock = pygame.time.Clock()
    running = True

    print("Emulator started. P1: Arrows=Move, Z=A, X=B, Enter=Start, RShift=Select")
    print("P2: I/J/K/L=Move, U=A, O=B, RAlt=Start, RCtrl=Select")

    try:
        # Main host loop: process events, sample input, run one emulated frame,
        # and present timing diagnostics in the window title.
        while running:
            # Pump OS/window events to keep the app responsive.
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    # ESC is a quick exit shortcut.
                    if event.key == pygame.K_ESCAPE:
                        running = False

            # Snapshot all host key states once per frame.
            keys = pygame.key.get_pressed()

            # Convert host keyboard state into NES controller bit layout:
            # A, B, SELECT, START, UP, DOWN, LEFT, RIGHT.
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

            # Same mapping for player 2 (second virtual controller).
            input_state_p2 = [
                keys[KEY_MAP_P2['A']],
                keys[KEY_MAP_P2['B']],
                keys[KEY_MAP_P2['SELECT']],
                keys[KEY_MAP_P2['START']],
                keys[KEY_MAP_P2['UP']],
                keys[KEY_MAP_P2['DOWN']],
                keys[KEY_MAP_P2['LEFT']],
                keys[KEY_MAP_P2['RIGHT']]
            ]

            # Push sampled input into controller shift-register front buffers.
            if hasattr(nes, 'controller') and nes.controller:
                nes.controller.update(input_state)
            if hasattr(nes, 'controller2') and nes.controller2:
                nes.controller2.update(input_state_p2)

            # Emulate one full video frame worth of CPU/PPU/APU activity.
            nes.run_frame()

            # Keep host execution near 60 updates per second.
            clock.tick(60)

            # Show measured host FPS for quick timing diagnostics.
            pygame.display.set_caption(f"NES Emulator - {clock.get_fps():.2f} FPS")
    finally:
        # Ensure save-related shutdown handlers always run.
        if hasattr(nes, 'shutdown'):
            nes.shutdown()
        # Release SDL/pygame resources even on exceptions.
        pygame.quit()


if __name__ == "__main__":
    main()
