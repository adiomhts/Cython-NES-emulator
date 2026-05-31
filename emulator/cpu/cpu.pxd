import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, int8_t
from mappers cimport MapperBase

cdef class CPU6502:
    cdef uint8_t A
    cdef uint8_t X
    cdef uint8_t Y
    cdef uint8_t SP
    cdef uint16_t PC
    cdef object F  # Assuming CPUFlags is a Python class or handles itself
    cdef public cnp.ndarray memory
    cdef cnp.ndarray ram
    cdef public int cycles
    cdef uint8_t current_instruction
    cdef uint16_t current_memory_address
    cdef bint has_current_address
    cdef uint16_t interrupt_vectors[3]
    cdef bint interrupts[2]
    cdef object ppu
    cdef object apu
    cdef object controller
    cdef object controller2
    cdef object cartridge
    cdef public MapperBase mapper_instance
    cdef int _debug_instr_printed
    cdef int _debug_instr_limit
    cdef int _has_reset_once

    cpdef public void step(self)
    cpdef public void reset(self)
    cpdef public void trigger_interrupt(self, int type)
    cdef inline uint8_t fetch(self)
    cdef inline uint8_t read_byte(self, uint16_t address)
    cdef inline void write_byte(self, uint16_t address, uint8_t value)
    cdef inline uint16_t read_word(self, uint16_t address)
    cdef inline void push(self, uint8_t value)
    cdef inline uint8_t pop(self)
    cdef inline void push_word(self, uint16_t value)
    cdef inline uint16_t pop_word(self)
    cdef inline uint8_t get_P(self)
    cdef inline void set_P(self, uint8_t value)
    cdef inline uint8_t next_byte(self)
    cdef inline uint16_t next_word(self)
    cdef inline int8_t next_sbyte(self)
    cdef inline uint16_t address(self)
    cdef inline uint8_t address_read(self)
    cdef inline void address_write(self, uint8_t val)
    cdef void execute(self, uint8_t opcode)
    cdef void write_io_register(self, uint16_t reg, uint8_t val)
    cdef uint8_t read_io_register(self, uint16_t reg)

# CPU Opcode Handlers
cdef void op_JSR(CPU6502 cpu)
cdef void op_RTI(CPU6502 cpu)
cdef void op_RTS(CPU6502 cpu)
cdef void op_INY(CPU6502 cpu)
cdef void op_DEY(CPU6502 cpu)
cdef void op_INX(CPU6502 cpu)
cdef void op_DEX(CPU6502 cpu)
cdef void op_TAY(CPU6502 cpu)
cdef void op_TYA(CPU6502 cpu)
cdef void op_TAX(CPU6502 cpu)
cdef void op_TXA(CPU6502 cpu)
cdef void op_TSX(CPU6502 cpu)
cdef void op_TXS(CPU6502 cpu)
cdef void op_PHP(CPU6502 cpu)
cdef void op_PLP(CPU6502 cpu)
cdef void op_PLA(CPU6502 cpu)
cdef void op_PHA(CPU6502 cpu)
cdef void op_BIT(CPU6502 cpu)
cdef void op_JMP(CPU6502 cpu)
cdef void op_BCS(CPU6502 cpu)
cdef void op_BCC(CPU6502 cpu)
cdef void op_BEQ(CPU6502 cpu)
cdef void op_BNE(CPU6502 cpu)
cdef void op_BVS(CPU6502 cpu)
cdef void op_BVC(CPU6502 cpu)
cdef void op_BPL(CPU6502 cpu)
cdef void op_BMI(CPU6502 cpu)
cdef void op_STA(CPU6502 cpu)
cdef void op_STX(CPU6502 cpu)
cdef void op_STY(CPU6502 cpu)
cdef void op_CLC(CPU6502 cpu)
cdef void op_SEC(CPU6502 cpu)
cdef void op_CLI(CPU6502 cpu)
cdef void op_SEI(CPU6502 cpu)
cdef void op_CLV(CPU6502 cpu)
cdef void op_CLD(CPU6502 cpu)
cdef void op_SED(CPU6502 cpu)
cdef void op_NOP(CPU6502 cpu)
cdef void op_LDA(CPU6502 cpu)
cdef void op_LDY(CPU6502 cpu)
cdef void op_LDX(CPU6502 cpu)
cdef void op_ORA(CPU6502 cpu)
cdef void op_AND(CPU6502 cpu)
cdef void op_EOR(CPU6502 cpu)
cdef void op_SBC(CPU6502 cpu)
cdef void op_ADC(CPU6502 cpu)
cdef void op_BRK(CPU6502 cpu)
cdef void op_CMP(CPU6502 cpu)
cdef void op_CPX(CPU6502 cpu)
cdef void op_CPY(CPU6502 cpu)
cdef void op_LSR(CPU6502 cpu)
cdef void op_ASL(CPU6502 cpu)
cdef void op_ROR(CPU6502 cpu)
cdef void op_ROL(CPU6502 cpu)
cdef void op_INC(CPU6502 cpu)
cdef void op_DEC(CPU6502 cpu)
cdef void op_SKB(CPU6502 cpu)
cdef void op_ANC(CPU6502 cpu)
cdef void op_ALR(CPU6502 cpu)
cdef void op_ARR(CPU6502 cpu)
cdef void op_ATX(CPU6502 cpu)
