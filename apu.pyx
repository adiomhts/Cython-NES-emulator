import numpy as np
import pygame
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, uint32_t

LENGTH_TABLE = (
    10, 254, 20, 2, 40, 4, 80, 6,
    160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30,
)

NOISE_PERIOD_TABLE = (
    4, 8, 16, 32, 64, 96, 128, 160,
    202, 254, 380, 508, 762, 1016, 2034, 4068,
)

DMC_RATE_TABLE = (
    428, 380, 340, 320, 286, 254, 226, 214,
    190, 160, 142, 128, 106, 84, 72, 54,
)


cdef class APU:
    """NES APU mixer with pulse, triangle, noise, DMC and frame-counter clocks.

    Implements channel register state machines and periodic sample emission to
    host audio backend.
    """

    cdef public object cpu
    cdef uint32_t cycles
    cdef double cpu_clock_hz
    cdef int sample_rate
    cdef int mixer_channels
    cdef double cycles_per_sample
    cdef double sample_cycle_acc
    cdef int frame_mode_5step
    cdef int frame_cycle_pos
    cdef int frame_reload_pending
    cdef int frame_reload_delay
    cdef int frame_reload_mode_5step
    cdef uint8_t frame_irq_inhibit
    cdef uint8_t frame_irq_flag
    cdef uint8_t dmc_irq_flag

    cdef uint8_t pulse_enabled[2]
    cdef uint8_t pulse_duty[2]
    cdef uint8_t pulse_volume[2]
    cdef uint8_t pulse_constant[2]
    cdef uint8_t pulse_env_loop[2]
    cdef uint8_t pulse_env_start[2]
    cdef uint8_t pulse_env_divider[2]
    cdef uint8_t pulse_env_decay[2]
    cdef uint8_t pulse_length[2]
    cdef uint8_t pulse_sweep_enable[2]
    cdef uint8_t pulse_sweep_period[2]
    cdef uint8_t pulse_sweep_negate[2]
    cdef uint8_t pulse_sweep_shift[2]
    cdef uint8_t pulse_sweep_reload[2]
    cdef uint8_t pulse_sweep_divider[2]
    cdef uint16_t pulse_timer[2]
    cdef double pulse_phase[2]

    cdef uint8_t tri_enabled
    cdef uint8_t tri_control
    cdef uint8_t tri_linear_reload
    cdef uint8_t tri_linear_counter
    cdef uint8_t tri_reload_flag
    cdef uint8_t tri_length
    cdef uint16_t tri_timer
    cdef double tri_phase

    cdef uint8_t noise_enabled
    cdef uint8_t noise_constant
    cdef uint8_t noise_env_loop
    cdef uint8_t noise_volume
    cdef uint8_t noise_env_start
    cdef uint8_t noise_env_divider
    cdef uint8_t noise_env_decay
    cdef uint8_t noise_length
    cdef uint8_t noise_mode
    cdef uint8_t noise_period_idx
    cdef uint16_t noise_shift_reg
    cdef double noise_phase

    cdef uint8_t dmc_enabled
    cdef uint8_t dmc_loop
    cdef uint8_t dmc_irq_enable
    cdef uint8_t dmc_rate_idx
    cdef uint8_t dmc_output_level
    cdef uint16_t dmc_sample_addr
    cdef uint16_t dmc_cur_addr
    cdef uint16_t dmc_sample_len
    cdef uint16_t dmc_bytes_remaining
    cdef uint8_t dmc_shift_reg
    cdef uint8_t dmc_bits_remaining
    cdef uint8_t dmc_sample_buffer
    cdef uint8_t dmc_sample_buffer_empty
    cdef double dmc_cycle_acc

    cdef bint audio_ready
    cdef bint audio_error_reported
    cdef object audio_channel
    cdef object sample_buffer
    cdef int buffer_target
    cdef double hp_prev_in
    cdef double hp_prev_out
    cdef double lp_prev

    def __init__(self):
        """Initialize APU channel state and host audio backend.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Resets all APU channel/frame-counter state, allocates sample buffer,
            and attempts to initialize pygame mixer/channel.

        Raises:
            No exception is propagated for audio init failures; backend errors
            are swallowed to keep emulation running headless.
        """
        self.cycles = 0
        self.cpu = None
        self.cpu_clock_hz = 1789772.7272727273
        self.sample_rate = 44100
        self.mixer_channels = 1
        self.cycles_per_sample = self.cpu_clock_hz / self.sample_rate
        self.sample_cycle_acc = 0.0
        self.frame_mode_5step = 0
        self.frame_cycle_pos = 0
        self.frame_reload_pending = 0
        self.frame_reload_delay = 0
        self.frame_reload_mode_5step = 0
        self.frame_irq_inhibit = 0
        self.frame_irq_flag = 0
        self.dmc_irq_flag = 0

        self.pulse_enabled[0] = 0
        self.pulse_enabled[1] = 0
        self.pulse_duty[0] = 0
        self.pulse_duty[1] = 0
        self.pulse_volume[0] = 0
        self.pulse_volume[1] = 0
        self.pulse_constant[0] = 0
        self.pulse_constant[1] = 0
        self.pulse_env_loop[0] = 0
        self.pulse_env_loop[1] = 0
        self.pulse_env_start[0] = 0
        self.pulse_env_start[1] = 0
        self.pulse_env_divider[0] = 0
        self.pulse_env_divider[1] = 0
        self.pulse_env_decay[0] = 0
        self.pulse_env_decay[1] = 0
        self.pulse_length[0] = 0
        self.pulse_length[1] = 0
        self.pulse_sweep_enable[0] = 0
        self.pulse_sweep_enable[1] = 0
        self.pulse_sweep_period[0] = 0
        self.pulse_sweep_period[1] = 0
        self.pulse_sweep_negate[0] = 0
        self.pulse_sweep_negate[1] = 0
        self.pulse_sweep_shift[0] = 0
        self.pulse_sweep_shift[1] = 0
        self.pulse_sweep_reload[0] = 0
        self.pulse_sweep_reload[1] = 0
        self.pulse_sweep_divider[0] = 0
        self.pulse_sweep_divider[1] = 0
        self.pulse_timer[0] = 0
        self.pulse_timer[1] = 0
        self.pulse_phase[0] = 0.0
        self.pulse_phase[1] = 0.0

        self.tri_enabled = 0
        self.tri_control = 0
        self.tri_linear_reload = 0
        self.tri_linear_counter = 0
        self.tri_reload_flag = 0
        self.tri_length = 0
        self.tri_timer = 0
        self.tri_phase = 0.0

        self.noise_enabled = 0
        self.noise_constant = 0
        self.noise_env_loop = 0
        self.noise_volume = 0
        self.noise_env_start = 0
        self.noise_env_divider = 0
        self.noise_env_decay = 0
        self.noise_length = 0
        self.noise_mode = 0
        self.noise_period_idx = 0
        self.noise_shift_reg = 1
        self.noise_phase = 0.0

        self.dmc_enabled = 0
        self.dmc_loop = 0
        self.dmc_irq_enable = 0
        self.dmc_rate_idx = 0
        self.dmc_output_level = 0
        self.dmc_sample_addr = 0xC000
        self.dmc_cur_addr = 0xC000
        self.dmc_sample_len = 1
        self.dmc_bytes_remaining = 0
        self.dmc_shift_reg = 0
        self.dmc_bits_remaining = 8
        self.dmc_sample_buffer = 0
        self.dmc_sample_buffer_empty = 1
        self.dmc_cycle_acc = 0.0

        self.audio_ready = False
        self.audio_error_reported = False
        self.audio_channel = None
        self.sample_buffer = []
        self.buffer_target = 2048
        self.hp_prev_in = 0.0
        self.hp_prev_out = 0.0
        self.lp_prev = 0.0

        try:
            if not pygame.mixer.get_init():
                pygame.mixer.init(frequency=self.sample_rate, size=-16, channels=1, buffer=512)
            mix_cfg = pygame.mixer.get_init()
            if mix_cfg is not None and len(mix_cfg) >= 3:
                self.sample_rate = int(mix_cfg[0])
                self.mixer_channels = int(mix_cfg[2])
                self.cycles_per_sample = self.cpu_clock_hz / self.sample_rate
            self.audio_channel = pygame.mixer.Channel(0)
            self.audio_channel.set_volume(1.0)
            self.audio_ready = True
        except Exception as e:
            self.audio_ready = False
            self.audio_channel = None
            _ = e

    cdef double _duty_ratio(self, int duty_idx):
        if duty_idx == 0:
            return 0.125
        elif duty_idx == 1:
            return 0.25
        elif duty_idx == 2:
            return 0.5
        return 0.75

    cdef double _pulse_sample(self, int ch):
        cdef double freq, duty, vol, step
        cdef uint8_t env_out
        cdef uint16_t timer
        cdef int delta, target

        if self.pulse_enabled[ch] == 0:
            return 0.0
        if self.pulse_length[ch] == 0:
            return 0.0

        timer = self.pulse_timer[ch]
        if timer < 8:
            return 0.0

        if self.pulse_sweep_shift[ch] > 0:
            delta = timer >> self.pulse_sweep_shift[ch]
            if self.pulse_sweep_negate[ch]:
                if ch == 0:
                    target = timer - delta - 1
                else:
                    target = timer - delta
            else:
                target = timer + delta
            if target < 0 or target > 0x7FF:
                return 0.0

        if self.pulse_constant[ch]:
            env_out = self.pulse_volume[ch]
        else:
            env_out = self.pulse_env_decay[ch]

        vol = env_out / 15.0

        if vol <= 0.0:
            return 0.0

        freq = self.cpu_clock_hz / (16.0 * (timer + 1.0))
        step = freq / self.sample_rate
        self.pulse_phase[ch] += step
        if self.pulse_phase[ch] >= 1.0:
            self.pulse_phase[ch] -= <int>self.pulse_phase[ch]

        duty = self._duty_ratio(self.pulse_duty[ch])
        if self.pulse_phase[ch] < duty:
            return vol
        return -vol

    cdef double _tri_sample(self):
        cdef double freq, step, amp, tri

        if self.tri_enabled == 0:
            return 0.0
        if self.tri_timer < 2:
            return 0.0
        if self.tri_length == 0:
            return 0.0
        if self.tri_linear_counter == 0:
            return 0.0

        freq = self.cpu_clock_hz / (32.0 * (self.tri_timer + 1.0))
        step = freq / self.sample_rate
        self.tri_phase += step
        if self.tri_phase >= 1.0:
            self.tri_phase -= <int>self.tri_phase

        tri = 1.0 - 4.0 * abs(self.tri_phase - 0.5)
        amp = 0.35
        return tri * amp

    cdef double _noise_sample(self):
        cdef double freq, step, vol
        cdef uint8_t env_out
        cdef int period
        cdef uint16_t feedback

        if self.noise_enabled == 0:
            return 0.0
        if self.noise_length == 0:
            return 0.0

        if self.noise_constant:
            env_out = self.noise_volume
        else:
            env_out = self.noise_env_decay

        vol = env_out / 15.0
        if vol <= 0.0:
            return 0.0

        period = NOISE_PERIOD_TABLE[self.noise_period_idx & 0x0F]
        if period <= 0:
            return 0.0

        freq = self.cpu_clock_hz / period
        step = freq / self.sample_rate
        self.noise_phase += step

        while self.noise_phase >= 1.0:
            self.noise_phase -= 1.0
            if self.noise_mode:
                feedback = (self.noise_shift_reg ^ (self.noise_shift_reg >> 6)) & 1
            else:
                feedback = (self.noise_shift_reg ^ (self.noise_shift_reg >> 1)) & 1
            self.noise_shift_reg = (self.noise_shift_reg >> 1) | (feedback << 14)

        if self.noise_shift_reg & 1:
            return 0.0
        return (vol - 0.5) * 0.8

    cdef void _dmc_fetch_byte(self):
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

    cdef void _clock_dmc(self, uint32_t cpu_cycles):
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

            self._dmc_fetch_byte()

    cdef double _dmc_sample(self):
        return (self.dmc_output_level / 127.0) * 0.4 - 0.2

    cdef void _clock_quarter_frame(self):
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

    cdef void _clock_half_frame(self):
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

    cdef void _clock_frame_counter(self, uint32_t cpu_cycles):
        cdef int seq_len, e1, e2, e3, e4
        cdef int old_pos, new_pos, step, remaining

        if self.frame_mode_5step:
            seq_len = 18641
            e1 = 3729
            e2 = 7457
            e3 = 11186
            e4 = 18641
        else:
            seq_len = 14915
            e1 = 3729
            e2 = 7457
            e3 = 11186
            e4 = 14915

        remaining = <int>cpu_cycles
        while remaining > 0:
            old_pos = self.frame_cycle_pos
            step = seq_len - old_pos
            if step > remaining:
                step = remaining
            new_pos = old_pos + step

            if old_pos < e1 <= new_pos:
                self._clock_quarter_frame()
            if old_pos < e2 <= new_pos:
                self._clock_quarter_frame()
            if old_pos < e3 <= new_pos:
                self._clock_quarter_frame()
            if old_pos < e4 <= new_pos:
                self._clock_quarter_frame()

            if old_pos < e2 <= new_pos:
                self._clock_half_frame()
            if old_pos < e4 <= new_pos:
                self._clock_half_frame()

            if self.frame_mode_5step == 0 and old_pos < e4 <= new_pos and self.frame_irq_inhibit == 0:
                self.frame_irq_flag = 1
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

    cdef void _advance_frame_reload_delay(self, uint32_t cpu_cycles):
        if self.frame_reload_pending == 0:
            return

        self.frame_reload_delay -= <int>cpu_cycles
        if self.frame_reload_delay > 0:
            return

        self.frame_reload_pending = 0
        self.frame_mode_5step = self.frame_reload_mode_5step
        self.frame_cycle_pos = 0

        if self.frame_mode_5step:
            self._clock_quarter_frame()
            self._clock_half_frame()

    cpdef public uint8_t read_status(self):
        cdef uint8_t status

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

    cdef void _emit_audio_if_needed(self):
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

    def step(self, uint32_t cpu_cycles):
        """Advance APU timing and synthesize audio samples.

        Args:
            cpu_cycles: Number of CPU cycles elapsed since previous call.

        Returns:
            None.

        Side Effects:
            Advances frame counter and channel clocks, appends synthesized PCM
            samples to internal buffer, and may queue/play audio chunks.
        """
        cdef double mix
        cdef double filtered
        cdef int sample_i16

        self.cycles += cpu_cycles
        self.sample_cycle_acc += cpu_cycles
        self._advance_frame_reload_delay(cpu_cycles)
        self._clock_dmc(cpu_cycles)
        self._clock_frame_counter(cpu_cycles)

        while self.sample_cycle_acc >= self.cycles_per_sample:
            self.sample_cycle_acc -= self.cycles_per_sample

            mix = (
                self._pulse_sample(0)
                + self._pulse_sample(1)
                + self._tri_sample()
                + self._noise_sample()
                + self._dmc_sample()
            )

            if mix > 1.0:
                mix = 1.0
            elif mix < -1.0:
                mix = -1.0

            filtered = mix - self.hp_prev_in + (0.995 * self.hp_prev_out)
            self.hp_prev_in = mix
            self.hp_prev_out = filtered
            self.lp_prev += 0.18 * (filtered - self.lp_prev)

            if self.lp_prev > 1.0:
                self.lp_prev = 1.0
            elif self.lp_prev < -1.0:
                self.lp_prev = -1.0

            sample_i16 = <int>(self.lp_prev * 9000.0)
            self.sample_buffer.append(sample_i16)

        self._emit_audio_if_needed()

    cpdef public void write(self, uint16_t addr, uint8_t value):
        """Apply CPU register write to APU state.

        Args:
            addr: CPU address in APU register range (`$4000-$4017`).
            value: 8-bit value written by CPU.

        Returns:
            None.

        Side Effects:
            Mutates channel envelopes/timers/length counters, enable bits, DMC
            transfer state, and frame-counter mode/reload timing.
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
            self.noise_length = LENGTH_TABLE[(value >> 3) & 0x1F]
            self.noise_env_start = 1
            return

        elif addr == 0x4010:
            self.dmc_irq_enable = 1 if (value & 0x80) else 0
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
                    self._dmc_fetch_byte()
            else:
                self.dmc_bytes_remaining = 0
            return

        elif addr == 0x4017:
            self.frame_irq_inhibit = 1 if (value & 0x40) else 0
            if self.frame_irq_inhibit:
                self.frame_irq_flag = 0
            self.frame_reload_pending = 1
            self.frame_reload_mode_5step = 1 if (value & 0x80) else 0
            self.frame_reload_delay = 3 if (self.cycles & 1) else 4
            return