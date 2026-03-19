import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t
from mappers cimport Mapper0, Mapper1, Mapper2, Mapper3, Mapper4

cdef class Cartridge:
    """iNES cartridge parser exposing PRG/CHR buffers and mapper metadata.

    Parses ROM header and payload, prepares PRG/CHR memory, and constructs
    a mapper implementation used by CPU/PPU memory accesses.
    """

    cdef public object prg_rom
    cdef public object chr_rom
    cdef unsigned char[:] prg_rom_view
    cdef unsigned char[:] chr_rom_view
    
    cdef public uint8_t mapper, prg_banks, chr_banks, mirroring
    cdef public object mapper_instance

    def __init__(self, file_path: str):
        """Load and parse a `.nes` ROM file.

        Args:
            file_path: Path to ROM file in iNES format.

        Returns:
            None.

        Side Effects:
            Reads file from disk, initializes PRG/CHR arrays and typed views,
            sets mapper/mirroring metadata, and builds mapper instance.

        Raises:
            ValueError: If file does not contain a valid iNES signature.
            OSError: If ROM file cannot be opened/read.
        """
        with open(file_path, 'rb') as f:
            data = np.frombuffer(f.read(), dtype=np.uint8).copy()
        
        if data[:4].tobytes() != b'NES\x1A':
            raise ValueError("Invalid NES ROM file")

        self.prg_banks = data[4]
        self.chr_banks = data[5]
        
        self.mirroring = data[6] & 1
        
        self.mapper = ((data[6] >> 4) | ((data[7] & 0xF0) >> 4))

        prg_size = self.prg_banks * 16384
        chr_size = self.chr_banks * 8192

        start = 16
        prg_slice = data[start:start + prg_size]
        start += prg_size
        chr_slice = data[start:start + chr_size]

        if prg_size > 0:
            self.prg_rom = np.array(prg_slice, dtype=np.uint8).copy()
        else:
            self.prg_rom = np.zeros(0, dtype=np.uint8)

        if chr_size == 0:
            self.chr_rom = np.zeros(8192, dtype=np.uint8)
            self.chr_banks = 1
        else:
            self.chr_rom = np.array(chr_slice, dtype=np.uint8).copy()

        self.prg_rom_view = self.prg_rom
        self.chr_rom_view = self.chr_rom


        self.load_mapper()

    
    def load_mapper(self):
        """Instantiate mapper implementation for the currently parsed mapper id.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Assigns `self.mapper_instance` with one of the supported mapper
            classes.

        Raises:
            ValueError: If mapper id is not supported by this build.
        """
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

    cdef uint8_t read_prg(self, uint16_t address):
        return self.mapper_instance.read_prg(address)

    cdef uint8_t read_chr(self, uint16_t address):
        return self.mapper_instance.read_chr(address)

    cdef void write_prg(self, uint16_t address, uint8_t value):
        self.mapper_instance.write_prg(address, value)

    cdef void write_chr(self, uint16_t address, uint8_t value):
        self.mapper_instance.write_chr(address, value)