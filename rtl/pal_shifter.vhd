library ieee;
    use ieee.std_logic_1164.all;

entity pal_shifter is
    port (
        clock    : in  std_logic;
        data     : in  std_logic_vector(7 downto 0);
        load     : in  std_logic;
        shiftout : out std_logic
    );
end pal_shifter;

architecture behavior of pal_shifter is
    signal sr    : std_logic_vector(7 downto 0);
    signal tick  : std_logic;   -- toggles each clock, shift only on tick='1'
begin
    process(clock)
    begin
        if rising_edge(clock) then
            if load = '1' then
                sr   <= data;
                tick <= '0';    -- reset phase on load
            else
                tick <= not tick;
                if tick = '1' then
                    sr <= sr(6 downto 0) & '0';
                end if;
            end if;
        end if;
    end process;

    shiftout <= sr(7);
end behavior;