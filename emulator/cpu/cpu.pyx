import numpy as np
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, int8_t

include "cpu_flags.pyx"
include "cpu_adressing_modes.pyx"

# Glossary (terms used in comments/docstrings in this file):
# - CPU: Central Processing Unit (Ricoh 2A03, 6502-derived core).
# - PC/SP: Program Counter / Stack Pointer registers.
# - IRQ/NMI: Maskable / non-maskable interrupt request lines.
# - DMA: Direct Memory Access; here OAM DMA via '$4014'.
# - RMW: Read-Modify-Write instruction class with dummy write behavior.
# - Zero page: First 256 bytes ('$0000-$00FF') with special addressing modes.
# NESdev references:
# - https://www.nesdev.org/wiki/CPU
# - https://www.nesdev.org/wiki/CPU_memory_map
# - https://www.nesdev.org/wiki/CPU_interrupts
# - https://www.nesdev.org/wiki/DMA

cdef class CPU6502:
    """Ricoh 2A03 CPU core with NES bus mapping and interrupt handling.

    Implements instruction fetch/decode/execute, interrupt sequencing, and
    memory-mapped IO dispatch to PPU/APU/controller/cartridge.

    NESdev references:
    - https://www.nesdev.org/wiki/CPU
    - https://www.nesdev.org/wiki/CPU_memory_map
    - https://www.nesdev.org/wiki/Cycle_reference_chart
    """

    cdef uint8_t A
    cdef uint8_t X
    cdef uint8_t Y
    cdef uint8_t SP
    cdef uint16_t PC
    cdef CPUFlags F
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
    cdef int _debug_instr_printed
    cdef int _debug_instr_limit

    def __init__(self):
        """Create CPU state, opcode tables, and interrupt vectors.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Allocates CPU RAM/memory arrays, initializes status/register fields,
            and prepares opcode metadata used by execution loop.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_power_up_state
            https://www.nesdev.org/wiki/CPU_memory_map
        """
        # 6502 general-purpose registers.
        self.A = <uint8_t>0x00
        self.X = <uint8_t>0x00
        self.Y = <uint8_t>0x00
        # Stack pointer reset default for NES power-up flow.
        self.SP = <uint8_t>0xFD
        self.PC = <uint16_t>0x0000
        # Processor status flags container.
        self.F = CPUFlags()
        self.F.interrupts_disabled = True
        # Full 64KB address space view (used for fallback / mapped regions).
        self.memory = np.full(0x10000, 0x00, dtype=np.uint8)
        # Internal RAM physically 2KB and mirrored through $1FFF.
        self.ram = np.full(0x0800, 0xFF, dtype=np.uint8)
        # Global cycle counter consumed by scheduler and peripherals.
        self.cycles = 0
        self.current_instruction = 0
        self.current_memory_address = 0
        self.has_current_address = False
        # Build opcode dispatch tables exactly once per instance startup.
        init_opcodes()
        # Interrupt vectors: NMI, IRQ/BRK, RESET.
        self.interrupt_vectors[0] = 0xFFFA
        self.interrupt_vectors[1] = 0xFFFE
        self.interrupt_vectors[2] = 0xFFFC
        # Pending interrupt latches.
        self.interrupts[0] = False
        self.interrupts[1] = False
        self.controller2 = None
        self._debug_instr_printed = 0
        self._debug_instr_limit = 50

    cpdef public void reset(self):
        """Reset CPU core state.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Loads PC from RESET vector, resets stack pointer and cycle counter,
            and forces interrupt-disable flag.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_power_up_state
            https://www.nesdev.org/wiki/CPU_interrupts
        """
        # Read reset vector from $FFFC/$FFFD and jump execution there.
        self.PC = self.read_word(self.interrupt_vectors[2])
        # Reset stack pointer and interrupt mask for deterministic startup.
        self.SP = <uint8_t>0xFD
        self.F.interrupts_disabled = True
        self.cycles = 0

    cdef uint8_t fetch(self):
        cdef uint8_t opcode = self.read_byte(self.PC)
        self.PC += 1
        return opcode

    cdef uint8_t read_byte(self, uint16_t address):
        # $0000-$1FFF: internal RAM mirrored every 2KB.
        if 0x0000 <= address <= 0x1FFF:
            return self.ram[address & 0x07FF]
            
        # $2000-$3FFF: PPU registers mirrored every 8 bytes.
        if 0x2000 <= address <= 0x3FFF:
            reg = 0x2000 + (address % 8)
            return self.ppu.read_register(reg)
            
        # $4000-$401F: APU and controller I/O space.
        if 0x4000 <= address <= 0x401F:
            return self.read_io_register(address)

        # $6000-$7FFF: cartridge PRG RAM / save RAM window.
        if 0x6000 <= address <= 0x7FFF:
            if self.cartridge is not None:
                try:
                    if getattr(self.cartridge, 'mapper', 0) == 1:
                        return self.cartridge.mapper_instance.read_prg(address)
                except Exception:
                    pass
            return self.memory[address]
            
        # $8000-$FFFF: cartridge PRG ROM through mapper.
        if 0x8000 <= address <= 0xFFFF:
            return self.cartridge.mapper_instance.read_prg(address)
            
        # Generic fallback for any unmapped path.
        return self.memory[address]

    cdef void write_byte(self, uint16_t address, uint8_t value):
        # PPU register writes.
        if 0x2000 <= address <= 0x3FFF:
            reg = 0x2000 + (address % 8)
            self.ppu.write_register(reg, value)
            return
            
        # APU/controller and DMA register writes.
        if 0x4000 <= address <= 0x401F:
            self.write_io_register(address, value)
            return

        # Internal RAM writes with mirroring.
        if 0x0000 <= address <= 0x1FFF:
            self.ram[address & 0x07FF] = value

        elif 0x6000 <= address <= 0x7FFF:
            # Mapper-specific PRG RAM handling (MMC1 path).
            if self.cartridge is not None:
                try:
                    if getattr(self.cartridge, 'mapper', 0) == 1:
                        self.cartridge.mapper_instance.write_prg(address, value)
                        return
                except Exception:
                    pass
            self.memory[address] = value
            
        elif address >= 0x8000:
            # Writes to PRG area are mapper control writes for many cartridges.
            self.cartridge.mapper_instance.write_prg(address, value)
            
        else:
            self.memory[address] = value

    cdef uint16_t read_word(self, uint16_t address):
        # 6502 words are little-endian: low byte then high byte.
        return <uint16_t>(self.read_byte(address) | (self.read_byte(address + 1) << 8))

    cdef void push(self, uint8_t value):
        # Stack is fixed at page $0100 and grows downward.
        self.write_byte(0x0100 + self.SP, value)
        self.SP -= 1

    cdef uint8_t pop(self):
        # Pop reverses push order and stack grows upward on read.
        self.SP += 1
        return self.read_byte(0x0100 + self.SP)

    cdef void push_word(self, uint16_t value):
        # Push high then low, matching 6502 interrupt/call conventions.
        self.push(<uint8_t>(value >> 8))
        self.push(<uint8_t>(value & 0xFF))

    cdef uint16_t pop_word(self):
        return <uint16_t>(self.pop() | (self.pop() << 8))

    cdef uint8_t get_P(self):
        return <uint8_t>(
            (self.F.carry << 0) |
            (self.F.zero << 1) |
            (self.F.interrupts_disabled << 2) |
            (self.F.decimal_mode << 3) |
            (self.F.break_source << 4) |
            (1 << 5) |
            (self.F.overflow << 6) |
            (self.F.negative << 7)
        )

    cdef void set_P(self, uint8_t value):
        self.F.carry = (value & 0x01) > 0
        self.F.zero = (value & 0x02) > 0
        self.F.interrupts_disabled = (value & 0x04) > 0
        self.F.decimal_mode = (value & 0x08) > 0
        self.F.break_source = (value & 0x10) > 0
        self.F.overflow = (value & 0x40) > 0
        self.F.negative = (value & 0x80) > 0

    cdef uint8_t next_byte(self):
        # Fetch one byte at PC and post-increment.
        cdef uint8_t value = self.read_byte(self.PC)
        self.PC += 1
        return value

    cdef uint16_t next_word(self):
        # Fetch little-endian 16-bit operand and advance PC by 2.
        cdef uint16_t value = self.read_word(self.PC)
        self.PC += 2
        return value

    cdef int8_t next_sbyte(self):
        return <int8_t>self.next_byte()

    cdef uint16_t address(self):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        cdef uint16_t addr
        cdef uint8_t off
        if defn.mode == IMMEDIATE:
            # Immediate mode uses operand byte at current PC.
            addr = self.PC
            self.PC += 1
        elif defn.mode == ZEROPAGE:
            # Zero-page addressing wraps within $00xx.
            addr = self.next_byte()
        elif defn.mode == ABSOLUTE:
            # Absolute 16-bit address operand.
            addr = self.next_word()
        elif defn.mode == ZEROPAGEX:
            # Zero-page indexed by X with wrap-around.
            addr = (self.next_byte() + self.X) & 0xFF
        elif defn.mode == ZEROPAGEY:
            # Zero-page indexed by Y with wrap-around.
            addr = (self.next_byte() + self.Y) & 0xFF
        elif defn.mode == ABSOLUTEX:
            # Absolute indexed by X (may incur page-cross cycle).
            addr = self.next_word()
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.X) & 0xFF00):
                self.cycles += 1
            addr += self.X
        elif defn.mode == ABSOLUTEY:
            # Absolute indexed by Y (may incur page-cross cycle).
            addr = self.next_word()
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.Y) & 0xFF00):
                self.cycles += 1
            addr += self.Y
        elif defn.mode == INDIRECTX:
            # (d,X): first index zp pointer by X, then read 16-bit target.
            off = (self.next_byte() + self.X) & 0xFF
            addr = <uint16_t>(self.read_byte(off) | (self.read_byte((off + 1) & 0xFF) << 8))
        elif defn.mode == INDIRECTY:
            # (d),Y: read zp pointer then index final target by Y.
            off = self.next_byte() & 0xFF
            addr = <uint16_t>(self.read_byte(off) | (self.read_byte((off + 1) & 0xFF) << 8))
            if defn.page_boundary and (addr & 0xFF00) != ((addr + self.Y) & 0xFF00):
                self.cycles += 1
            addr += self.Y
        else:
            # NONE/direct modes do not resolve a memory address here.
            addr = 0
        return addr

    cdef uint8_t address_read(self):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        if defn.mode == DIRECT:
            # Accumulator-addressed ops read A directly.
            return self.A
        if not self.has_current_address:
            # Resolve once so RMW ops reuse same effective address.
            self.current_memory_address = self.address()
            self.has_current_address = True
        return self.read_byte(self.current_memory_address)

    cdef void address_write(self, uint8_t val):
        cdef OpcodeDef defn = opcode_defs[self.current_instruction]
        if defn.mode == DIRECT:
            # Accumulator-addressed write targets A register directly.
            self.A = val
            self.F.zero = (self.A == 0)
            self.F.negative = (self.A & 0x80) > 0
        else:
            if not self.has_current_address:
                # Ensure same effective address as prior read phase.
                self.current_memory_address = self.address()
                self.has_current_address = True
            if defn.rmw:
                # Emulate dummy write for read-modify-write timing behavior.
                self.write_byte(self.current_memory_address, self.read_byte(self.current_memory_address))
            # Final writeback phase.
            self.write_byte(self.current_memory_address, val)

    cdef void execute(self, uint8_t opcode):
        cdef void (*op_func)(CPU6502)
        # Track opcode so addressing helpers can inspect metadata.
        self.current_instruction = opcode
        # New instruction => no cached effective address yet.
        self.has_current_address = False
        op_func = opcode_table[opcode]
        if op_func != NULL:
            # Base cycles are charged before handler-specific penalties.
            self.cycles += opcode_defs[opcode].cycles
            op_func(self)
        else:
            return

    cpdef public void trigger_interrupt(self, int type):
        """Queue an interrupt request.

        Args:
            type: Interrupt kind identifier ('0=NMI', '1=IRQ', '2=RESET').

        Returns:
            None.

        Side Effects:
            Marks corresponding interrupt slot as pending when allowed by CPU
            interrupt mask rules.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_interrupts
            https://www.nesdev.org/wiki/NMI
        """
        # Interrupt is latched and consumed at the next 'step()' boundary.
        self.interrupts[type] = True
        try:
            itype = {0: 'NMI', 1: 'IRQ', 2: 'RESET'}.get(type, str(type))
        except Exception:
            pass

    cdef void write_io_register(self, uint16_t reg, uint8_t val):
        cdef int i
        cdef uint16_t dma_start
        cdef uint8_t[:] dma_buffer 

        if reg == 0x4014:
            # OAM DMA: copy page $xx00-$xxFF into PPU OAM.
            dma_start = <uint16_t>val << 8
            
            dma_buffer = np.zeros(256, dtype=np.uint8)
            
            for i in range(256):
                dma_buffer[i] = self.read_byte(dma_start + i)
            
            if self.ppu is not None:
                self.ppu.perform_dma(dma_buffer)
            
            # DMA stalls CPU for 513 or 514 cycles depending on parity.
            self.cycles += 513
            if self.cycles % 2 == 1:
                self.cycles += 1
                
        elif reg == 0x4016:
            # Controller strobe write is broadcast to both controllers.
            if self.controller is not None:
                self.controller.write(val)
            if self.controller2 is not None:
                self.controller2.write(val)
                
        elif reg <= 0x401F:
            # Remaining IO register writes are delegated to APU.
            if self.apu is not None:
                self.apu.write(reg, val)
        else:
            pass


    cdef uint8_t read_io_register(self, uint16_t reg):
        if reg == 0x4015:
            # APU status register (channel activity + IRQ flags).
            if self.apu is not None:
                return self.apu.read_status()
            return 0

        if reg == 0x4016:
            # Controller 1 serial read.
            if self.controller is not None:
                return self.controller.read()
            return 0x40

        if reg == 0x4017:
            # Controller 2 serial read.
            if self.controller2 is not None:
                return self.controller2.read()
            return 0x40
        # Unimplemented IO reads return open-bus-like zero fallback.
        return 0

    def set_peripherals(self, ppu, apu, controller, controller2=None):
        """Attach memory-mapped peripherals.

        Args:
            ppu: PPU instance handling '$2000-$3FFF' register space.
            apu: APU instance handling '$4000-$4017' register writes.
            controller: Controller instance handling '$4016' reads/writes.
            controller2: Optional controller instance for '$4017' reads.

        Returns:
            None.

        Side Effects:
            Stores references used by 'read_byte' and 'write_byte' dispatch.

        NESdev references:
            https://www.nesdev.org/wiki/CPU_memory_map
            https://www.nesdev.org/wiki/PPU_registers
        """
        # Keep direct references for fast dispatch in hot read/write paths.
        self.ppu = ppu
        self.apu = apu
        self.controller = controller
        self.controller2 = controller2

    def set_cartridge(self, cartridge):
        """Attach cartridge/mapper backend.

        Args:
            cartridge: Cartridge object exposing mapper read/write operations.

        Returns:
            None.

        Side Effects:
            Stores cartridge reference used by CPU PRG read/write mapping.

        NESdev references:
            https://www.nesdev.org/wiki/Mapper
            https://www.nesdev.org/wiki/CPU_memory_map
        """
        # Mapper object owns bank switching behavior for PRG/CHR accesses.
        self.cartridge = cartridge

    cpdef public void step(self):
        """Execute one CPU step.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Services pending interrupts or fetches/executes one opcode,
            mutating registers, memory, and cycle counter.

        NESdev references:
            https://www.nesdev.org/wiki/Cycle_reference_chart
            https://www.nesdev.org/wiki/CPU_interrupts
        """
        # Mapper (e.g., MMC3) may request IRQ asynchronously.
        if self.cartridge is not None:
            try:
                if getattr(self.cartridge.mapper_instance, 'irq_pending', 0):
                    self.interrupts[1] = True
            except Exception:
                pass

        # Service pending NMI/IRQ before fetching next opcode.
        for i in range(2):
            if self.interrupts[i] and (i == 0 or not self.F.interrupts_disabled):
                # Standard interrupt prologue: push PC/P, load vector, mask IRQ.
                self.push_word(self.PC)
                self.push(self.get_P())
                self.PC = self.read_word(self.interrupt_vectors[i])
                self.F.interrupts_disabled = True
                self.interrupts[i] = False
                return
        # No interrupt taken: execute one opcode.
        opcode = self.fetch()
        self.execute(opcode)

include "cpu_operations.pyx"
include "cpu_opcodes.pyx"