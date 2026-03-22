# Glossary (plain-language terms for this APU section):
# - Mixer sum: Arithmetic combination of all enabled channel samples.
# - High-pass filter: Removes slow DC bias so output centers near zero.
# - Low-pass filter: Smooths sharp digital edges to reduce harsh alias-like tone.
# - Saturation: Clamping sample range to avoid numeric overflow/distortion.
# - PCM int16: 16-bit signed integer format used by common audio APIs.
# NESdev references:
# - https://www.nesdev.org/wiki/APU_Mixer
# - https://www.nesdev.org/wiki/APU

cdef double apu_mix_channels(APU self):
    """Compute mixed APU sample from all channel generators.

    Args:
        self: Active APU instance.

    Returns:
        double: Mixed sample in approximate range `[-1.0, 1.0]`.

    Side Effects:
        Indirectly advances per-channel phase where channel helper methods do so.

    Notes:
        This helper centralizes channel summation and hard clipping. It keeps
        `apu_step` focused on timing and buffer management.

    NESdev references:
        https://www.nesdev.org/wiki/APU_Mixer
    """
    cdef double mix

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

    return mix


cdef int apu_filter_to_i16(APU self, double mix):
    """Apply simple DC/high-pass + low-pass chain and convert to int16.

    Args:
        self: Active APU instance.
        mix: Input mixed sample expected in `[-1.0, 1.0]`.

    Returns:
        int: Signed 16-bit style sample value (stored as Python/C int here).

    Side Effects:
        Updates filter state accumulators (`hp_prev_in`, `hp_prev_out`, `lp_prev`).

    Notes:
        The constants are pragmatic tuning values aimed at stable, pleasant output
        with low computational overhead for realtime emulation.
    """
    cdef double filtered

    filtered = mix - self.hp_prev_in + (0.995 * self.hp_prev_out)
    self.hp_prev_in = mix
    self.hp_prev_out = filtered

    self.lp_prev += 0.18 * (filtered - self.lp_prev)

    if self.lp_prev > 1.0:
        self.lp_prev = 1.0
    elif self.lp_prev < -1.0:
        self.lp_prev = -1.0

    return <int>(self.lp_prev * 9000.0)
