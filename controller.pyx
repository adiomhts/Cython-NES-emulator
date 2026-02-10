from libc.stdint cimport uint8_t

cdef class Controller:
    cdef uint8_t buttons       # Текущее реальное состояние (от клавиатуры)
    cdef uint8_t shift_reg     # То, что отдаем процессору при чтении
    cdef bint strobe           # Режим "защелки"

    def __init__(self):
        self.buttons = 0
        self.shift_reg = 0
        self.strobe = False

    # Ожидает список булевых значений: [A, B, Select, Start, Up, Down, Left, Right]
    def update(self, list buttons_state):
        self.buttons = 0
        # Упаковываем массив bool в 1 байт (бит 0 = A, бит 7 = Right)
        if len(buttons_state) >= 8:
            if buttons_state[0]: self.buttons |= 0x01 # A
            if buttons_state[1]: self.buttons |= 0x02 # B
            if buttons_state[2]: self.buttons |= 0x04 # Select
            if buttons_state[3]: self.buttons |= 0x08 # Start
            if buttons_state[4]: self.buttons |= 0x10 # Up
            if buttons_state[5]: self.buttons |= 0x20 # Down
            if buttons_state[6]: self.buttons |= 0x40 # Left
            if buttons_state[7]: self.buttons |= 0x80 # Right
        
        # Если строб включен, регистр прозрачен (сразу видит изменения)
        if self.strobe:
            self.shift_reg = self.buttons

    # Запись в порт $4016 (из CPU)
    cpdef public void write(self, uint8_t value):
        cdef bint new_strobe = (value & 1) != 0
        
        # При переходе строба (или если он активен), обновляем регистр
        if self.strobe or new_strobe:
            self.shift_reg = self.buttons
            
        self.strobe = new_strobe

    # Чтение из порта $4016 (из CPU)
    cpdef public uint8_t read(self):
        cdef uint8_t ret
        
        if self.strobe:
            # В режиме строба всегда читается состояние кнопки A
            ret = self.buttons & 1
        else:
            # Читаем младший бит
            ret = self.shift_reg & 1
            # Сдвигаем регистр вправо, заполняя старший бит единицей
            # (стандартное поведение NES: после 8 чтений идут единицы)
            self.shift_reg = (self.shift_reg >> 1) | 0x80
            
        # NES обычно возвращает 0x40 или 0x41 на неиспользуемых битах шины (open bus)
        return ret | 0x40