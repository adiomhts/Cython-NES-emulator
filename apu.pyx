import numpy as np
import pygame
cimport numpy as cnp
from libc.stdint cimport uint8_t, uint16_t, uint32_t


cdef class APU:
    cdef uint32_t cycles
    cdef double cpu_clock_hz
    cdef int sample_rate
    cdef double cycles_per_sample
    cdef double sample_cycle_acc

    # Pulse channel state (2 channels)
    cdef uint8_t pulse_enabled[2]
    cdef uint8_t pulse_duty[2]
    cdef uint8_t pulse_volume[2]
    cdef uint16_t pulse_timer[2]
    cdef double pulse_phase[2]

    # Audio output state
    cdef bint audio_ready
    cdef object audio_channel
    cdef object sample_buffer
    cdef int buffer_target

    def __init__(self):
        self.cycles = 0
        self.cpu_clock_hz = 1789773.0
        self.sample_rate = 44100
        self.cycles_per_sample = self.cpu_clock_hz / self.sample_rate
        self.sample_cycle_acc = 0.0

        self.pulse_enabled[0] = 0
        self.pulse_enabled[1] = 0
        self.pulse_duty[0] = 0
        self.pulse_duty[1] = 0
        self.pulse_volume[0] = 0
        self.pulse_volume[1] = 0
        self.pulse_timer[0] = 0
        self.pulse_timer[1] = 0
        self.pulse_phase[0] = 0.0
        self.pulse_phase[1] = 0.0

        self.audio_ready = False
        self.audio_channel = None
        self.sample_buffer = []
        self.buffer_target = 1024

        # Mixer init is best-effort: emulator must still run headless/no-audio.
        try:
            if not pygame.mixer.get_init():
                pygame.mixer.init(frequency=self.sample_rate, size=-16, channels=1, buffer=512)
            self.audio_channel = pygame.mixer.Channel(0)
            self.audio_ready = True
        except Exception:
            self.audio_ready = False
            self.audio_channel = None

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
        cdef uint16_t timer

        if self.pulse_enabled[ch] == 0:
            return 0.0

        timer = self.pulse_timer[ch]
        if timer < 8:
            return 0.0

        vol = self.pulse_volume[ch] / 15.0
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

    cdef void _emit_audio_if_needed(self):
        cdef cnp.ndarray[cnp.int16_t, ndim=1] pcm
        cdef object snd

        if not self.audio_ready:
            self.sample_buffer.clear()
            return

        if len(self.sample_buffer) < self.buffer_target:
            return

        pcm = np.asarray(self.sample_buffer, dtype=np.int16)
        self.sample_buffer = []

        try:
            snd = pygame.sndarray.make_sound(pcm)
            if self.audio_channel is None:
                self.audio_channel = pygame.mixer.Channel(0)
            if self.audio_channel.get_busy():
                self.audio_channel.queue(snd)
            else:
                self.audio_channel.play(snd)
        except Exception:
            # If audio backend glitches, keep emulation alive.
            pass

    def step(self, uint32_t cpu_cycles):
        cdef double mix
        cdef int sample_i16

        self.cycles += cpu_cycles
        self.sample_cycle_acc += cpu_cycles

        while self.sample_cycle_acc >= self.cycles_per_sample:
            self.sample_cycle_acc -= self.cycles_per_sample

            # Baseline mix: two pulse channels. This is intentionally simple and
            # will be replaced with more accurate frame-counter/envelope mixing.
            mix = self._pulse_sample(0) + self._pulse_sample(1)

            if mix > 1.0:
                mix = 1.0
            elif mix < -1.0:
                mix = -1.0

            sample_i16 = <int>(mix * 9000.0)
            self.sample_buffer.append(sample_i16)

        self._emit_audio_if_needed()

    cpdef public void write(self, uint16_t addr, uint8_t value):
        cdef int ch

        # Pulse 1
        if addr == 0x4000:
            self.pulse_duty[0] = (value >> 6) & 0x03
            self.pulse_volume[0] = value & 0x0F
            return
        elif addr == 0x4002:
            self.pulse_timer[0] = (self.pulse_timer[0] & 0x0700) | value
            return
        elif addr == 0x4003:
            self.pulse_timer[0] = (self.pulse_timer[0] & 0x00FF) | ((value & 0x07) << 8)
            self.pulse_phase[0] = 0.0
            return

        # Pulse 2
        elif addr == 0x4004:
            self.pulse_duty[1] = (value >> 6) & 0x03
            self.pulse_volume[1] = value & 0x0F
            return
        elif addr == 0x4006:
            self.pulse_timer[1] = (self.pulse_timer[1] & 0x0700) | value
            return
        elif addr == 0x4007:
            self.pulse_timer[1] = (self.pulse_timer[1] & 0x00FF) | ((value & 0x07) << 8)
            self.pulse_phase[1] = 0.0
            return

        # Channel enables
        elif addr == 0x4015:
            for ch in range(2):
                self.pulse_enabled[ch] = 1 if (value & (1 << ch)) else 0
            return

        # Frame counter write (not fully modeled yet)
        elif addr == 0x4017:
            return