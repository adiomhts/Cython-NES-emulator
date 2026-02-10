import pygame
import sys
import time
import os
from nes import NES

# Карта кнопок клавиатуры на кнопки NES
# NES: A, B, Select, Start, Up, Down, Left, Right
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

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python main.py <path_to_rom>")
        sys.exit(1)
    
    rom_path = sys.argv[1]
    dump_nametable = os.getenv("NES_DUMP_NT") in {"1", "true", "yes", "on"}
    dump_frame_env = os.getenv("NES_DUMP_NT_FRAME")
    dump_frames_env = os.getenv("NES_DUMP_NT_FRAMES")
    dump_frames = []
    if dump_frames_env:
        for part in dump_frames_env.split(","):
            part = part.strip()
            if part.isdigit():
                dump_frames.append(int(part))
    if not dump_frames:
        dump_frame = int(dump_frame_env) if dump_frame_env and dump_frame_env.isdigit() else 120
        dump_frames = [dump_frame]
    force_bg_pattern_env = os.getenv("NES_BG_PATTERN")
    force_bg_pattern = None
    if force_bg_pattern_env is not None and force_bg_pattern_env.strip() in {"0", "1"}:
        force_bg_pattern = int(force_bg_pattern_env.strip())
    force_sprite_pattern_env = os.getenv("NES_SPR_PATTERN")
    force_sprite_pattern = None
    if force_sprite_pattern_env is not None and force_sprite_pattern_env.strip() in {"0", "1"}:
        force_sprite_pattern = int(force_sprite_pattern_env.strip())
    dump_chr_tiles_env = os.getenv("NES_DUMP_CHR_TILES")
    dump_chr_tiles = []
    if dump_chr_tiles_env:
        for part in dump_chr_tiles_env.split(","):
            part = part.strip()
            if not part:
                continue
            try:
                dump_chr_tiles.append(int(part, 16) if part.lower().startswith("0x") else int(part))
            except ValueError:
                pass
    tile_info_env = os.getenv("NES_TILE_INFO")
    tile_info = None
    if tile_info_env:
        parts = [p.strip() for p in tile_info_env.split(",")]
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            tile_info = (int(parts[0]), int(parts[1]))

    nes = NES(rom_path)
    if force_bg_pattern is not None:
        try:
            nes.ppu.force_bg_pattern = force_bg_pattern
        except Exception:
            pass
    if force_sprite_pattern is not None:
        try:
            nes.ppu.force_sprite_pattern = force_sprite_pattern
        except Exception:
            pass
    
    # Часы для ограничения FPS
    clock = pygame.time.Clock()
    running = True
    dumped_nt = False
    frame_count = 0

    print("Emulator started. Controls: Arrows=Move, Z=A, X=B, Enter=Start, RShift=Select")

    while running:
        # 1. ОБРАБОТКА СОБЫТИЙ (Важно, чтобы окно не висло!)
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False

        # 2. Считывание управления
        keys = pygame.key.get_pressed()
        
        # Формируем список состояний кнопок для контроллера
        # Порядок в Controller.pyx: [A, B, Select, Start, Up, Down, Left, Right]
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
        
        # Передаем в эмулятор
        if hasattr(nes, 'controller') and nes.controller:
            nes.controller.update(input_state)

        # 3. Эмуляция кадра
        nes.run_frame()
        # frame_count += 1

        # Optional: dump nametable once for debugging
        if dump_nametable and frame_count in dump_frames:
            try:
                ppu = nes.ppu
                vram = ppu.vram

                def dump_table(path, data, rows=30):
                    lines = []
                    for row in range(rows):
                        row_bytes = data[row * 32:(row + 1) * 32]
                        lines.append(" ".join(f"{int(b):02X}" for b in row_bytes))
                    with open(path, "w", encoding="utf-8") as f:
                        f.write("\n".join(lines))

                nt0 = vram[:0x3C0]
                nt1 = vram[0x400:0x7C0]
                suffix = f"_f{frame_count}" if len(dump_frames) > 1 else ""
                dump_table(f"nametable0{suffix}.txt", nt0)
                dump_table(f"nametable1{suffix}.txt", nt1)

                with open(f"attrtable0{suffix}.txt", "w", encoding="utf-8") as f:
                    f.write(" ".join(f"{int(b):02X}" for b in vram[0x3C0:0x400]))
                with open(f"attrtable1{suffix}.txt", "w", encoding="utf-8") as f:
                    f.write(" ".join(f"{int(b):02X}" for b in vram[0x7C0:0x800]))

                with open(f"palette_ram{suffix}.txt", "w", encoding="utf-8") as f:
                    f.write(" ".join(f"{int(b):02X}" for b in ppu.palette_ram))

                nonzero_nt0 = sum(1 for b in nt0 if int(b) != 0)
                nonzero_nt1 = sum(1 for b in nt1 if int(b) != 0)
                ctrl_nt = int(ppu.ctrl) & 0x03
                v_val = int(ppu.debug_get_v()) if hasattr(ppu, "debug_get_v") else 0
                t_val = int(ppu.debug_get_t()) if hasattr(ppu, "debug_get_t") else 0
                v_nt = (v_val >> 10) & 0x03
                t_nt = (t_val >> 10) & 0x03
                print(
                    f"Saved nametable0{suffix}.txt/nametable1{suffix}.txt and "
                    f"attrtable0{suffix}.txt/attrtable1{suffix}.txt. "
                    f"Nonzero NT0={nonzero_nt0}, NT1={nonzero_nt1}"
                )
                scroll_x = int(ppu.debug_get_scroll_x()) if hasattr(ppu, "debug_get_scroll_x") else 0
                scroll_y = int(ppu.debug_get_scroll_y()) if hasattr(ppu, "debug_get_scroll_y") else 0
                nonzero_palette = sum(1 for b in ppu.palette_ram if int(b) != 0)
                bg_ctrl = (int(ppu.ctrl) >> 4) & 0x01
                spr_ctrl = (int(ppu.ctrl) >> 3) & 0x01
                if dump_chr_tiles:
                    chr_rom = ppu.chr_rom
                    bg_pattern = force_bg_pattern if force_bg_pattern is not None else bg_ctrl
                    base = 0x1000 if bg_pattern == 1 else 0x0000

                    def dump_chr_tile(tile_index: int):
                        offset = base + tile_index * 16
                        if offset + 16 > len(chr_rom):
                            return
                        lines = []
                        for row in range(8):
                            low = chr_rom[offset + row]
                            high = chr_rom[offset + 8 + row]
                            pixels = []
                            for bit in range(7, -1, -1):
                                pix = ((high >> bit) & 1) << 1 | ((low >> bit) & 1)
                                pixels.append(str(pix))
                            lines.append(" ".join(pixels))
                        with open(f"chr_tile_{tile_index:02X}.txt", "w", encoding="utf-8") as f:
                            f.write("\n".join(lines))

                    for idx in dump_chr_tiles:
                        dump_chr_tile(idx)

                if tile_info:
                    tile_x, tile_y = tile_info
                    if 0 <= tile_x < 32 and 0 <= tile_y < 30:
                        tile_index = int(nt0[tile_y * 32 + tile_x])
                        attr_index = (tile_y >> 2) * 8 + (tile_x >> 2)
                        attr_byte = int(vram[0x3C0 + attr_index])
                        shift = ((tile_y & 0x02) << 1) | (tile_x & 0x02)
                        palette_index = (attr_byte >> shift) & 0x03
                        print(
                            f"Tile info (NT0 {tile_x},{tile_y}): "
                            f"tile=0x{tile_index:02X} palette={palette_index} attr=0x{attr_byte:02X}"
                        )
                print(
                    "PPU state: "
                    f"CTRL_NT={ctrl_nt} V_NT={v_nt} T_NT={t_nt} "
                    f"scroll_x={scroll_x} scroll_y={scroll_y} v=0x{v_val:04X} "
                    f"palette_nonzero={nonzero_palette} bg_pattern_ctrl={bg_ctrl} "
                    f"spr_pattern_ctrl={spr_ctrl}"
                )
            except Exception as e:
                print("Failed to dump nametable:", e)
            if frame_count == dump_frames[-1]:
                dumped_nt = True
        
        # 4. Ограничение скорости (60 FPS)
        # Если убрать это, игра будет работать слишком быстро на мощном ПК
        clock.tick(60)
        
        # Вывод реального FPS в заголовок (для отладки)
        pygame.display.set_caption(f"NES Emulator - {clock.get_fps():.2f} FPS")

    pygame.quit()