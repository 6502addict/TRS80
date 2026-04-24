library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity altair_88_cpa is
    port (
        cpu_clk    : in  std_logic;        -- CPU clock
        reset_n    : in  std_logic;
        cs_n       : in  std_logic;
        rd_n       : in  std_logic;
        wr_n       : in  std_logic;
        data_in    : in  std_logic_vector(7 downto 0);
        data_out   : out std_logic_vector(7 downto 0);
        sw         : in  std_logic_vector(7 downto 0);
        leds       : out std_logic_vector(7 downto 0)
    );
end entity altair_88_cpa;

architecture rtl of altair_88_cpa is

begin

    process(cpu_clk, reset_n)
    begin
        if reset_n = '0' then
            leds     <= x"00";
            data_out <= (others => '0');
        elsif rising_edge(cpu_clk) then
            if cs_n = '0' then
                if wr_n = '0' then   
                    leds <= data_in;
                end if;
                if rd_n = '0' then
                    data_out <= sw;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;