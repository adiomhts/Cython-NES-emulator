import pygame
import sys
from nes import NES
from controls_config import BUTTON_ORDER, DEFAULT_CONTROL_NAMES, load_control_names

# Glossary (terms used in comments/docstrings in this file):
# - CLI: Command-Line Interface (launching emulator with arguments).
# - OS: Operating System event queue handled by pygame.
# - ROM: Read-Only Memory image of a game cartridge ('.nes' file format).
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

KEY_MAP = {}
KEY_MAP_P2 = {}


def _resolve_key_code(key_name, fallback_name):
    try:
        return pygame.key.key_code(key_name)
    except Exception:
        return pygame.key.key_code(fallback_name)


def _apply_control_config():
    global KEY_MAP, KEY_MAP_P2
    names = load_control_names()

    KEY_MAP = {
        btn: _resolve_key_code(names["P1"][btn], DEFAULT_CONTROL_NAMES["P1"][btn])
        for btn in BUTTON_ORDER
    }
    KEY_MAP_P2 = {
        btn: _resolve_key_code(names["P2"][btn], DEFAULT_CONTROL_NAMES["P2"][btn])
        for btn in BUTTON_ORDER
    }

TOP_BAR_HEIGHT = 36
BG_COLOR = (18, 18, 22)
TOP_BAR_COLOR = (36, 36, 44)
BUTTON_COLOR = (72, 72, 90)
BUTTON_HOVER_COLOR = (96, 96, 120)
TEXT_COLOR = (235, 235, 245)


def _format_key_name(key_code):
    return pygame.key.name(key_code).upper()


def _build_controls_lines():
    p1 = (
        f"P1: A={_format_key_name(KEY_MAP['A'])}, B={_format_key_name(KEY_MAP['B'])}, "
        f"SELECT={_format_key_name(KEY_MAP['SELECT'])}, START={_format_key_name(KEY_MAP['START'])}, "
        f"UP={_format_key_name(KEY_MAP['UP'])}, DOWN={_format_key_name(KEY_MAP['DOWN'])}, "
        f"LEFT={_format_key_name(KEY_MAP['LEFT'])}, RIGHT={_format_key_name(KEY_MAP['RIGHT'])}"
    )
    p2 = (
        f"P2: A={_format_key_name(KEY_MAP_P2['A'])}, B={_format_key_name(KEY_MAP_P2['B'])}, "
        f"SELECT={_format_key_name(KEY_MAP_P2['SELECT'])}, START={_format_key_name(KEY_MAP_P2['START'])}, "
        f"UP={_format_key_name(KEY_MAP_P2['UP'])}, DOWN={_format_key_name(KEY_MAP_P2['DOWN'])}, "
        f"LEFT={_format_key_name(KEY_MAP_P2['LEFT'])}, RIGHT={_format_key_name(KEY_MAP_P2['RIGHT'])}"
    )
    return [p1, p2, "Hotkeys: F11=Fullscreen, F10=Original Size, ESC=Exit"]


def _make_buttons(font, window_width):
    labels = ["Controls", "Fullscreen", "Original Size"]
    padding = 10
    x = 8
    y = 6
    buttons = []
    for label in labels:
        text_w, _ = font.size(label)
        width = max(120, text_w + 18)
        rect = pygame.Rect(x, y, width, TOP_BAR_HEIGHT - 12)
        if rect.right > window_width - 8:
            break
        buttons.append((label, rect))
        x += width + padding
    return buttons


def _compute_game_rect(window_size):
    win_w, win_h = window_size
    avail_h = max(1, win_h - TOP_BAR_HEIGHT)

    scale = min(win_w / 256.0, avail_h / 240.0)
    scale = max(scale, 0.1)

    game_w = max(1, int(256 * scale))
    game_h = max(1, int(240 * scale))
    x = (win_w - game_w) // 2
    y = TOP_BAR_HEIGHT + (avail_h - game_h) // 2
    return pygame.Rect(x, y, game_w, game_h)


def _toggle_fullscreen(current_size, fullscreen):
    if fullscreen:
        return pygame.display.set_mode(current_size, pygame.RESIZABLE), False
    return pygame.display.set_mode((0, 0), pygame.FULLSCREEN), True


def _set_original_window_size():
    return pygame.display.set_mode((256, 240 + TOP_BAR_HEIGHT), pygame.RESIZABLE)


def _draw_top_bar(screen, buttons, font, mouse_pos):
    screen_rect = screen.get_rect()
    top_rect = pygame.Rect(0, 0, screen_rect.width, TOP_BAR_HEIGHT)
    pygame.draw.rect(screen, TOP_BAR_COLOR, top_rect)

    for label, rect in buttons:
        hover = rect.collidepoint(mouse_pos)
        color = BUTTON_HOVER_COLOR if hover else BUTTON_COLOR
        pygame.draw.rect(screen, color, rect, border_radius=6)
        pygame.draw.rect(screen, (25, 25, 32), rect, width=1, border_radius=6)
        text_surface = font.render(label, True, TEXT_COLOR)
        text_pos = text_surface.get_rect(center=rect.center)
        screen.blit(text_surface, text_pos)


def _draw_controls_overlay(screen, lines, font, title_font):
    win_rect = screen.get_rect()
    panel_w = min(win_rect.width - 30, 940)
    panel_h = 132
    panel = pygame.Rect((win_rect.width - panel_w) // 2, TOP_BAR_HEIGHT + 16, panel_w, panel_h)

    overlay = pygame.Surface((panel.width, panel.height), pygame.SRCALPHA)
    overlay.fill((12, 12, 16, 228))
    screen.blit(overlay, panel.topleft)
    pygame.draw.rect(screen, (120, 120, 145), panel, width=1, border_radius=6)

    title = title_font.render("Controls", True, TEXT_COLOR)
    screen.blit(title, (panel.x + 10, panel.y + 8))

    y = panel.y + 38
    for line in lines:
        text_surface = font.render(line, True, TEXT_COLOR)
        screen.blit(text_surface, (panel.x + 10, y))
        y += 26

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
    # a valid path to a '.nes' ROM image.
    if len(sys.argv) < 2:
        print("Usage: python main.py <path_to_rom>")
        sys.exit(1)

    # Apply control mapping from launcher settings file before game loop starts.
    _apply_control_config()

    # Instantiate and fully wire the emulator state from the selected ROM.
    rom_path = sys.argv[1]
    nes = NES(rom_path)

    # Replace fixed window with resizable window and keep NES screen reference synced.
    windowed_size = (768, 600)
    nes.screen = pygame.display.set_mode(windowed_size, pygame.RESIZABLE)
    fullscreen = False
    show_controls = False
    mouse_pos = (0, 0)

    font = pygame.font.SysFont(None, 22)
    title_font = pygame.font.SysFont(None, 26)
    controls_lines = _build_controls_lines()
    
    # Host-side frame limiter used to keep real-time pacing close to NTSC.
    clock = pygame.time.Clock()
    running = True

    print("Emulator started. P1: Arrows=Move, Z=A, X=B, Enter=Start, RShift=Select")
    print("P2: I/J/K/L=Move, U=A, O=B, RAlt=Start, RCtrl=Select")

    try:
        # Main host loop: process events, sample input, run one emulated frame,
        # and present timing diagnostics in the window title.
        while running:
            buttons = _make_buttons(font, nes.screen.get_width())
            # Pump OS/window events to keep the app responsive.
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.VIDEORESIZE and not fullscreen:
                    windowed_size = (max(320, event.w), max(240 + TOP_BAR_HEIGHT, event.h))
                    nes.screen = pygame.display.set_mode(windowed_size, pygame.RESIZABLE)
                elif event.type == pygame.MOUSEMOTION:
                    mouse_pos = event.pos
                elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    for label, rect in buttons:
                        if rect.collidepoint(event.pos):
                            if label == "Controls":
                                show_controls = not show_controls
                            elif label == "Fullscreen":
                                if not fullscreen:
                                    windowed_size = nes.screen.get_size()
                                nes.screen, fullscreen = _toggle_fullscreen(windowed_size, fullscreen)
                            elif label == "Original Size":
                                fullscreen = False
                                nes.screen = _set_original_window_size()
                                windowed_size = nes.screen.get_size()
                            break
                elif event.type == pygame.KEYDOWN:
                    # ESC is a quick exit shortcut.
                    if event.key == pygame.K_ESCAPE:
                        running = False
                    elif event.key == pygame.K_F11:
                        if not fullscreen:
                            windowed_size = nes.screen.get_size()
                        nes.screen, fullscreen = _toggle_fullscreen(windowed_size, fullscreen)
                    elif event.key == pygame.K_F10:
                        fullscreen = False
                        nes.screen = _set_original_window_size()
                        windowed_size = nes.screen.get_size()

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
            nes.run_frame(present=False)

            # Draw game frame with aspect-ratio preserving scaling into available area.
            nes.screen.fill(BG_COLOR)
            game_rect = _compute_game_rect(nes.screen.get_size())
            nes.render_screen(target_surface=nes.screen, dest_rect=game_rect, flip=False)

            # Draw settings top bar and optional controls panel.
            _draw_top_bar(nes.screen, buttons, font, mouse_pos)
            if show_controls:
                _draw_controls_overlay(nes.screen, controls_lines, font, title_font)

            pygame.display.flip()

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
