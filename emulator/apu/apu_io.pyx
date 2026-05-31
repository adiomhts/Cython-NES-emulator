# Glossary (plain-language terms for this APU section):
# - Chunk queue: Short audio blocks buffered for continuous playback.
# - PCM block: Array of integer samples sent to host audio API.
# - Frame sequencer: APU timing unit that clocks envelopes/sweeps/length counters.
# - Register map: CPU-visible control addresses '$4000-$4017'.
# - Host mixer: Audio subsystem provided by pygame used to play generated PCM.
# - Headroom: Intentional output scaling margin to reduce clipping artifacts.
# NESdev references:
# - https://www.nesdev.org/wiki/APU_registers
# - https://www.nesdev.org/wiki/APU_Frame_Counter

# IDE Static Analysis Hints
if not "APU" in globals():
    from apu cimport APU, apu_filter_to_i16, apu_mix_channels, LENGTH_TABLE
    from libc.stdint cimport uint8_t, uint16_t, uint32_t
    import numpy as np
    import pygame
    cimport numpy as cnp


cpdef uint8_t apu_read_status(APU self):
    """Return current APU status register value.

    Args:
        self: Active APU instance.

    Returns:
        uint8_t: Bitfield matching `$4015` status semantics (channel active
        bits and IRQ flags).

    Side Effects:
        Clears frame IRQ flag after read (DMC IRQ flag is not cleared here).

    NESdev references:
        https://www.nesdev.org/wiki/APU
        https://www.nesdev.org/wiki/APU_registers
    """
    cdef uint8_t status

    # Report active length counters and pending IRQ flags.
    status = 0
    if self.pulse_length[0] > 0:
        status |= 0x01
    if self.pulse_length[1] > 0:
        status |= 0x02
    if self.tri_length > 0:
        status |= 0x04
    if self.noise_length > 0:
        status |= 0x08
    if self.dmc_bytes_remaining > 0:
        status |= 0x10
    if self.frame_irq_flag:
        status |= 0x40
    if self.dmc_irq_flag:
        status |= 0x80

    self.frame_irq_flag = 0
    return status


cdef void apu_emit_audio_if_needed(APU self):
    """Flush buffered synthesized samples to host audio backend.

    Args:
        self: Active APU instance.

    Returns:
        None.

    Side Effects:
        Converts internal sample list to PCM chunk, queues/plays it through
        pygame mixer channel, and may clear sample buffer.
    """
    cdef cnp.ndarray[cnp.int16_t, ndim=1] pcm
    cdef object snd, mix_cfg, pcm_out
    cdef object queued

    if not self.audio_ready:
        self.sample_buffer.clear()
        return

    if len(self.sample_buffer) < self.buffer_target:
        return

    if self.audio_channel is not None and self.audio_channel.get_busy() and self.audio_channel.get_queue() is not None:
        return

    pcm = np.asarray(self.sample_buffer, dtype=np.int16)
    self.sample_buffer = []

    try:
        mix_cfg = pygame.mixer.get_init()
        if mix_cfg is not None and len(mix_cfg) >= 3 and int(mix_cfg[2]) == 2:
            pcm_out = np.column_stack((pcm, pcm))
        else:
            pcm_out = pcm

        snd = pygame.sndarray.make_sound(pcm_out)
        if self.audio_channel is None:
            self.audio_channel = pygame.mixer.Channel(0)
            self.audio_channel.set_volume(1.0)
        if self.audio_channel.get_busy():
            queued = self.audio_channel.get_queue()
            if queued is None:
                self.audio_channel.queue(snd)
        else:
            self.audio_channel.play(snd)
    except Exception as e:
        if not self.audio_error_reported:
            self.audio_error_reported = True
            _ = e


def apu_step(APU self, uint32_t cpu_cycles):
    """Advance APU timing and generate mixed audio samples.

    Args:
        self: Active APU instance.
        cpu_cycles: Number of CPU cycles elapsed since previous call.

    Returns:
        None.

    Side Effects:
        Advances frame sequencer and DMC timing, synthesizes channel mix,
        pushes samples into output buffer, and may emit audio chunk.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Frame_Counter
        https://www.nesdev.org/wiki/APU_Mixer
    """
    cdef int sample_i16

    cdef uint32_t i

    self.cycles += cpu_cycles
    self.sample_cycle_acc += cpu_cycles

    # Keep frame-sequencer timing cycle-accurate: a pending $4017 reload can
    # expire mid-instruction, so advancing in a single chunk can shift IRQ/
    # quarter/half events too early or too late.
    for i in range(cpu_cycles):
        self._advance_frame_reload_delay(1)
        self._clock_dmc(1)
        self._clock_frame_counter(1)

    while self.sample_cycle_acc >= self.cycles_per_sample:
        self.sample_cycle_acc -= self.cycles_per_sample

        sample_i16 = apu_filter_to_i16(self, apu_mix_channels(self))
        self.sample_buffer.append(sample_i16)

    self._emit_audio_if_needed()


cpdef void apu_write(APU self, uint16_t addr, uint8_t value):
    """Apply CPU write to APU register map.

    Args:
        self: Active APU instance.
        addr: CPU address in APU register range (`$4000-$4017`).
        value: Raw 8-bit value written by CPU.

    Returns:
        None.

    Side Effects:
        Mutates channel envelope/timer/length state, sweep units, DMC transfer
        parameters, channel enables, and frame-counter mode/reload behavior.

    NESdev references:
        https://www.nesdev.org/wiki/APU_registers
        https://www.nesdev.org/wiki/APU_Frame_Counter
    """
    cdef int ch

    if addr == 0x4000:
        self.pulse_duty[0] = (value >> 6) & 0x03
        self.pulse_constant[0] = 1 if (value & 0x10) else 0
        self.pulse_env_loop[0] = 1 if (value & 0x20) else 0
        self.pulse_volume[0] = value & 0x0F
        return
    elif addr == 0x4002:
        self.pulse_timer[0] = (self.pulse_timer[0] & 0x0700) | value
        return
    elif addr == 0x4003:
        self.pulse_timer[0] = (self.pulse_timer[0] & 0x00FF) | ((value & 0x07) << 8)
        if self.pulse_enabled[0]:
            self.pulse_length[0] = LENGTH_TABLE[(value >> 3) & 0x1F]
        self.pulse_env_start[0] = 1
        self.pulse_phase[0] = 0.0
        return

    elif addr == 0x4001:
        self.pulse_sweep_enable[0] = 1 if (value & 0x80) else 0
        self.pulse_sweep_period[0] = (value >> 4) & 0x07
        self.pulse_sweep_negate[0] = 1 if (value & 0x08) else 0
        self.pulse_sweep_shift[0] = value & 0x07
        self.pulse_sweep_reload[0] = 1
        return

    elif addr == 0x4004:
        self.pulse_duty[1] = (value >> 6) & 0x03
        self.pulse_constant[1] = 1 if (value & 0x10) else 0
        self.pulse_env_loop[1] = 1 if (value & 0x20) else 0
        self.pulse_volume[1] = value & 0x0F
        return
    elif addr == 0x4006:
        self.pulse_timer[1] = (self.pulse_timer[1] & 0x0700) | value
        return
    elif addr == 0x4007:
        self.pulse_timer[1] = (self.pulse_timer[1] & 0x00FF) | ((value & 0x07) << 8)
        if self.pulse_enabled[1]:
            self.pulse_length[1] = LENGTH_TABLE[(value >> 3) & 0x1F]
        self.pulse_env_start[1] = 1
        self.pulse_phase[1] = 0.0
        return

    elif addr == 0x4005:
        self.pulse_sweep_enable[1] = 1 if (value & 0x80) else 0
        self.pulse_sweep_period[1] = (value >> 4) & 0x07
        self.pulse_sweep_negate[1] = 1 if (value & 0x08) else 0
        self.pulse_sweep_shift[1] = value & 0x07
        self.pulse_sweep_reload[1] = 1
        return

    elif addr == 0x4008:
        self.tri_control = 1 if (value & 0x80) else 0
        self.tri_linear_reload = value & 0x7F
        return
    elif addr == 0x400A:
        self.tri_timer = (self.tri_timer & 0x0700) | value
        return
    elif addr == 0x400B:
        self.tri_timer = (self.tri_timer & 0x00FF) | ((value & 0x07) << 8)
        if self.tri_enabled:
            self.tri_length = LENGTH_TABLE[(value >> 3) & 0x1F]
        self.tri_reload_flag = 1
        self.tri_phase = 0.0
        return

    elif addr == 0x400C:
        self.noise_env_loop = 1 if (value & 0x20) else 0
        self.noise_constant = 1 if (value & 0x10) else 0
        self.noise_volume = value & 0x0F
        return
    elif addr == 0x400E:
        self.noise_mode = 1 if (value & 0x80) else 0
        self.noise_period_idx = value & 0x0F
        return
    elif addr == 0x400F:
        if self.noise_enabled:
            self.noise_length = LENGTH_TABLE[(value >> 3) & 0x1F]
        self.noise_env_start = 1
        return

    elif addr == 0x4010:
        self.dmc_irq_enable = 1 if (value & 0x80) else 0
        if self.dmc_irq_enable == 0:
            self.dmc_irq_flag = 0
        self.dmc_loop = 1 if (value & 0x40) else 0
        self.dmc_rate_idx = value & 0x0F
        return
    elif addr == 0x4011:
        self.dmc_output_level = value & 0x7F
        return
    elif addr == 0x4012:
        self.dmc_sample_addr = <uint16_t>(0xC000 + (value * 64))
        return
    elif addr == 0x4013:
        self.dmc_sample_len = <uint16_t>(value * 16 + 1)
        return

    elif addr == 0x4015:
        self.dmc_irq_flag = 0
        for ch in range(2):
            self.pulse_enabled[ch] = 1 if (value & (1 << ch)) else 0
            if self.pulse_enabled[ch] == 0:
                self.pulse_length[ch] = 0
        self.tri_enabled = 1 if (value & 0x04) else 0
        if self.tri_enabled == 0:
            self.tri_length = 0
        self.noise_enabled = 1 if (value & 0x08) else 0
        if self.noise_enabled == 0:
            self.noise_length = 0
        self.dmc_enabled = 1 if (value & 0x10) else 0
        if self.dmc_enabled:
            if self.dmc_bytes_remaining == 0:
                self.dmc_cur_addr = self.dmc_sample_addr
                self.dmc_bytes_remaining = self.dmc_sample_len
                self.dmc_bits_remaining = 4
                self.dmc_cycle_acc = -4.0
                self._dmc_fetch_byte()
        else:
            self.dmc_bytes_remaining = 0
        return

    elif addr == 0x4017:
        self.frame_last_write = value
        self.frame_irq_inhibit = 1 if (value & 0x40) else 0
        if self.frame_irq_inhibit:
            self.frame_irq_flag = 0
            self.frame_irq_retrigger = 0
        self.frame_reload_pending = 1
        self.frame_reload_mode_5step = 1 if (value & 0x80) else 0
        self.frame_reload_delay = 3 if (self.cycles & 1) else 4
        return
