import pygame
import sys
import time
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
    nes = NES(rom_path)
    
    # Часы для ограничения FPS
    clock = pygame.time.Clock()
    running = True

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
        
        # 4. Ограничение скорости (60 FPS)
        # Если убрать это, игра будет работать слишком быстро на мощном ПК
        clock.tick(60)
        
        # Вывод реального FPS в заголовок (для отладки)
        pygame.display.set_caption(f"NES Emulator - {clock.get_fps():.2f} FPS")

    pygame.quit()