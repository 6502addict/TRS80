library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity clock_multiplier is
generic(
    CLK_HZ      : natural := 50_000_000; -- horloge rapide
    MULT        : natural := 2           -- facteur multiplication
);
port(
    clk_50m     : in  std_logic;
    reset_n     : in  std_logic;
    f_in        : in  std_logic;         -- 0 à 2 MHz
    f_out       : out std_logic          -- f_in * MULT
);
end clock_multiplier;

architecture rtl of clock_multiplier is
    signal f_in_d1, f_in_d2 : std_logic := '0';
    signal rising_edge_in   : std_logic;
    
    signal period_cnt   : unsigned(31 downto 0) := (others=>'0');
    signal period_latched : unsigned(31 downto 0) := to_unsigned(CLK_HZ, 32);
    
    signal acc          : unsigned(31 downto 0) := (others=>'0');
    signal toggle       : std_logic := '0';
begin
    -- Détection front montant de f_in
    process(clk_50m)
    begin
        if rising_edge(clk_50m) then
            f_in_d1 <= f_in;
            f_in_d2 <= f_in_d1;
        end if;
    end process;
    rising_edge_in <= f_in_d1 and not f_in_d2;
    
    -- Mesure de période
    process(clk_50m)
    begin
        if rising_edge(clk_50m) then
            if reset_n = '0' then
                period_cnt <= (others=>'0');
                period_latched <= to_unsigned(CLK_HZ, 32); -- 1Hz par défaut
            elsif rising_edge_in = '1' then
                period_latched <= period_cnt;
                period_cnt <= (others=>'0');
            else
                period_cnt <= period_cnt + 1;
            end if;
        end if;
    end process;
    
    -- Générateur DDS : acc += MULT, overflow = toggle
    process(clk_50m)
    variable step : unsigned(31 downto 0);
    begin
        if rising_edge(clk_50m) then
            if reset_n = '0' then
                acc <= (others=>'0');
                toggle <= '0';
            else
                -- step = MULT * 2^32 / period_latched
                -- Pour éviter la division : on fait acc += MULT
                -- et on compare à period_latched/2 pour le toggle
                acc <= acc + MULT;
                if acc >= period_latched then
                    acc <= acc - period_latched;
                    toggle <= not toggle;
                end if;
            end if;
        end if;
    end process;
    
    f_out <= toggle;
end rtl;
