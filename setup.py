from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy as np

extensions = [
    Extension("cpu", ["emulator/cpu/cpu.pyx"], extra_compile_args=["-O3", "-flto", "-fno-strict-overflow", "-fno-math-errno"]),
    Extension("ppu", ["emulator/ppu/ppu.pyx"], extra_compile_args=["-O3", "-flto", "-fno-strict-overflow", "-fno-math-errno"]),
    Extension("apu", ["emulator/apu/apu.pyx"], extra_compile_args=["-O3", "-flto", "-fno-strict-overflow", "-fno-math-errno"]),
    Extension("controller", ["emulator/controller/controller.pyx"], extra_compile_args=["-O3", "-flto", "-fno-strict-overflow", "-fno-math-errno"]),
    Extension("mappers", ["emulator/mappers/mappers.pyx"], extra_compile_args=["-O3", "-flto", "-fno-strict-overflow", "-fno-math-errno"]),
    Extension("cartridge", ["emulator/cartridge/cartridge.pyx"], extra_compile_args=["-O3", "-flto", "-fno-strict-overflow", "-fno-math-errno"])
]

setup(
    ext_modules=cythonize(
        extensions,
        language_level="3",
        compiler_directives={
            'boundscheck': False,
            'wraparound': False,
            'initializedcheck': False,
            'cdivision': True,
            'nonecheck': False,
            'language_level': '3'
        },
        include_path=["emulator", "emulator/mappers", "emulator/cpu", "emulator/ppu", "emulator/apu"]
    ),
    include_dirs=[
        np.get_include(),
        "emulator",
        "emulator/cpu",
        "emulator/ppu",
        "emulator/apu",
        "emulator/mappers",
        "emulator/controller",
        "emulator/cartridge"
    ],
)
