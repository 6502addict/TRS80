library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k7_encoder is
    generic (
        CLOCK_PULSE_CYCLES : integer := 3548;   -- same as decoder
        DATA_PULSE_CYCLES  : integer := 1774;
        PULSE_WIDTH_CYCLES : integer := 100     -- how wide each pulse is
    );
    port (
        cpu_clk      : in  std_logic;
        reset_n      : in  std_logic;
        motor        : in  std_logic;
        byte_in      : in  std_logic_vector(7 downto 0);
        byte_strobe  : in  std_logic;           -- push a byte to transmit
        byte_ready   : out std_logic;           -- '1' when ready for next byte
        tape_in      : out std_logic            -- to ff_port
    );
end entity k7_encoder;

architecture rtl of k7_encoder is

    type state_t is (IDLE, CLOCK_PULSE, WAIT_MID_CELL, DATA_PULSE, WAIT_NEXT_CELL);
    signal state       : state_t := IDLE;

    signal shift_reg   : std_logic_vector(7 downto 0) := (others => '0');
    signal bits_left   : unsigned(3 downto 0) := (others => '0');
    signal cycle_count : unsigned(15 downto 0) := (others => '0');
    signal current_bit : std_logic := '0';

begin

    byte_ready <= '1' when (state = IDLE) and (bits_left = 0) else '0';

    process(cpu_clk, reset_n)
    begin
        if reset_n = '0' then
            state       <= IDLE;
            shift_reg   <= (others => '0');
            bits_left   <= (others => '0');
            cycle_count <= (others => '0');
            tape_in     <= '0';
            current_bit <= '0';

        elsif rising_edge(cpu_clk) then

            cycle_count <= cycle_count + 1;

            if motor = '0' then
                state       <= IDLE;
                tape_in     <= '0';
                bits_left   <= (others => '0');
                cycle_count <= (others => '0');
            else
                case state is

                    when IDLE =>
                        tape_in <= '0';
                        if bits_left = 0 and byte_strobe = '1' then
                            -- new byte to send
                            shift_reg <= byte_in;
                            bits_left <= to_unsigned(8, 4);
                        elsif bits_left > 0 then
                            -- start next bit: emit clock pulse
                            current_bit <= shift_reg(7);             -- MSB first
                            shift_reg   <= shift_reg(6 downto 0) & '0';
                            bits_left   <= bits_left - 1;
                            cycle_count <= (others => '0');
                            tape_in     <= '1';
                            state       <= CLOCK_PULSE;
                        end if;

                    when CLOCK_PULSE =>
                        -- hold tape_in high for PULSE_WIDTH_CYCLES
                        if cycle_count >= to_unsigned(PULSE_WIDTH_CYCLES, 16) then
                            tape_in     <= '0';
                            cycle_count <= (others => '0');
                            state       <= WAIT_MID_CELL;
                        end if;

                    when WAIT_MID_CELL =>
                        -- wait until mid-cell (data pulse time)
                        if cycle_count >= to_unsigned(DATA_PULSE_CYCLES - PULSE_WIDTH_CYCLES, 16) then
                            if current_bit = '1' then
                                tape_in     <= '1';
                                cycle_count <= (others => '0');
                                state       <= DATA_PULSE;
                            else
                                -- '0' bit: no data pulse, just wait for end of cell
                                state <= WAIT_NEXT_CELL;
                            end if;
                        end if;

                    when DATA_PULSE =>
                        if cycle_count >= to_unsigned(PULSE_WIDTH_CYCLES, 16) then
                            tape_in     <= '0';
                            cycle_count <= (others => '0');
                            state       <= WAIT_NEXT_CELL;
                        end if;

                    when WAIT_NEXT_CELL =>
                        -- wait until the full cell duration has elapsed
                        -- (time until next clock pulse)
                        if cycle_count >= to_unsigned(CLOCK_PULSE_CYCLES - DATA_PULSE_CYCLES - PULSE_WIDTH_CYCLES, 16) then
                            cycle_count <= (others => '0');
                            state       <= IDLE;
                        end if;

                end case;
            end if;

        end if;
    end process;

end architecture rtl;