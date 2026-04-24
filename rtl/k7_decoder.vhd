library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================================
-- Module  : k7_decoder
-- Purpose : Decode TRS-80 Model I cassette output (port 0xFF bits 0-1) into a
--           stream of bytes.
-- =============================================================================
--
-- The Model I cassette ROM generates Kansas-City-style waveforms by bit-banging
-- the 2-bit DAC on port 0xFF bits 0-1. Each bit cell is approximately 2000 Z80
-- cycles long. A clock pulse marks the start of every cell; a data pulse in
-- the middle of the cell (at ~1000 cycles) indicates a '1' bit; absence of a
-- data pulse indicates a '0' bit.
--
-- A "pulse" on the DAC output is any transition from "00" (idle) to a non-idle
-- state ("01" or "10"). The polarity doesn't matter for decoding; only the
-- timing of pulses does.
--
-- All timing is measured in cpu_clk cycles, so the decoder automatically
-- follows whatever CPU clock frequency is configured.
--
-- Output: byte_out + byte_strobe (1 cycle pulse when a byte is ready).
--         bit_out  + bit_strobe  (1 cycle pulse each bit, for debug).
--
-- Framing: this version does NOT detect the 0xA5 sync byte; bytes are emitted
-- every 8 decoded bits from the moment motor goes high. You'll see the leader
-- pattern as garbage bytes at the start of each transmission, then the real
-- data. Add sync detection later if needed.
-- =============================================================================

entity k7_decoder is
    generic (
        -- Timing windows in cpu_clk cycles (Level II Model I, 500-baud KCS)
        CLOCK_PULSE_CYCLES : integer := 2000;   -- nominal clock-to-clock interval
        DATA_PULSE_CYCLES  : integer := 1000;   -- nominal clock-to-data interval
        TOLERANCE_CYCLES   : integer := 400;    -- ±20% window
        SILENCE_CYCLES     : integer := 8000    -- 4 cells of silence = end of transmission
    );
    port (
        cpu_clk     : in  std_logic;
        reset_n     : in  std_logic;
        motor       : in  std_logic;                       -- cassette motor on
        tape_out    : in  std_logic_vector(1 downto 0);    -- from ff_port
        bit_out     : out std_logic;                       -- decoded bit value
        bit_strobe  : out std_logic;                       -- 1 cycle pulse per bit
        byte_out    : out std_logic_vector(7 downto 0);    -- decoded byte
        byte_strobe : out std_logic                        -- 1 cycle pulse per byte
    );
end entity k7_decoder;

architecture rtl of k7_decoder is

    -- pulse detection
    signal tape_prev    : std_logic_vector(1 downto 0) := "00";
    signal pulse_event  : std_logic;

    -- cycle counter since last pulse
    signal cycle_count  : unsigned(15 downto 0) := (others => '0');

    -- state machine
    type state_t is (IDLE, IN_CELL, SAW_DATA_PULSE);
    signal state        : state_t := IDLE;

    -- bit accumulator (MSB-first per Model I Level II format)
    signal bit_accum    : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_counter  : unsigned(3 downto 0) := (others => '0');

    -- timing window helpers
    function in_data_window(c : unsigned) return boolean is
    begin
        return (c >= to_unsigned(DATA_PULSE_CYCLES - TOLERANCE_CYCLES, 16))
           and (c <= to_unsigned(DATA_PULSE_CYCLES + TOLERANCE_CYCLES, 16));
    end function;

    function in_clock_window(c : unsigned) return boolean is
    begin
        return (c >= to_unsigned(CLOCK_PULSE_CYCLES - TOLERANCE_CYCLES, 16))
           and (c <= to_unsigned(CLOCK_PULSE_CYCLES + TOLERANCE_CYCLES, 16));
    end function;

begin

    -- pulse detection: transition from "00" to non-"00" on tape_out
    pulse_event <= '1' when (tape_prev = "00") and (tape_out /= "00")
                   else '0';

    process(cpu_clk, reset_n)
        variable current_bit : std_logic;
    begin
        if reset_n = '0' then
            tape_prev    <= "00";
            cycle_count  <= (others => '0');
            state        <= IDLE;
            bit_accum    <= (others => '0');
            bit_counter  <= (others => '0');
            bit_out      <= '0';
            bit_strobe   <= '0';
            byte_out     <= (others => '0');
            byte_strobe  <= '0';

        elsif rising_edge(cpu_clk) then

            -- register tape_out for edge detection
            tape_prev <= tape_out;

            -- default: no strobes this cycle
            bit_strobe  <= '0';
            byte_strobe <= '0';

            -- cycle counter increments every clock; resets on pulse
            if pulse_event = '1' then
                cycle_count <= (others => '0');
            elsif cycle_count < to_unsigned(65535, 16) then
                cycle_count <= cycle_count + 1;
            end if;

            -- state machine
            if motor = '0' then
                -- motor off: reset everything, wait for next transmission
                state       <= IDLE;
                bit_counter <= (others => '0');
                bit_accum   <= (others => '0');
            else
                case state is

                    when IDLE =>
                        -- waiting for first pulse while motor is on
                        if pulse_event = '1' then
                            -- first pulse = clock pulse of first bit cell
                            state <= IN_CELL;
                        end if;

                    when IN_CELL =>
                        -- we're inside a bit cell, waiting for either a data
                        -- pulse (1 ms) or the next clock pulse (2 ms)
                        if pulse_event = '1' then
                            if in_data_window(cycle_count) then
                                -- mid-cell pulse: current bit is '1'
                                state <= SAW_DATA_PULSE;
                            elsif in_clock_window(cycle_count) then
                                -- clock pulse without seeing a data pulse:
                                -- current bit was '0'
                                current_bit := '0';
                                bit_accum <= bit_accum(6 downto 0) & current_bit;
                                bit_out   <= current_bit;
                                bit_strobe <= '1';

                                if bit_counter = 7 then
                                    byte_out    <= bit_accum(6 downto 0) & current_bit;
                                    byte_strobe <= '1';
                                    bit_counter <= (others => '0');
                                else
                                    bit_counter <= bit_counter + 1;
                                end if;
                                -- stay IN_CELL for the next bit
                            end if;
                            -- pulses outside both windows are ignored (glitch)
                        elsif cycle_count > to_unsigned(SILENCE_CYCLES, 16) then
                            -- long silence: end of transmission
                            state       <= IDLE;
                            bit_counter <= (others => '0');
                        end if;

                    when SAW_DATA_PULSE =>
                        -- we saw a data pulse, current bit is '1'; waiting for
                        -- the next clock pulse to close the cell
                        if pulse_event = '1' then
                            -- should be the clock pulse of the next cell
                            current_bit := '1';
                            bit_accum <= bit_accum(6 downto 0) & current_bit;
                            bit_out   <= current_bit;
                            bit_strobe <= '1';

                            if bit_counter = 7 then
                                byte_out    <= bit_accum(6 downto 0) & current_bit;
                                byte_strobe <= '1';
                                bit_counter <= (others => '0');
                            else
                                bit_counter <= bit_counter + 1;
                            end if;

                            state <= IN_CELL;
                        elsif cycle_count > to_unsigned(SILENCE_CYCLES, 16) then
                            state       <= IDLE;
                            bit_counter <= (others => '0');
                        end if;

                end case;
            end if;

        end if;
    end process;

end architecture rtl;