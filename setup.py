from setuptools import setup
from Cython.Build import cythonize
import numpy as np

setup(
    ext_modules=cythonize(
        [
            "emulator/cpu/cpu.pyx",
            "emulator/ppu/ppu.pyx",
            "emulator/apu/apu.pyx",
            "emulator/controller/controller.pyx",
            "emulator/mappers/mappers.pyx",
            "emulator/cartridge/cartridge.pyx"
        ],
        language_level="3"
    ),
    include_dirs=[np.get_include()],
)
