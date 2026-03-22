import numpy as np
import pygame
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, uint32_t

# Glossary (terms used in comments/docstrings in this file):
# - APU: Audio Processing Unit.
# - DMC: Delta Modulation Channel (sample playback channel in NES APU).
# - IRQ: Interrupt Request (maskable CPU interrupt line).
# - Frame counter: APU sequencer clocking envelopes/length/sweep units.
# - Envelope: Automatic volume decay/gating unit per channel.
# - Length counter: Per-channel timer that mutes voice when it reaches zero.
# - Sweep unit: Hardware pitch shifter for pulse channels.
# - LFSR: Linear Feedback Shift Register (noise generation core).
# - DAC: Digital-to-Analog Converter output level (modeled numerically here).
# - PCM: Pulse-Code Modulation sample buffer sent to host audio mixer.
# - Mixer: Formula combining all APU voices into one output sample.
# - DC offset: Constant bias in waveform level; filtered before playback.
# NESdev references:
# - https://www.nesdev.org/wiki/APU
# - https://www.nesdev.org/wiki/APU_registers
# - https://www.nesdev.org/wiki/APU_Frame_Counter
# - https://www.nesdev.org/wiki/APU_DMC

LENGTH_TABLE = (
    10, 254, 20, 2, 40, 4, 80, 6,
    160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30,
)

# Length lookup used when games write length index bits in channel registers.

NOISE_PERIOD_TABLE = (
    4, 8, 16, 32, 64, 96, 128, 160,
    202, 254, 380, 508, 762, 1016, 2034, 4068,
)

# Noise period lookup converting register index -> timer period.

DMC_RATE_TABLE = (
    428, 380, 340, 320, 286, 254, 226, 214,
    190, 160, 142, 128, 106, 84, 72, 54,
)

# DMC fetch/update cadence lookup (CPU cycles per bit step).


cdef class APU:
    """NES APU mixer with pulse, triangle, noise, DMC and frame-counter clocks.

    Implements channel register state machines and periodic sample emission to
    host audio backend.

    NESdev references:
    - https://www.nesdev.org/wiki/APU
    - https://www.nesdev.org/wiki/APU_registers
    - https://www.nesdev.org/wiki/APU_Frame_Counter
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

        NESdev references:
            https://www.nesdev.org/wiki/APU
            https://www.nesdev.org/wiki/APU_registers
        """
        # Global APU timing and sample-rate conversion state.
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
            # Bring up host audio backend if not already initialized.
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
            # Fail softly: keep emulation running without audio output.
            self.audio_ready = False
            self.audio_channel = None
            _ = e

    cdef double _duty_ratio(self, int duty_idx):
        """Delegate pulse duty conversion to channel helper module.

        Args:
            duty_idx: Pulse duty selector index (`0..3`).

        Returns:
            double: High-time ratio for the selected duty pattern.
        """
        return apu_duty_ratio(self, duty_idx)

    cdef double _pulse_sample(self, int ch):
        """Delegate pulse synthesis to channel helper module.

        Args:
            ch: Pulse channel index (`0` or `1`).

        Returns:
            double: Synthesized pulse sample contribution.
        """
        return apu_pulse_sample(self, ch)

    cdef double _tri_sample(self):
        """Delegate triangle synthesis to channel helper module.

        Args:
            None.

        Returns:
            double: Synthesized triangle sample contribution.

        Side Effects:
            May advance internal triangle phase and consume current channel
            gating state through delegated helper logic.
        """
        return apu_tri_sample(self)

    cdef double _noise_sample(self):
        """Delegate noise synthesis to channel helper module.

        Args:
            None.

        Returns:
            double: Synthesized noise sample contribution.

        Side Effects:
            May advance LFSR/phase state and consume envelope/length gates via
            delegated helper logic.
        """
        return apu_noise_sample(self)

    cdef void _dmc_fetch_byte(self):
        """Delegate DMC byte-fetch pipeline to timing helper module.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            May read CPU memory, update DMC address/remaining counters, and
            potentially assert DMC IRQ conditions.
        """
        apu_dmc_fetch_byte(self)

    cdef void _clock_dmc(self, uint32_t cpu_cycles):
        """Delegate DMC timing clock to timing helper module.

        Args:
            cpu_cycles: Number of CPU cycles to process.

        Returns:
            None.

        Side Effects:
            Advances DMC bit timing and output level through delegated helper logic.
        """
        apu_clock_dmc(self, cpu_cycles)

    cdef double _dmc_sample(self):
        """Delegate DMC sample conversion to channel helper module.

        Returns:
            double: DMC contribution centered near zero.
        """
        return apu_dmc_sample(self)

    cdef void _clock_quarter_frame(self):
        """Delegate quarter-frame clock to timing helper module.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Updates envelope and linear-counter state through delegated logic.
        """
        apu_clock_quarter_frame(self)

    cdef void _clock_half_frame(self):
        """Delegate half-frame clock to timing helper module.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            Updates length counters and sweep units through delegated logic.
        """
        apu_clock_half_frame(self)

    cdef void _clock_frame_counter(self, uint32_t cpu_cycles):
        """Delegate frame-counter sequencing to timing helper module.

        Args:
            cpu_cycles: Number of elapsed CPU cycles.

        Returns:
            None.

        Side Effects:
            Advances sequence cursor and can set frame IRQ latch via helper logic.
        """
        apu_clock_frame_counter(self, cpu_cycles)

    cdef void _advance_frame_reload_delay(self, uint32_t cpu_cycles):
        """Delegate delayed frame-reload application to timing helper module.

        Args:
            cpu_cycles: Number of elapsed CPU cycles.

        Returns:
            None.

        Side Effects:
            May commit pending `$4017` mode reload and trigger immediate clocks
            in 5-step mode through delegated helper logic.
        """
        apu_advance_frame_reload_delay(self, cpu_cycles)

    cpdef public uint8_t read_status(self):
        """Delegate status-register read semantics to IO helper module.

        Args:
            None.

        Returns:
            uint8_t: `$4015`-compatible channel/IRQ status bitfield.

        Side Effects:
            Mirrors hardware-like latch clearing behavior implemented in helper.
        """
        return apu_read_status(self)

    cdef void _emit_audio_if_needed(self):
        """Delegate host-audio queue/emit to IO helper module.

        Args:
            None.

        Returns:
            None.

        Side Effects:
            May convert internal sample buffer to PCM and queue/play it via
            pygame mixer channel.
        """
        apu_emit_audio_if_needed(self)

    def step(self, uint32_t cpu_cycles):
        """Advance APU timing and emit samples via modular IO pipeline.

        Args:
            cpu_cycles: Number of CPU cycles elapsed since previous call.

        Returns:
            None.
        """
        apu_step(self, cpu_cycles)

    cpdef public void write(self, uint16_t addr, uint8_t value):
        """Delegate APU register-write semantics to IO helper module.

        Args:
            addr: CPU address in APU register space.
            value: Raw 8-bit value written by CPU.

        Returns:
            None.
        """
        apu_write(self, addr, value)


include "apu_channels.pyx"
include "apu_timing.pyx"
include "apu_signal.pyx"
include "apu_io.pyx"