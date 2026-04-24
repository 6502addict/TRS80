library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity ff_port is
    port (
        clk         : in  std_logic;                       
        reset_n     : in  std_logic;
        cs_n        : in  std_logic;                       
        rd_n        : in  std_logic;                       
        wr_n        : in  std_logic;                       
        data_in     : in  std_logic_vector(7 downto 0);    
        data_out    : out std_logic_vector(7 downto 0);    
        tape_in     : in  std_logic;
        tape_out    : out std_logic_vector(1 downto 0);
        motor       : out std_logic;      
        video_mode  : out std_logic
    );
end entity ff_port;

architecture rtl of ff_port is
begin
    process(reset_n, clk)
    begin
        if reset_n = '0' then
            tape_out   <= "00";  -- no signal
            motor      <= '0';   -- motor off
            video_mode <= '0';   -- 64 col 
        elsif rising_edge(clk) then
            if cs_n = '0' and wr_n = '0' then
                tape_out   <= data_in(1 downto 0);
                motor      <= data_in(2);
                video_mode <= data_in(3); 
            end if;
        end if;
    end process;
    
    process(clk)
    begin
        if rising_edge(clk) then
            if cs_n = '0' and rd_n = '0' then
                data_out <= tape_in & "1111111";
            end if;
        end if;
    end process;

end architecture rtl;