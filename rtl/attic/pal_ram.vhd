library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    use IEEE.math_real.all;

entity pal_ram is
    generic (
        SIZE_BYTES : positive := 512
    );
    port (
        address_a : in  std_logic_vector(integer(ceil(log2(real(SIZE_BYTES))))-1 downto 0);
        address_b : in  std_logic_vector(integer(ceil(log2(real(SIZE_BYTES))))-1 downto 0);
        clock_a   : in  std_logic;
        clock_b   : in  std_logic;
        data_a    : in  std_logic_vector(7 downto 0);
        data_b    : in  std_logic_vector(7 downto 0);
        rden_a    : in  std_logic := '1';
        rden_b    : in  std_logic := '1';
        wren_a    : in  std_logic := '0';
        wren_b    : in  std_logic := '0';
        q_a       : out std_logic_vector(7 downto 0);
        q_b       : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of pal_ram is
    type ram_t is array(0 to SIZE_BYTES-1) of std_logic_vector(7 downto 0);
    shared variable ram : ram_t; -- Use shared variable for dual-process RAM in some tools, 
                                 -- or keep as signal if your compiler prefers it.
begin
    -- Port A: Standard Sync Read
    process(clock_a)
    begin
        if rising_edge(clock_a) then
            if wren_a = '1' then
                ram(to_integer(unsigned(address_a))) := data_a;
            end if;
            -- Read-After-Write: This usually infers "Write-First" behavior
            -- Move this ABOVE the 'if wren_a' to infer "Read-First" (Old Data)
            if rden_a = '1' then
                q_a <= ram(to_integer(unsigned(address_a)));
            end if;
        end if;
    end process;

    -- Port B: Standard Sync Read
    process(clock_b)
    begin
        if rising_edge(clock_b) then
            if wren_b = '1' then
                ram(to_integer(unsigned(address_b))) := data_b;
            end if;
            if rden_b = '1' then
                q_b <= ram(to_integer(unsigned(address_b)));
            end if;
        end if;
    end process;
end rtl;
