from libc.stdint cimport uint32_t

cdef class APU:
    cdef uint32_t cycles  # Ограничиваем размер числа

    def __init__(self):
        self.cycles = 0

    def step(self, uint32_t cpu_cycles):
        self.cycles += cpu_cycles  # Теперь значение не выйдет за границы
