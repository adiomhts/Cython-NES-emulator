from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef class APU:
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
    cdef uint8_t frame_last_write
    cdef uint8_t frame_irq_inhibit
    cdef uint8_t frame_irq_flag
    cdef uint8_t frame_irq_retrigger
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

    cdef double _duty_ratio(self, int duty_idx)
    cdef double _pulse_sample(self, int ch)
    cdef double _tri_sample(self)
    cdef double _noise_sample(self)
    cdef void _dmc_fetch_byte(self)
    cdef void _clock_dmc(self, uint32_t cpu_cycles)
    cdef double _dmc_sample(self)
    cdef void _clock_quarter_frame(self)
    cdef void _clock_half_frame(self)
    cdef void _clock_frame_counter(self, uint32_t cpu_cycles)
    cdef void _advance_frame_reload_delay(self, uint32_t cpu_cycles)
    cdef void _power_on_init(self)
    cdef void _console_reset(self)
    cpdef public uint8_t read_status(self)
    cdef void _emit_audio_if_needed(self)
    cpdef public void write(self, uint16_t addr, uint8_t value)
    cpdef public void reset(self)
