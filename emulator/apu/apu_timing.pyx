# Glossary (plain-language terms for this APU section):
# - Quarter-frame clock: Step that updates envelopes/linear counter.
# - Half-frame clock: Step that updates length counters and sweeps.
# - Reload delay: Hardware delay before new frame-counter mode applies.
# - DMC transfer: Byte/bit pipeline reading CPU memory for sample playback.
# - Sequencer event point: Specific CPU-cycle position where quarter/half clocks fire.
# - IRQ flag: Latch bit indicating APU requests CPU interrupt handling.
# - Sample buffer: One-byte holding register used by DMC before shift playback.
# - Looping sample: DMC mode where playback restarts from initial address/length.
# NESdev references:
# - https://www.nesdev.org/wiki/APU_Frame_Counter
# - https://www.nesdev.org/wiki/APU_DMC

# IDE Static Analysis Hints
# IDE Static Analysis Hints
if not "APU" in globals():
    from apu cimport APU, DMC_RATE_TABLE
    from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef void apu_dmc_fetch_byte(APU self):
    """Fetch one DMC byte from CPU memory into DMC sample buffer.

    Args:
        self: Active APU instance.

    Returns:
        None.

    Side Effects:
        Reads memory at current DMC address, updates buffer-empty state,
        increments/wraps source address, decrements remaining length, and may
        restart looping sample or raise DMC IRQ when stream ends.

    NESdev references:
        https://www.nesdev.org/wiki/APU_DMC
    """
    cdef int addr
    cdef object mem

    if self.dmc_bytes_remaining == 0:
        return
    if self.dmc_sample_buffer_empty == 0:
        return
    if self.cpu is None:
        return

    try:
        mem = self.cpu.memory
        addr = self.dmc_cur_addr & 0xFFFF
        self.dmc_sample_buffer = <uint8_t>int(mem[addr])
        self.dmc_sample_buffer_empty = 0
    except Exception:
        self.dmc_sample_buffer = 0
        self.dmc_sample_buffer_empty = 0

    self.dmc_cur_addr = <uint16_t>((self.dmc_cur_addr + 1) & 0xFFFF)
    if self.dmc_cur_addr < 0x8000:
        self.dmc_cur_addr = 0x8000

    if self.dmc_bytes_remaining > 0:
        self.dmc_bytes_remaining -= 1

    if self.dmc_bytes_remaining == 0 and self.dmc_loop:
        self.dmc_cur_addr = self.dmc_sample_addr
        self.dmc_bytes_remaining = self.dmc_sample_len
    elif self.dmc_bytes_remaining == 0 and self.dmc_irq_enable:
        self.dmc_irq_flag = 1
        if self.cpu is not None:
            try:
                self.cpu.trigger_interrupt(1)
            except Exception:
                pass


cdef void apu_clock_dmc(APU self, uint32_t cpu_cycles):
    """Advance DMC bit playback by elapsed CPU cycles.

    Args:
        self: Active APU instance.
        cpu_cycles: Number of CPU cycles to process.

    Returns:
        None.

    Side Effects:
        Consumes DMC timing accumulator, shifts playback bits, adjusts DMC DAC
        output level, and triggers source-byte fetches when the shift register drains.

    NESdev references:
        https://www.nesdev.org/wiki/APU_DMC
    """
    cdef int period

    if self.dmc_enabled == 0:
        return

    period = DMC_RATE_TABLE[self.dmc_rate_idx & 0x0F]
    self.dmc_cycle_acc += cpu_cycles

    while self.dmc_cycle_acc >= period:
        self.dmc_cycle_acc -= period

        if self.dmc_bits_remaining == 0:
            if self.dmc_sample_buffer_empty == 0:
                self.dmc_shift_reg = self.dmc_sample_buffer
                self.dmc_sample_buffer_empty = 1
                self.dmc_bits_remaining = 8
            else:
                self.dmc_bits_remaining = 8

        if self.dmc_bits_remaining > 0:
            if self.dmc_shift_reg & 1:
                if self.dmc_output_level <= 125:
                    self.dmc_output_level += 2
            else:
                if self.dmc_output_level >= 2:
                    self.dmc_output_level -= 2

            self.dmc_shift_reg >>= 1
            self.dmc_bits_remaining -= 1

        apu_dmc_fetch_byte(self)


cdef void apu_clock_quarter_frame(APU self):
    """Clock quarter-frame units (envelopes and triangle linear counter).

    Args:
        self: Active APU instance.

    Returns:
        None.

    Side Effects:
        Updates pulse/noise envelope dividers/decay counters and triangle
        linear-counter reload/decrement behavior according to current control bits.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Frame_Counter
        https://www.nesdev.org/wiki/APU_Envelope
    """
    cdef int ch

    for ch in range(2):
        if self.pulse_env_start[ch]:
            self.pulse_env_start[ch] = 0
            self.pulse_env_decay[ch] = 15
            self.pulse_env_divider[ch] = self.pulse_volume[ch]
        else:
            if self.pulse_env_divider[ch] == 0:
                self.pulse_env_divider[ch] = self.pulse_volume[ch]
                if self.pulse_env_decay[ch] > 0:
                    self.pulse_env_decay[ch] -= 1
                elif self.pulse_env_loop[ch]:
                    self.pulse_env_decay[ch] = 15
            else:
                self.pulse_env_divider[ch] -= 1

    if self.tri_reload_flag:
        self.tri_linear_counter = self.tri_linear_reload
    elif self.tri_linear_counter > 0:
        self.tri_linear_counter -= 1

    if self.tri_control == 0:
        self.tri_reload_flag = 0

    if self.noise_env_start:
        self.noise_env_start = 0
        self.noise_env_decay = 15
        self.noise_env_divider = self.noise_volume
    else:
        if self.noise_env_divider == 0:
            self.noise_env_divider = self.noise_volume
            if self.noise_env_decay > 0:
                self.noise_env_decay -= 1
            elif self.noise_env_loop:
                self.noise_env_decay = 15
        else:
            self.noise_env_divider -= 1


cdef void apu_clock_half_frame(APU self):
    """Clock half-frame units (length counters and pulse sweep).

    Args:
        self: Active APU instance.

    Returns:
        None.

    Side Effects:
        Decrements enabled length counters, advances/loads sweep dividers,
        and conditionally applies pulse timer sweep arithmetic.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Frame_Counter
        https://www.nesdev.org/wiki/APU_Sweep
    """
    cdef int ch, delta, target

    for ch in range(2):
        if self.pulse_env_loop[ch] == 0 and self.pulse_length[ch] > 0:
            self.pulse_length[ch] -= 1

        if self.pulse_sweep_reload[ch]:
            self.pulse_sweep_divider[ch] = self.pulse_sweep_period[ch]
            self.pulse_sweep_reload[ch] = 0
        else:
            if self.pulse_sweep_divider[ch] > 0:
                self.pulse_sweep_divider[ch] -= 1
            else:
                self.pulse_sweep_divider[ch] = self.pulse_sweep_period[ch]
                if self.pulse_sweep_enable[ch] and self.pulse_sweep_shift[ch] > 0:
                    if self.pulse_timer[ch] >= 8:
                        delta = self.pulse_timer[ch] >> self.pulse_sweep_shift[ch]
                        if self.pulse_sweep_negate[ch]:
                            if ch == 0:
                                target = self.pulse_timer[ch] - delta - 1
                            else:
                                target = self.pulse_timer[ch] - delta
                        else:
                            target = self.pulse_timer[ch] + delta
                        if 0 <= target <= 0x7FF:
                            self.pulse_timer[ch] = <uint16_t>target

    if self.tri_control == 0 and self.tri_length > 0:
        self.tri_length -= 1

    if self.noise_env_loop == 0 and self.noise_length > 0:
        self.noise_length -= 1


cdef void apu_clock_frame_counter(APU self, uint32_t cpu_cycles):
    """Advance frame sequencer and fire quarter/half-frame events.

    Args:
        self: Active APU instance.
        cpu_cycles: Number of elapsed CPU cycles.

    Returns:
        None.

    Side Effects:
        Moves frame sequencer cursor, clocks quarter/half units at event points,
        wraps sequence position, and may assert frame IRQ in 4-step mode.

    Notes:
        Event timing uses CPU-cycle checkpoints (not APU half-cycles), so
        quarter/half-frame clocks occur near 7457/14913/22371/29829 in 4-step
        mode and near 7457/14913/22371/37281 in 5-step mode.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Frame_Counter
    """
    cdef int seq_len, e1, e2, e3, e4, h2, h4
    cdef int old_pos, new_pos, step, remaining

    if self.frame_mode_5step:
        seq_len = 37282
        e1 = 7457
        e2 = 14913
        e3 = 22371
        e4 = 37281
        h2 = 14914
        h4 = 37282
    else:
        seq_len = 29830
        e1 = 7457
        e2 = 14913
        e3 = 22371
        e4 = 29829
        h2 = 14914
        h4 = 29830

    remaining = <int>cpu_cycles
    while remaining > 0:
        if self.frame_mode_5step == 0 and self.frame_irq_inhibit == 0 and self.frame_irq_retrigger > 0:
            self.frame_irq_flag = 1
            self.frame_irq_retrigger -= 1

        old_pos = self.frame_cycle_pos
        step = seq_len - old_pos
        if step > remaining:
            step = remaining
        new_pos = old_pos + step

        if old_pos < e1 <= new_pos:
            apu_clock_quarter_frame(self)
        if old_pos < e2 <= new_pos:
            apu_clock_quarter_frame(self)
        if old_pos < e3 <= new_pos:
            apu_clock_quarter_frame(self)
        if old_pos < e4 <= new_pos:
            apu_clock_quarter_frame(self)

        if old_pos < h2 <= new_pos:
            apu_clock_half_frame(self)
        if old_pos < h4 <= new_pos:
            apu_clock_half_frame(self)

        if self.frame_mode_5step == 0 and old_pos < e4 <= new_pos and self.frame_irq_inhibit == 0:
            self.frame_irq_flag = 1
            self.frame_irq_retrigger = 2
            if self.cpu is not None:
                try:
                    self.cpu.trigger_interrupt(1)
                except Exception:
                    pass

        if new_pos >= seq_len:
            self.frame_cycle_pos = 0
        else:
            self.frame_cycle_pos = new_pos

        remaining -= step


cdef void apu_advance_frame_reload_delay(APU self, uint32_t cpu_cycles):
    """Apply delayed frame-counter mode reload after `$4017` write.

    Args:
        self: Active APU instance.
        cpu_cycles: Number of elapsed CPU cycles.

    Returns:
        None.

    Side Effects:
        Decrements pending reload delay, commits new 4-step/5-step mode when
        delay expires, resets frame cursor, and clocks immediate quarter+half
        ticks in 5-step mode.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Frame_Counter
    """
    if self.frame_reload_pending == 0:
        return

    self.frame_reload_delay -= <int>cpu_cycles
    if self.frame_reload_delay > 0:
        return

    self.frame_reload_pending = 0
    self.frame_mode_5step = self.frame_reload_mode_5step
    self.frame_cycle_pos = 0

    if self.frame_mode_5step:
        apu_clock_quarter_frame(self)
        apu_clock_half_frame(self)
