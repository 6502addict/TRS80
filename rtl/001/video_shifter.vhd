library ieee;
    use ieee.std_logic_1164.all;

entity video_shifter is
    port (
        clock    : in  std_logic;
        mode80   : in  std_logic;                     -- ctrl(0): '1'=80col '0'=40col
        data     : in  std_logic_vector(7 downto 0);
        load     : in  std_logic;
        shiftout : out std_logic
    );
end video_shifter;

architecture behavior of video_shifter is
    signal sr      : std_logic_vector(15 downto 0);
    signal sr_data : std_logic_vector(15 downto 0);
begin
    -- 80col: 8 bits in high half, zeros in low half
    -- 40col: each bit doubled MSB first
    sr_data <= data & x"00" when mode80 = '1' else
               data(7) & data(7) & data(6) & data(6) &
               data(5) & data(5) & data(4) & data(4) &
               data(3) & data(3) & data(2) & data(2) &
               data(1) & data(1) & data(0) & data(0);

    process(clock)
    begin
        if rising_edge(clock) then
            if load = '1' then
                sr <= sr_data;
            else
                sr <= sr(14 downto 0) & '0';
            end if;
        end if;
    end process;

    shiftout <= sr(15);
end behavior;

