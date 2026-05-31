# NESdev references:
# - https://www.nesdev.org/wiki/CPU
# - https://www.nesdev.org/wiki/Status_flags

# IDE Static Analysis Hints
if not "CPU6502" in globals():
    from cpu cimport CPU6502
    from libc.stdint cimport uint8_t, uint16_t, int8_t

cdef void op_JSR(CPU6502 cpu):
    """JSR - Jump to Subroutine.

    Saves the program's current location by pushing the address of the
    instruction just before the return point onto the stack. It then "jumps"
    to a new address, causing the CPU to start executing code from that new
    location (the "subroutine").

    This is used to run a piece of code that can be called from many different
    places. When the subroutine is finished, an 'RTS' (Return from Subroutine)
    instruction is used to pop the saved address and resume execution.

    Side Effects:
        - The Program Counter (PC) is set to the subroutine's address.
        - The Stack Pointer (SP) is decremented by 2.
        - The return address is written to the stack.

    Note:
        The address pushed to the stack is that of the last byte of the JSR
        instruction. 'RTS' will pop this and add 1 to find the correct
        return location.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#JSR
    """
    # Push the address of the last byte of this instruction onto the stack.
    # The 'RTS' instruction will later pop this and add one to resume execution.
    cpu.push_word(cpu.PC + 1)
    # Read the 16-bit address operand that follows the opcode
    # and set the Program Counter to it, effectively jumping to the subroutine.
    cpu.PC = cpu.next_word()

cdef void op_RTI(CPU6502 cpu):
    """RTI - Return from Interrupt.

    Pulls the processor status and the program counter from the stack.
    This is used to exit from an interrupt handler.

    Side Effects:
        - All status flags are restored to their pre-interrupt state.
        - The Program Counter (PC) is restored.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#RTI
    """
    cpu.next_byte()
    cpu.set_P(cpu.pop())
    cpu.PC = cpu.pop_word()

cdef void op_RTS(CPU6502 cpu):
    """RTS - Return from Subroutine.

    Pulls the program counter (minus one) from the stack and increments it.
    This is used to return from a subroutine previously called by JSR.

    Side Effects:
        - The Program Counter (PC) is restored to the address after the
          original JSR call.

    Note:
        The address pushed by JSR is the address of the last byte of the
        JSR instruction. RTS pulls this and adds one to get the address
        of the next instruction to be executed.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#RTS
    """
    cpu.next_byte()
    cpu.PC = cpu.pop_word() + 1

cdef void op_INY(CPU6502 cpu):
    """INY - Increment Y Register.

    Adds one to the Y register.

    Side Effects:
        - The Zero flag is set if the new value in Y is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Note:
        This operation does not affect the Carry flag.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#INY
    """
    cpu.Y += 1
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_DEY(CPU6502 cpu):
    """DEY - Decrement Y Register.

    Subtracts one from the Y register.

    Side Effects:
        - The Zero flag is set if the new value in Y is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Note:
        This operation does not affect the Carry flag.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#DEY
    """
    cpu.Y -= 1
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_INX(CPU6502 cpu):
    """INX - Increment X Register.

    Adds one to the X register.

    Side Effects:
        - The Zero flag is set if the new value in X is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Note:
        This operation does not affect the Carry flag.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#INX
    """
    cpu.X += 1
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_DEX(CPU6502 cpu):
    """DEX - Decrement X Register.

    Subtracts one from the X register.

    Side Effects:
        - The Zero flag is set if the new value in X is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Note:
        This operation does not affect the Carry flag.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#DEX
    """
    cpu.X -= 1
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_TAY(CPU6502 cpu):
    """TAY - Transfer Accumulator to Y.

    Copies the value of the Accumulator (A) into the Y register.

    Side Effects:
        - The Zero flag is set if the new value in Y is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#TAY
    """
    cpu.Y = cpu.A
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_TYA(CPU6502 cpu):
    """TYA - Transfer Y to Accumulator.

    Copies the value of the Y register into the Accumulator (A).

    Side Effects:
        - The Zero flag is set if the new value in A is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#TYA
    """
    cpu.A = cpu.Y
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_TAX(CPU6502 cpu):
    """TAX - Transfer Accumulator to X.

    Copies the value of the Accumulator (A) into the X register.

    Side Effects:
        - The Zero flag is set if the new value in X is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#TAX
    """
    cpu.X = cpu.A
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_TXA(CPU6502 cpu):
    """TXA - Transfer X to Accumulator.

    Copies the value of the X register into the Accumulator (A).

    Side Effects:
        - The Zero flag is set if the new value in A is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#TXA
    """
    cpu.A = cpu.X
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_TSX(CPU6502 cpu):
    """TSX - Transfer Stack Pointer to X.

    Copies the value of the Stack Pointer (SP) into the X register.

    Side Effects:
        - The Zero flag is set if the new value in X is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#TSX
    """
    cpu.X = cpu.SP
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_TXS(CPU6502 cpu):
    """TXS - Transfer X to Stack Pointer.

    Copies the value of the X register into the Stack Pointer (SP).

    Note:
        This instruction does NOT affect any CPU flags.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#TXS
    """
    cpu.SP = cpu.X

cdef void op_PHP(CPU6502 cpu):
    """PHP - Push Processor Status on Stack.

    Pushes a copy of the status flags onto the stack.

    Note:
        The status flags are pushed with the B flag (bit 4) set to 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#PHP
    """
    # Push the status register. The B-flag bit (0x10) is always set when pushed
    # by PHP and BRK.
    cpu.push(cpu.get_P() | 0x10)

cdef void op_PLP(CPU6502 cpu):
    """PLP - Pull Processor Status from Stack.

    Pulls an 8-bit value from the stack and into the processor status
    register.

    Note:
        The B-flag (bit 4) is ignored and not updated in the CPU's flags.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#PLP
    """
    # Pull the status register. The B-flag bit (0x10) is masked out as it
    # does not exist as a real flag in the CPU.
    cpu.set_P(cpu.pop() & ~0x10)

cdef void op_PLA(CPU6502 cpu):
    """PLA - Pull Accumulator from Stack.

    Pulls an 8-bit value from the stack and places it in the accumulator.

    Side Effects:
        - The Zero flag is set if the pulled value is 0.
        - The Negative flag is set if bit 7 of the pulled value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#PLA
    """
    cpu.A = cpu.pop()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_PHA(CPU6502 cpu):
    """PHA - Push Accumulator on Stack.

    Pushes the current value of the accumulator onto the stack.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#PHA
    """
    cpu.push(cpu.A)

cdef void op_BIT(CPU6502 cpu):
    """BIT - Bit Test.

    Tests bits in memory with the accumulator. This instruction modifies
    flags but does not change any registers or memory. It's used to check
    the status of bits in a memory location.

    Its behavior is unique:
    - The Zero (Z) flag is set if the result of a bitwise AND between the
      accumulator and the memory value is zero.
    - The Negative (N) flag is copied directly from bit 7 of the memory value.
    - The Overflow (V) flag is copied directly from bit 6 of the memory value.

    This allows checking multiple external flags (e.g., from PPU registers)
    at once without disturbing the accumulator's value.

    Side Effects:
        - The Zero, Negative, and Overflow flags are updated based on the
          value in memory and the accumulator.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BIT
    """
    # Read the value from the memory location determined by the addressing mode.
    cdef uint8_t val = cpu.address_read()
    # Set the Overflow (V) flag from bit 6 of the memory value.
    cpu.F.overflow = (val & 0x40) > 0
    # Set the Zero (Z) flag if (accumulator AND memory value) is 0.
    cpu.F.zero = (val & cpu.A) == 0
    # Set the Negative (N) flag from bit 7 of the memory value.
    cpu.F.negative = (val & 0x80) > 0

cdef void op_BRANCH(CPU6502 cpu, bint cond):
    """Helper function for all conditional branch instructions.

    Reads a signed 8-bit relative offset and adds it to the Program
    Counter (PC) if the given condition is true.

    Args:
        cpu (CPU6502): The CPU instance to operate on.
        cond (bint): The boolean condition that must be true for the
                     branch to be taken.
    Side Effects:
        - The Program Counter (PC) may be modified.
        - CPU cycles may be added if the branch is taken.
    """
    cdef int8_t offset = cpu.next_sbyte()
    if cond:
        cpu.PC = <uint16_t>(cpu.PC + offset)
        cpu.cycles += 1

cdef void op_JMP(CPU6502 cpu):
    """JMP - Jump.

    Sets the program counter to a new address. Unlike branches, which use a
    relative offset, JMP takes an absolute or indirect absolute address.

    Note:
        The indirect jump `JMP (xxxx)` has a hardware bug. If the low byte
        of the supplied address is $FF, the high byte of the target address
        is fetched from `(xxxx & $FF00)` instead of `(xxxx + 1)`.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#JMP
    """
    cdef uint16_t off
    cdef uint16_t addr_low, addr_high
    
    if cpu.current_instruction == 0x4C: # Absolute JMP
        cpu.PC = cpu.next_word()
    elif cpu.current_instruction == 0x6C: # Indirect JMP
        off = cpu.next_word()
        
        addr_low = cpu.read_byte(off)
        
        # Emulate the hardware bug in indirect JMP
        if (off & 0x00FF) == 0x00FF:
            addr_high = cpu.read_byte(off & 0xFF00)
        else:
            addr_high = cpu.read_byte(off + 1)
            
        cpu.PC = <uint16_t>(addr_low | (addr_high << 8))

cdef void op_BCS(CPU6502 cpu):
    """BCS - Branch if Carry Set.

    Branches if the Carry flag is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BCS
    """
    op_BRANCH(cpu, cpu.F.carry)

cdef void op_BCC(CPU6502 cpu):
    """BCC - Branch if Carry Clear.

    Branches if the Carry flag is 0.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BCC
    """
    op_BRANCH(cpu, not cpu.F.carry)

cdef void op_BEQ(CPU6502 cpu):
    """BEQ - Branch if Equal.

    Branches if the Zero flag is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BEQ
    """
    op_BRANCH(cpu, cpu.F.zero)

cdef void op_BNE(CPU6502 cpu):
    """BNE - Branch if Not Equal.

    Branches if the Zero flag is 0.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BNE
    """
    op_BRANCH(cpu, not cpu.F.zero)

cdef void op_BVS(CPU6502 cpu):
    """BVS - Branch if Overflow Set.

    Branches if the Overflow flag is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BVS
    """
    op_BRANCH(cpu, cpu.F.overflow)

cdef void op_BVC(CPU6502 cpu):
    """BVC - Branch if Overflow Clear.

    Branches if the Overflow flag is 0.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BVC
    """
    op_BRANCH(cpu, not cpu.F.overflow)

cdef void op_BPL(CPU6502 cpu):
    """BPL - Branch if Plus.

    Branches if the Negative flag is 0.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BPL
    """
    op_BRANCH(cpu, not cpu.F.negative)

cdef void op_BMI(CPU6502 cpu):
    """BMI - Branch if Minus.

    Branches if the Negative flag is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BMI
    """
    op_BRANCH(cpu, cpu.F.negative)

cdef void op_STA(CPU6502 cpu):
    """STA - Store Accumulator in Memory.

    Stores the contents of the Accumulator into a memory location.

    Note:
        This operation does not affect any CPU flags.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#STA
    """
    cpu.address_write(cpu.A)

cdef void op_STX(CPU6502 cpu):
    """STX - Store X Register in Memory.

    Stores the contents of the X register into a memory location.

    Note:
        This operation does not affect any CPU flags.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#STX
    """
    cpu.address_write(cpu.X)

cdef void op_STY(CPU6502 cpu):
    """STY - Store Y Register in Memory.

    Stores the contents of the Y register into a memory location.

    Note:
        This operation does not affect any CPU flags.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#STY
    """
    cpu.address_write(cpu.Y)

cdef void op_CLC(CPU6502 cpu):
    """CLC - Clear Carry Flag.

    Sets the Carry flag to 0.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#CLC
    """
    cpu.F.carry = False

cdef void op_SEC(CPU6502 cpu):
    """SEC - Set Carry Flag.

    Sets the Carry flag to 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#SEC
    """
    cpu.F.carry = True

cdef void op_CLI(CPU6502 cpu):
    """CLI - Clear Interrupt Disable Bit.

    Sets the Interrupt Disable flag to 0, enabling hardware interrupts (IRQs).

    Note:
        The effect of this instruction is delayed by one instruction.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#CLI
    """
    cpu.F.interrupts_disabled = False

cdef void op_SEI(CPU6502 cpu):
    """SEI - Set Interrupt Disable Bit.

    Sets the Interrupt Disable flag to 1, disabling hardware interrupts (IRQs).

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#SEI
    """
    cpu.F.interrupts_disabled = True

cdef void op_CLV(CPU6502 cpu):
    """CLV - Clear Overflow Flag.

    Sets the Overflow flag to 0.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#CLV
    """
    cpu.F.overflow = False

cdef void op_CLD(CPU6502 cpu):
    """CLD - Clear Decimal Mode.

    Sets the Decimal Mode flag to 0.

    Note:
        The 2A03 CPU in the NES does not support BCD (Binary-Coded Decimal)
        mode, so this instruction has no effect on arithmetic operations.
        However, the flag itself can still be set and cleared.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#CLD
    """
    cpu.F.decimal_mode = False

cdef void op_SED(CPU6502 cpu):
    """SED - Set Decimal Mode.

    Sets the Decimal Mode flag to 1.

    Note:
        The 2A03 CPU in the NES does not support BCD (Binary-Coded Decimal)
        mode, so this instruction has no effect on arithmetic operations.
        However, the flag itself can still be set and cleared.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#SED
    """
    cpu.F.decimal_mode = True

cdef void op_NOP(CPU6502 cpu):
    """NOP - No Operation.

    This instruction does nothing except waste CPU cycles and advance
    the program counter.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#NOP
    """
    pass

cdef void op_LDA(CPU6502 cpu):
    """LDA - Load Accumulator with Memory.

    Loads a byte of memory into the Accumulator.

    Side Effects:
        - The Zero flag is set if the loaded value is 0.
        - The Negative flag is set if bit 7 of the loaded value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#LDA
    """
    cpu.A = cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_LDY(CPU6502 cpu):
    """LDY - Load Y Register with Memory.

    Loads a byte of memory into the Y register.

    Side Effects:
        - The Zero flag is set if the loaded value is 0.
        - The Negative flag is set if bit 7 of the loaded value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#LDY
    """
    cpu.Y = cpu.address_read()
    cpu.F.zero = (cpu.Y == 0)
    cpu.F.negative = (cpu.Y & 0x80) > 0

cdef void op_LDX(CPU6502 cpu):
    """LDX - Load X Register with Memory.

    Loads a byte of memory into the X register.

    Side Effects:
        - The Zero flag is set if the loaded value is 0.
        - The Negative flag is set if bit 7 of the loaded value is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#LDX
    """
    cpu.X = cpu.address_read()
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0

cdef void op_ORA(CPU6502 cpu):
    """ORA - Bitwise OR with Accumulator.

    Performs a bitwise OR on the Accumulator and a value from memory.
    If either of the corresponding bits is 1, the resulting bit is 1.

    Side Effects:
        - The Zero flag is set if the result is 0.
        - The Negative flag is set if bit 7 of the result is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#ORA
    """
    cpu.A |= cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_AND(CPU6502 cpu):
    """AND - Bitwise AND with Accumulator.

    Performs a bitwise AND on the Accumulator and a value from memory.
    The resulting bit is 1 only if both corresponding bits are 1.

    Side Effects:
        - The Zero flag is set if the result is 0.
        - The Negative flag is set if bit 7 of the result is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#AND
    """
    cpu.A &= cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_EOR(CPU6502 cpu):
    """EOR - Bitwise Exclusive OR with Accumulator.

    Performs a bitwise Exclusive OR (XOR) on the Accumulator and a value
    from memory. The resulting bit is 1 if the corresponding bits are
    different.

    Side Effects:
        - The Zero flag is set if the result is 0.
        - The Negative flag is set if bit 7 of the result is 1.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#EOR
    """
    cpu.A ^= cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_SBC(CPU6502 cpu):
    """SBC - Subtract with Carry.

    Subtracts a value from memory and the inverse of the Carry flag from the
    Accumulator. This is implemented by adding the bitwise inverse of the
    memory value to the accumulator, plus the Carry flag.
    i.e., A = A - M - (1 - C)  ==>  A = A + (~M) + C

    Side Effects:
        - The Accumulator (A) is updated with the result.
        - The Zero flag is set if the result in A is 0.
        - The Negative flag is set if bit 7 of the result is 1.
        - The Carry flag is set if the unsigned result did NOT underflow.
        - The Overflow flag is set if the signed result underflowed.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#SBC
    """
    # Subtraction is implemented as addition with the one's complement of the value.
    cdef uint8_t val = ~cpu.address_read()
    # The rest of the logic is identical to ADC.
    cdef int nA = <int8_t>cpu.A + <int8_t>val + (1 if cpu.F.carry else 0)
    cpu.F.overflow = nA < -128 or nA > 127
    cpu.F.carry = (cpu.A + val + (1 if cpu.F.carry else 0)) > 0xFF
    cpu.A = <uint8_t>(nA & 0xFF)
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_ADC(CPU6502 cpu):
    """ADC - Add with Carry.

    Adds a value from memory and the value of the Carry flag (C) to the
    Accumulator register (A). This is the primary instruction for addition.

    The Carry flag is used to handle multi-byte addition. For example, to add
    two 16-bit numbers, you would first use ADC on the lower 8 bits. If that
    addition overflows (result > 255), the Carry flag is set. Then, you use
    ADC on the upper 8 bits, and the Carry from the first operation is
    automatically included, giving the correct 16-bit result.

    Side Effects:
        - The Accumulator (A) is updated with the result.
        - The Zero flag is set if the result in A is 0.
        - The Negative flag is set if bit 7 of the result is 1.
        - The Carry flag is set if the addition resulted in an unsigned overflow.
        - The Overflow flag is set if the addition resulted in a signed overflow.

    Reference:
        https://www.nesdev.org/wiki/6502_instructions
    """
    # Read the value to add from the memory location determined by the addressing mode.
    cdef uint8_t val = cpu.address_read()
    # Perform the addition in a wider integer type to detect overflows.
    # We treat the 8-bit inputs as signed numbers to correctly calculate the Overflow flag.
    cdef int nA = <int8_t>cpu.A + <int8_t>val + (1 if cpu.F.carry else 0)

    # Set Overflow flag (V): happens if the sign of the result is wrong.
    # e.g., adding two positive numbers gives a negative result, or two negatives give a positive.
    # This check sees if the signed result has gone out of the -128 to 127 range.
    cpu.F.overflow = nA < -128 or nA > 127

    # Set Carry flag (C): happens if the unsigned addition goes past 255.
    cpu.F.carry = (cpu.A + val + (1 if cpu.F.carry else 0)) > 0xFF

    # Store the final 8-bit result back in the accumulator.
    cpu.A = <uint8_t>(nA & 0xFF)

    # Set Zero flag (Z) if the result is 0.
    cpu.F.zero = (cpu.A == 0)
    # Set Negative flag (N) if bit 7 of the result is set.
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_BRK(CPU6502 cpu):
    """BRK - Force Break (Software Interrupt).

    Forces the generation of an interrupt request (IRQ). The program counter
    and processor status are pushed to the stack, then the PC is loaded
    with the IRQ interrupt vector at $FFFE.

    Side Effects:
        - Pushes PC and status register to the stack.
        - Sets the Interrupt Disable flag.
        - Loads PC with the address from the IRQ vector ($FFFE).

    Note:
        The B flag is set in the status that is pushed to the stack. The
        return address pushed is PC+2, effectively making BRK a 2-byte
        opcode, though it is encoded as one.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#BRK
    """
    cpu.next_byte()
    cpu.push_word(cpu.PC)
    cpu.push(cpu.get_P() | 0x10)
    cpu.F.interrupts_disabled = True
    cpu.PC = cpu.read_word(0xFFFE)

cdef void op_CMP(CPU6502 cpu):
    """CMP - Compare Accumulator.

    Compares the contents of the Accumulator with a value from memory.
    This is implemented as a subtraction without storing the result.

    Side Effects:
        - The Carry flag is set if A >= memory.
        - The Zero flag is set if A == memory.
        - The Negative flag is set to bit 7 of the subtraction result.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#CMP
    """
    cdef uint8_t reg = cpu.A
    cdef long d = reg - <int>cpu.address_read()
    cpu.F.negative = (d & 0x80) > 0 and d != 0
    cpu.F.carry = d >= 0
    cpu.F.zero = d == 0

cdef void op_CPX(CPU6502 cpu):
    """CPX - Compare X Register.

    Compares the contents of the X register with a value from memory.
    This is implemented as a subtraction without storing the result.

    Side Effects:
        - The Carry flag is set if X >= memory.
        - The Zero flag is set if X == memory.
        - The Negative flag is set to bit 7 of the subtraction result.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#CPX
    """
    cdef uint8_t reg = cpu.X
    cdef long d = reg - <int>cpu.address_read()
    cpu.F.negative = (d & 0x80) > 0 and d != 0
    cpu.F.carry = d >= 0
    cpu.F.zero = d == 0

cdef void op_CPY(CPU6502 cpu):
    """CPY - Compare Y Register.

    Compares the contents of the Y register with a value from memory.
    This is implemented as a subtraction without storing the result.

    Side Effects:
        - The Carry flag is set if Y >= memory.
        - The Zero flag is set if Y == memory.
        - The Negative flag is set to bit 7 of the subtraction result.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#CPY
    """
    cdef uint8_t reg = cpu.Y
    cdef long d = reg - <int>cpu.address_read()
    cpu.F.negative = (d & 0x80) > 0 and d != 0
    cpu.F.carry = d >= 0
    cpu.F.zero = d == 0

cdef void op_LSR(CPU6502 cpu):
    """LSR - Logical Shift Right.

    Shifts all bits of a memory value one position to the right. Bit 0 is
    moved into the Carry flag, and a 0 is shifted into bit 7. This is
    equivalent to an unsigned division by 2.

    Visual: 0 -> [76543210] -> C

    Side Effects:
        - The Carry flag is set to the value of bit 0.
        - The Zero flag is set if the result is 0.
        - The Negative flag is always cleared to 0.

    Note:
        This is a read-modify-write instruction.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#LSR
    """
    cdef uint8_t val = cpu.address_read()
    cpu.F.carry = (val & 0x01) > 0
    val >>= 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0  # This will always be false
    cpu.address_write(val)

cdef void op_ASL(CPU6502 cpu):
    """ASL - Arithmetic Shift Left.

    Shifts all bits of a memory value one position to the left. Bit 7 is
    moved into the Carry flag, and a 0 is shifted into bit 0. This is
    equivalent to multiplication by 2.

    Visual: C <- [76543210] <- 0

    Side Effects:
        - The Carry flag is set to the original value of bit 7.
        - The Zero flag is set if the result is 0.
        - The Negative flag is set if bit 7 of the result is 1.

    Note:
        This is a read-modify-write instruction.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#ASL
    """
    cdef uint8_t val = cpu.address_read()
    cpu.F.carry = (val & 0x80) > 0
    val <<= 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_ROR(CPU6502 cpu):
    """ROR - Rotate Right.

    Shifts all bits of a memory value one position to the right. Bit 0 is
    moved into the Carry flag, and the original value of the Carry flag is
    moved into bit 7.

    Visual: C -> [76543210] -> C

    Side Effects:
        - The Carry flag is set to the original value of bit 0.
        - The Zero flag is set if the result is 0.
        - The Negative flag is set if bit 7 of the result is 1 (i.e., if
          the old Carry flag was 1).

    Note:
        This is a read-modify-write instruction.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#ROR
    """
    cdef uint8_t val = cpu.address_read()
    cdef bint c = cpu.F.carry
    cpu.F.carry = (val & 0x01) > 0
    val >>= 1
    if c:
        val |= 0x80
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_ROL(CPU6502 cpu):
    """ROL - Rotate Left.

    Shifts all bits of a memory value one position to the left. Bit 7 is
    moved into the Carry flag, and the original value of the Carry flag is
    moved into bit 0.

    Visual: C <- [76543210] <- C

    Side Effects:
        - The Carry flag is set to the original value of bit 7.
        - The Zero flag is set if the result is 0.
        - The Negative flag is set if bit 7 of the result is 1.

    Note:
        This is a read-modify-write instruction.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#ROL
    """
    cdef uint8_t val = cpu.address_read()
    cdef bint c = cpu.F.carry
    cpu.F.carry = (val & 0x80) > 0
    val <<= 1
    if c:
        val |= 0x01
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_INC(CPU6502 cpu):
    """INC - Increment Memory.

    Adds one to a value in memory.

    Side Effects:
        - The Zero flag is set if the new value is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Note:
        This is a read-modify-write instruction. It does not affect the
        Carry flag.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#INC
    """
    cdef uint8_t val = cpu.address_read() + 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_DEC(CPU6502 cpu):
    """DEC - Decrement Memory.

    Subtracts one from a value in memory.

    Side Effects:
        - The Zero flag is set if the new value is 0.
        - The Negative flag is set if bit 7 of the new value is 1.

    Note:
        This is a read-modify-write instruction. It does not affect the
        Carry flag.

    Reference:
        https://www.nesdev.org/wiki/Instruction_reference#DEC
    """
    cdef uint8_t val = cpu.address_read() - 1
    cpu.F.zero = (val == 0)
    cpu.F.negative = (val & 0x80) > 0
    cpu.address_write(val)

cdef void op_SKB(CPU6502 cpu):
    """SKB - Unofficial Opcode (NOP).

    This is an unofficial no-operation instruction that reads an immediate
    byte but does nothing with it, effectively acting as a 2-byte NOP.

    Reference:
        https://www.nesdev.org/wiki/CPU_unofficial_opcodes
    """
    cpu.next_byte()

cdef void op_ANC(CPU6502 cpu):
    """ANC - Unofficial Opcode (AND + Carry).

    Performs a bitwise AND on the accumulator and a memory value, then sets
    the Carry flag based on the resulting Negative flag.

    Side Effects:
        - The Zero flag is set if the result is 0.
        - The Negative flag is set if bit 7 of the result is 1.
        - The Carry flag is set to the same value as the new Negative flag.

    Reference:
        https://www.nesdev.org/wiki/CPU_unofficial_opcodes
    """
    cpu.A &= cpu.address_read()
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0
    cpu.F.carry = cpu.F.negative

cdef void op_ALR(CPU6502 cpu):
    """ALR - Unofficial Opcode (AND + LSR).

    Performs a bitwise AND on the accumulator and a memory value, then
    performs a Logical Shift Right on the accumulator.

    Side Effects:
        - The Carry flag is set to the value of bit 0 of the AND result.
        - The Zero flag is set if the final result is 0.
        - The Negative flag is cleared.

    Reference:
        https://www.nesdev.org/wiki/CPU_unofficial_opcodes
    """
    cpu.A &= cpu.address_read()
    cpu.F.carry = (cpu.A & 0x01) > 0
    cpu.A >>= 1
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_ARR(CPU6502 cpu):
    """ARR - Unofficial Opcode (AND + ROR).

    Performs a bitwise AND on the accumulator and a memory value, then
    performs a Rotate Right on the accumulator. The flag logic is complex.

    Reference:
        https://www.nesdev.org/wiki/CPU_unofficial_opcodes
    """
    cpu.A &= cpu.address_read()
    cdef bint c = cpu.F.carry
    cpu.F.carry = (cpu.A & 0x01) > 0
    cpu.A >>= 1
    if c:
        cpu.A |= 0x80
    cpu.F.zero = (cpu.A == 0)
    cpu.F.negative = (cpu.A & 0x80) > 0

cdef void op_ATX(CPU6502 cpu):
    """ATX - Unofficial Opcode (LXA/OAL).

    A highly unstable instruction. This implementation loads A with a value
    from memory ANDed with a constant, then transfers A to X.

    Reference:
        https://www.nesdev.org/wiki/CPU_unofficial_opcodes
    """
    cpu.A |= cpu.read_byte(0xEE)
    cpu.A &= cpu.address_read()
    cpu.X = cpu.A
    cpu.F.zero = (cpu.X == 0)
    cpu.F.negative = (cpu.X & 0x80) > 0