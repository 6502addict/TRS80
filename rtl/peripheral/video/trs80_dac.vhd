-- =============================================================================
-- File    : trs80_dac.vhd
-- Version : 1.1
-- Date    : 2026-04-25
-- Author  : didier
-- Changes : 1.0 - Initial version
-- =============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity trs80_dac is
    port(
        clock       : in  std_logic;
        enable      : in  std_logic;
        blank       : in  std_logic;
        pixel       : in  std_logic;
        rgb         : out std_logic_vector(11 downto 0)
    );
end trs80_dac;

architecture behavior of trs80_dac is
    signal rgb_reg : std_logic_vector(11 downto 0);
    
begin
    rgb_reg <= x"FFF" when (enable = '1') and (blank = '0') and (pixel = '1') else x"000";

    process(clock)
    begin
        if rising_edge(clock) then
            rgb <= rgb_reg;
        end if;
    end process;
    
end behavior;


