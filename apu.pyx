cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef class APU:
    cdef uint32_t cycles  # Ограничиваем размер числа

    def __init__(self):
        self.cycles = 0

    def step(self, uint32_t cpu_cycles):
        self.cycles += cpu_cycles  # Теперь значение не выйдет за границы
    
    cpdef public void write(self, uint16_t addr, uint8_t value):
        # Заглушка для записи в регистры APU
        pass