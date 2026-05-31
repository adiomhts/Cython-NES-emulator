import pygame
import sys
from emulator.nes import NES
from controls_config import BUTTON_ORDER, DEFAULT_CONTROL_NAMES, load_control_names

# Glossary:
# - ROM: Read-Only Memory image of a game cartridge ('.nes' file format).
# - FPS: Frames Per Second; host-side render/update frequency metric.
# - NTSC: TV timing standard used by original NES frame cadence.
# - SDL: Simple DirectMedia Layer backend used under pygame.

"""CLI entrypoint for launching the NES emulator with a ROM path.

This module parses command-line arguments, creates the emulator instance,
translates host keyboard input to NES controller buttons, and drives the
frame loop at approximately 60 FPS.

NESdev references:
- https://www.nesdev.org/wiki
- https://www.nesdev.org/wiki/Controller_reading
- https://www.nesdev.org/wiki/NTSC_video
"""

TOP_BAR_HEIGHT = 36
BG_COLOR = (18, 18, 22)
TOP_BAR_COLOR = (36, 36, 44)
BUTTON_COLOR = (72, 72, 90)
BUTTON_HOVER_COLOR = (96, 96, 120)
TEXT_COLOR = (235, 235, 245)


def _resolve_key_code(key_name, fallback_name):
    """Resolve a pygame key string into its integer constant.

    Args:
        key_name: Primary string name of the key (e.g. 'return').
        fallback_name: Fallback string name if primary is invalid.

    Returns:
        int: The resolved pygame key code.
    """
    try:
        return pygame.key.key_code(key_name)
    except Exception:
        return pygame.key.key_code(fallback_name)


def get_control_config():
    """Load control mappings from JSON and resolve them to PyGame key codes.

    Args:
        None.

    Returns:
        tuple: (key_map, key_map_p2) dictionaries mapping NES buttons to host key codes.

    Side Effects:
        Reads '.cython_nes_controls.json' from disk.
    """
    names = load_control_names()
    key_map = {
        btn: _resolve_key_code(names["P1"][btn], DEFAULT_CONTROL_NAMES["P1"][btn])
        for btn in BUTTON_ORDER
    }
    key_map_p2 = {
        btn: _resolve_key_code(names["P2"][btn], DEFAULT_CONTROL_NAMES["P2"][btn])
        for btn in BUTTON_ORDER
    }
    return key_map, key_map_p2


def _format_key_name(key_code):
    """Convert pygame key code to a human-readable uppercase string.

    Args:
        key_code: Pygame key integer.

    Returns:
        str: Uppercase key name (e.g. 'ESCAPE').
    """
    return pygame.key.name(key_code).upper()


def _build_controls_lines(key_map, key_map_p2):
    """Format the mapped controls into human-readable text lines for the UI.

    Args:
        key_map: Dictionary mapping P1 buttons to key codes.
        key_map_p2: Dictionary mapping P2 buttons to key codes.

    Returns:
        list: A list of strings representing the control mappings.
    """
    p1 = (
        f"P1: A={_format_key_name(key_map['A'])}, B={_format_key_name(key_map['B'])}, "
        f"SELECT={_format_key_name(key_map['SELECT'])}, START={_format_key_name(key_map['START'])}, "
        f"UP={_format_key_name(key_map['UP'])}, DOWN={_format_key_name(key_map['DOWN'])}, "
        f"LEFT={_format_key_name(key_map['LEFT'])}, RIGHT={_format_key_name(key_map['RIGHT'])}"
    )
    p2 = (
        f"P2: A={_format_key_name(key_map_p2['A'])}, B={_format_key_name(key_map_p2['B'])}, "
        f"SELECT={_format_key_name(key_map_p2['SELECT'])}, START={_format_key_name(key_map_p2['START'])}, "
        f"UP={_format_key_name(key_map_p2['UP'])}, DOWN={_format_key_name(key_map_p2['DOWN'])}, "
        f"LEFT={_format_key_name(key_map_p2['LEFT'])}, RIGHT={_format_key_name(key_map_p2['RIGHT'])}"
    )
    return [p1, p2, "Hotkeys: F11=Fullscreen, F10=Original Size, ESC=Exit"]


def _make_buttons(font, window_width):
    """Create UI button rectangles for the top bar.

    Args:
        font: Pygame font used to render button labels.
        window_width: Current width of the application window.

    Returns:
        list: A list of tuples (label_str, pygame.Rect) representing the UI buttons.
    """
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
    """Calculate the aspect-ratio-preserving bounds for rendering the NES screen.

    Args:
        window_size: Tuple (width, height) of the current host window.

    Returns:
        pygame.Rect: The destination rectangle for the NES video frame.
    """
    win_w, win_h = window_size
    avail_h = max(1, win_h - TOP_BAR_HEIGHT)

    scale = min(win_w / 256.0, avail_h / 240.0)
    scale = max(scale, 0.1)

    game_w = max(1, int(256 * scale))
    game_h = max(1, int(240 * scale))
    x = (win_w - game_w) // 2
    y = TOP_BAR_HEIGHT + (avail_h - game_h) // 2
    return pygame.Rect(x, y, game_w, game_h)


class EmulatorApp:
    """Frontend application managing the window, inputs, and the NES core.

    This class encapsulates PyGame dependencies, decoupling the NES hardware
    emulation from the host OS graphics and event loop.
    """

    def __init__(self, rom_path):
        """Initialize the PyGame window and the NES emulator core.

        Args:
            rom_path: Path to the .nes file to load.

        Returns:
            None.

        Side Effects:
            Initializes PyGame subsystems, creates the display window,
            loads controller configuration, and boots the NES instance.
        """
        pygame.init()
        self.windowed_size = (768, 600)
        self.screen = pygame.display.set_mode(self.windowed_size, pygame.RESIZABLE)
        pygame.display.set_caption("NES Emulator")
        
        self.nes = NES(rom_path)
        self.key_map, self.key_map_p2 = get_control_config()
        self.fullscreen = False
        self.show_controls = False
        self.mouse_pos = (0, 0)
        self.font = pygame.font.SysFont(None, 22)
        self.title_font = pygame.font.SysFont(None, 26)
        self.controls_lines = _build_controls_lines(self.key_map, self.key_map_p2)

    def _toggle_fullscreen(self):
        """Toggle the window between fullscreen and windowed modes.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Recreates the PyGame display surface.
        """
        if self.fullscreen:
            self.screen = pygame.display.set_mode(self.windowed_size, pygame.RESIZABLE)
            self.fullscreen = False
        else:
            self.screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
            self.fullscreen = True

    def _set_original_window_size(self):
        """Restore the window to a base 1x scale representation.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Recreates the PyGame display surface.
        """
        self.fullscreen = False
        self.screen = pygame.display.set_mode((256, 240 + TOP_BAR_HEIGHT), pygame.RESIZABLE)
        self.windowed_size = self.screen.get_size()

    def _draw_top_bar(self, buttons):
        """Render the top configuration menu bar.

        Args:
            buttons: List of pre-calculated (label, rect) tuples.

        Returns:
            None.

        Side Effects:
            Mutates pixels on the PyGame display surface.
        """
        screen_rect = self.screen.get_rect()
        top_rect = pygame.Rect(0, 0, screen_rect.width, TOP_BAR_HEIGHT)
        pygame.draw.rect(self.screen, TOP_BAR_COLOR, top_rect)

        for label, rect in buttons:
            hover = rect.collidepoint(self.mouse_pos)
            color = BUTTON_HOVER_COLOR if hover else BUTTON_COLOR
            pygame.draw.rect(self.screen, color, rect, border_radius=6)
            pygame.draw.rect(self.screen, (25, 25, 32), rect, width=1, border_radius=6)
            text_surface = self.font.render(label, True, TEXT_COLOR)
            text_pos = text_surface.get_rect(center=rect.center)
            self.screen.blit(text_surface, text_pos)

    def _draw_controls_overlay(self):
        """Render the semi-transparent controls help overlay.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Mutates pixels on the PyGame display surface.
        """
        win_rect = self.screen.get_rect()
        panel_w = min(win_rect.width - 30, 940)
        panel_h = 132
        panel = pygame.Rect((win_rect.width - panel_w) // 2, TOP_BAR_HEIGHT + 16, panel_w, panel_h)

        overlay = pygame.Surface((panel.width, panel.height), pygame.SRCALPHA)
        overlay.fill((12, 12, 16, 228))
        self.screen.blit(overlay, panel.topleft)
        pygame.draw.rect(self.screen, (120, 120, 145), panel, width=1, border_radius=6)

        title = self.title_font.render("Controls", True, TEXT_COLOR)
        self.screen.blit(title, (panel.x + 10, panel.y + 8))

        y = panel.y + 38
        for line in self.controls_lines:
            text_surface = self.font.render(line, True, TEXT_COLOR)
            self.screen.blit(text_surface, (panel.x + 10, y))
            y += 26

    def render_game_frame(self, frame_buffer):
        """Scale and blit the raw NES frame buffer to the host screen.

        Args:
            frame_buffer: numpy.ndarray of shape (240, 256, 3) containing RGB pixels.

        Returns:
            None.

        Side Effects:
            Mutates pixels on the PyGame display surface.

        NESdev references:
            https://www.nesdev.org/wiki/PPU_rendering
        """
        surface = pygame.surfarray.make_surface(frame_buffer.swapaxes(0, 1))
        game_rect = _compute_game_rect(self.screen.get_size())
        scaled = pygame.transform.smoothscale(surface, (game_rect.width, game_rect.height))
        self.screen.blit(scaled, game_rect.topleft)

    def process_input(self):
        """Sample host keyboard state and forward it to NES controller instances.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Updates the internal shift-register states of the connected NES controllers.

        NESdev references:
            https://www.nesdev.org/wiki/Controller_reading
        """
        keys = pygame.key.get_pressed()
        input_state = [
            keys[self.key_map['A']], keys[self.key_map['B']],
            keys[self.key_map['SELECT']], keys[self.key_map['START']],
            keys[self.key_map['UP']], keys[self.key_map['DOWN']],
            keys[self.key_map['LEFT']], keys[self.key_map['RIGHT']]
        ]
        input_state_p2 = [
            keys[self.key_map_p2['A']], keys[self.key_map_p2['B']],
            keys[self.key_map_p2['SELECT']], keys[self.key_map_p2['START']],
            keys[self.key_map_p2['UP']], keys[self.key_map_p2['DOWN']],
            keys[self.key_map_p2['LEFT']], keys[self.key_map_p2['RIGHT']]
        ]
        if hasattr(self.nes, 'controller') and self.nes.controller:
            self.nes.controller.update(input_state)
        if hasattr(self.nes, 'controller2') and self.nes.controller2:
            self.nes.controller2.update(input_state_p2)

    def run(self):
        """Enter the blocking application loop: events -> emulate -> render.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Pumps OS message queue, advances emulator timing, and updates the display
            continuously until the user requests to quit.

        NESdev references:
            https://www.nesdev.org/wiki/Cycle_reference_chart
        """
        clock = pygame.time.Clock()
        running = True

        print("Emulator started. P1: Arrows=Move, Z=A, X=B, Enter=Start, RShift=Select")
        print("P2: I/J/K/L=Move, U=A, O=B, RAlt=Start, RCtrl=Select")

        try:
            while running:
                buttons = _make_buttons(self.font, self.screen.get_width())
                
                for event in pygame.event.get():
                    if event.type == pygame.QUIT:
                        running = False
                    elif event.type == pygame.VIDEORESIZE and not self.fullscreen:
                        self.windowed_size = (max(320, event.w), max(240 + TOP_BAR_HEIGHT, event.h))
                        self.screen = pygame.display.set_mode(self.windowed_size, pygame.RESIZABLE)
                    elif event.type == pygame.MOUSEMOTION:
                        self.mouse_pos = event.pos
                    elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                        for label, rect in buttons:
                            if rect.collidepoint(event.pos):
                                if label == "Controls":
                                    self.show_controls = not self.show_controls
                                elif label == "Fullscreen":
                                    if not self.fullscreen:
                                        self.windowed_size = self.screen.get_size()
                                    self._toggle_fullscreen()
                                elif label == "Original Size":
                                    self._set_original_window_size()
                                break
                    elif event.type == pygame.KEYDOWN:
                        if event.key == pygame.K_ESCAPE:
                            running = False
                        elif event.key == pygame.K_F11:
                            if not self.fullscreen:
                                self.windowed_size = self.screen.get_size()
                            self._toggle_fullscreen()
                        elif event.key == pygame.K_F10:
                            self._set_original_window_size()

                self.process_input()
                frame_buffer = self.nes.run_frame()

                self.screen.fill(BG_COLOR)
                if frame_buffer is not None:
                    self.render_game_frame(frame_buffer)

                self._draw_top_bar(buttons)
                if self.show_controls:
                    self._draw_controls_overlay()

                pygame.display.flip()
                clock.tick(60)
                pygame.display.set_caption(f"NES Emulator - {clock.get_fps():.2f} FPS")

        finally:
            if hasattr(self.nes, 'shutdown'):
                self.nes.shutdown()
            pygame.quit()


def main():
    """Application entry point parser.

    Args:
        None.

    Returns:
        None.

    Raises:
        SystemExit: If ROM path argument is not provided.
    """
    if len(sys.argv) < 2:
        print("Usage: python main.py <path_to_rom>")
        sys.exit(1)

    app = EmulatorApp(sys.argv[1])
    app.run()


if __name__ == "__main__":
    main()
