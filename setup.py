from setuptools import setup
from Cython.Build import cythonize
import numpy as np

setup(
    ext_modules=cythonize(
        ["cpu.pyx", "ppu.pyx", "apu.pyx", "controller.pyx", "mappers.pyx", "mappers.pxd", "cartridge.pyx"],
        language_level="3"
    ),
    include_dirs=[np.get_include()],
    # extra_compile_args=["-std=c99"]  # <-- Включаем поддержку `stdint.h`
)
