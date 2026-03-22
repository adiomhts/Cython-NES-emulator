# Glossary (plain-language terms for this APU section):
# - Duty ratio: Fraction of pulse period spent at high level.
# - Envelope output: Current volume value produced by envelope unit.
# - Bipolar sample: Audio sample centered around zero (positive/negative).
# - Phase accumulator: Running position inside waveform cycle.
# - Muted channel: Voice currently producing zero output due to rules/flags.
# - Timer period: Hardware divider value controlling waveform frequency.
# - Sweep target: New pulse timer value produced by sweep arithmetic.
# - LFSR: Shift-register noise generator where feedback bits create pseudo-random tone.
# - DAC level: Numeric output amplitude before host-side filtering/scaling.
# NESdev references:
# - https://www.nesdev.org/wiki/APU_Pulse
# - https://www.nesdev.org/wiki/APU_Triangle
# - https://www.nesdev.org/wiki/APU_Noise
# - https://www.nesdev.org/wiki/APU_DMC

cdef double apu_duty_ratio(APU self, int duty_idx):
    """Convert pulse duty index into normalized high-level ratio.

    Args:
        self: Active APU instance (unused directly, passed for uniform helper API).
        duty_idx: Hardware duty selector from pulse control register (`0..3`).

    Returns:
        double: Fraction of one pulse cycle that stays in high state.

    Side Effects:
        None.

    Notes:
        NES pulse channels use predefined duty patterns. This helper maps those
        patterns to approximate high-time ratios suitable for analytic synthesis.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Pulse
    """
    # NES pulse duty sequences reduced to average high-time ratios.
    if duty_idx == 0:
        return 0.125
    elif duty_idx == 1:
        return 0.25
    elif duty_idx == 2:
        return 0.5
    return 0.75


cdef double apu_pulse_sample(APU self, int ch):
    """Synthesize one pulse-channel sample in host-sample domain.

    Args:
        self: Active APU instance.
        ch: Pulse channel index (`0` for pulse 1, `1` for pulse 2).

    Returns:
        double: Bipolar pulse sample approximately in range `[-1.0, 1.0]`.

    Side Effects:
        Advances `pulse_phase[ch]` and may early-mute output based on timer,
        length counter, sweep overflow rules, and envelope state.

    Notes:
        The implementation intentionally uses a compact analytic waveform model
        while preserving the key NES muting/sweep constraints required by many games.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Pulse
        https://www.nesdev.org/wiki/APU_Sweep
    """
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

    duty = apu_duty_ratio(self, self.pulse_duty[ch])
    if self.pulse_phase[ch] < duty:
        return vol
    return -vol


cdef double apu_tri_sample(APU self):
    """Synthesize one triangle-channel sample.

    Args:
        self: Active APU instance.

    Returns:
        double: Triangle waveform sample scaled to mixer-friendly amplitude.

    Side Effects:
        Advances triangle phase when channel is active and not muted by timer,
        length counter, or linear counter gating.

    Notes:
        Triangle output is generated as an analytic approximation, which is
        easier to maintain than table-driven edges while staying musically close.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Triangle
    """
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


cdef double apu_noise_sample(APU self):
    """Synthesize one noise-channel sample using LFSR state.

    Args:
        self: Active APU instance.

    Returns:
        double: Noise contribution for current output sample.

    Side Effects:
        Advances `noise_phase`, clocks LFSR when needed, and reads envelope/
        length state to decide whether output is muted.

    Notes:
        Bit tap selection follows NES short/normal mode behavior (`bit6` vs `bit1`).

    NESdev references:
        https://www.nesdev.org/wiki/APU_Noise
    """
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


cdef double apu_dmc_sample(APU self):
    """Convert DMC DAC level to centered mixer contribution.

    Args:
        self: Active APU instance.

    Returns:
        double: Scaled DMC sample contribution centered around zero.

    Side Effects:
        None.

    NESdev references:
        https://www.nesdev.org/wiki/APU_DMC
    """
    # Convert 7-bit DMC DAC level to centered audio contribution.
    return (self.dmc_output_level / 127.0) * 0.4 - 0.2
