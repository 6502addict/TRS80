library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity std_ram is
    generic (
        ADDR_BITS : positive := 16
    );
    port (
        address : in  std_logic_vector(ADDR_BITS -1 downto 0);
        clock   : in  std_logic;
        data    : in  std_logic_vector(7 downto 0);
        wren    : in  std_logic := '0';
        q       : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of std_ram is

    type ram_t is array(0 to 2**ADDR_BITS-1) of std_logic_vector(7 downto 0);
    signal ram : ram_t;

    attribute ram_init_file : string;
    attribute ram_init_file of ram : signal is "none";

begin
    process(clock)
    begin
        if rising_edge(clock) then
            if wren = '1' then
                ram(to_integer(unsigned(address))) <= data;
            end if;
            q <= ram(to_integer(unsigned(address)));
        end if;
    end process;

end rtl;