# cartridge.pyx
import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t

# Импорт мапперов
from mappers cimport Mapper0, Mapper1, Mapper2, Mapper3, Mapper4


cdef class Cartridge:
    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    cdef public uint8_t mapper, prg_banks, chr_banks
    cdef public object mapper_instance

    def __init__(self, file_path: str):
        # Читаем файл
        with open(file_path, 'rb') as f:
            data = np.frombuffer(f.read(), dtype=np.uint8).copy()
        
        # Проверяем заголовок
        if data[:4].tobytes() != b'NES\x1A':
            raise ValueError("Invalid NES ROM file")

        # Получаем количество банков
        self.prg_banks = data[4]
        self.chr_banks = data[5]
        self.mapper = ((data[6] >> 4) | ((data[7] & 0xF0) >> 4))

        # Вычисляем размеры памяти
        prg_size = self.prg_banks * 16384
        chr_size = self.chr_banks * 8192

        # Create numpy arrays for PRG and CHR
        start = 16
        prg_slice = data[start:start + prg_size]
        start += prg_size
        chr_slice = data[start:start + chr_size]

        # Copy slices to ensure ownership and contiguity
        if prg_size > 0:
            self.prg_rom = np.array(prg_slice, dtype=np.uint8).copy()
        else:
            self.prg_rom = np.zeros(0, dtype=np.uint8)

        if chr_size == 0:
            # CHR RAM (some carts use CHR-RAM)
            print("CHR-ROM отсутствует, создаем RAM для графики (8KB)")
            self.chr_rom = np.zeros(8192, dtype=np.uint8)
            self.chr_banks = 1
        else:
            self.chr_rom = np.array(chr_slice, dtype=np.uint8).copy()

        # Create memoryviews for Cython access
        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom

        print(f"PRG-ROM Loaded: {len(self.prg_rom)} bytes")
        print(f"CHR-ROM Loaded: {len(self.chr_rom)} bytes")
        if len(self.chr_rom) > 0:
            print(f"First 64 CHR bytes: {self.chr_rom[:64]}")

        # Загружаем нужный маппер
        self.load_mapper()
        

    def load_mapper(self):
        """ Подключает соответствующий маппер """
        if self.mapper == 0:
            self.mapper_instance = Mapper0(self.prg_rom, self.chr_rom)
        elif self.mapper == 1:
            self.mapper_instance = Mapper1(self.prg_rom, self.chr_rom)
        elif self.mapper == 2:
            self.mapper_instance = Mapper2(self.prg_rom, self.chr_rom)
        elif self.mapper == 3:
            self.mapper_instance = Mapper3(self.prg_rom, self.chr_rom)
        elif self.mapper == 4:
            self.mapper_instance = Mapper4(self.prg_rom, self.chr_rom)
        else:
            raise ValueError(f"Unsupported mapper: {self.mapper}")

        print(f"Mapper {self.mapper} initialized!")

    cdef uint8_t read_prg(self, uint16_t address):
        return self.mapper_instance.read_prg(address)

    cdef uint8_t read_chr(self, uint16_t address):
        value = self.mapper_instance.read_chr(address)
        print(f"PPU: Reading CHR {hex(address)} -> {hex(value)}")
        return value

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.mapper_instance.write_prg(address, value)

    cdef void write_chr(self, uint16_t address, uint8_t value):
        self.mapper_instance.write_chr(address, value)
