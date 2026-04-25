library ieee;
    use ieee.std_logic_1164.all;

-- =============================================================================
-- Module  : trs80_shifter
-- Purpose : Serialize character ROM data into pixel stream
--
-- Always shifts once per clock. The mode selection is done at load time by
-- duplicating or quadruplicating each source pixel in sr_data:
--   mode = '0' : 64 col — 6 source pixels (bits 7..2) each doubled = 12 bits used
--   mode = '1' : 32 col — 6 source pixels (bits 7..2) each quadrupled = 24 bits used
-- In both modes, one character takes the same number of pixel clocks as
-- char_w configured in video_ctrl (12 clocks for 64-col, 24 clocks for 32-col).
--
-- bits 1..0 of data are zero padding in the 2513 ROM and are discarded.
-- =============================================================================

entity trs80_shifter is
    port (
        clock    : in  std_logic;
        reset_n  : in  std_logic;
        mode     : in  std_logic;                      -- '0' = 64col, '1' = 32col
        data     : in  std_logic_vector(7 downto 0);
        load     : in  std_logic;
        shiftout : out std_logic
    );
end trs80_shifter;

architecture behavior of trs80_shifter is
    signal sr       : std_logic_vector(11 downto 0);
    signal sr_data  : std_logic_vector(11 downto 0);
    signal shift_en : std_logic := '0';
    
begin
    -- 64col: 6 source pixels each doubled = 12 used bits, 12 zero padding bits
--    sr_data <= data(7) & data(7) & data(6) & data(6) & data(5) & data(5) & data(4) & data(4) &  data(3) & data(3) & data(2) & data(2); 
-- MCM6670P: 6 pixels in bits 5..0 (bit5 always 0 = gap), each doubled for 64col
    sr_data <= data(5) & data(5) &   -- always 0 = inter-character gap
               data(4) & data(4) & 
               data(3) & data(3) & 
               data(2) & data(2) & 
               data(1) & data(1) & 
               data(0) & data(0);

    
    -- Process to generate the enable pulse
    process(clock)
    begin
        if rising_edge(clock) then
            if mode = '0' then
                shift_en <= '1';      -- 64-col: Shift every clock cycle
            else
                shift_en <= not shift_en; -- 32-col: Shift every OTHER clock cycle
            end if;
        end if;
    end process;    
    
    process(clock)
    begin
        if rising_edge(clock) then
            if load = '1' then
                sr <= sr_data;
            elsif shift_en = '1' then
                sr <= sr(10 downto 0) & '0'; -- Assuming a 12-bit shifter
            end if;
        end if;
    end process;    

    shiftout <= sr(11);

end behavior;
