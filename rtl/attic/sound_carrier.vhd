library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity sound_carrier is
    port (
        clk     : in  std_logic;  -- 135.5 MHz
        audio   : in  std_logic;  -- 1-bit Apple II sound
        carrier : out std_logic
    );
end sound_carrier;

architecture behavior of sound_carrier is
    -- phase increments for ±50kHz deviation at 135.5 MHz
    -- 67.725 MHz = 67.725/135.5 * 2^32
    -- 67.775 MHz = 67.775/135.5 * 2^32
    constant INC_LO : unsigned(31 downto 0) := to_unsigned(2146894371, 32);
    constant INC_HI : unsigned(31 downto 0) := to_unsigned(2148073924, 32);
    signal phase    : unsigned(31 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if audio = '1' then
                phase <= phase + INC_HI;
            else
                phase <= phase + INC_LO;
            end if;
        end if;
    end process;
    -- MSB of phase accumulator = square wave at target frequency
    carrier <= phase(31);
end behavior;