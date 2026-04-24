library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity trs80_fdc is
    port (
        -- Master Side (Z80 / TRS-80)
        m_clk          : in  std_logic;
        m_reset_n      : in  std_logic;
        m_ds_cs_n      : in  std_logic;                    -- cs drive select register
        m_cs_n         : in  std_logic;                    -- cs 1771
        m_address      : in  std_logic_vector(1 downto 0); -- 37EC-37EF
        m_wr_n         : in  std_logic;
        m_rd_n         : in  std_logic;
        m_data_in      : in  std_logic_vector(7 downto 0);
        m_data_out     : out std_logic_vector(7 downto 0);

        -- Slave Side (6502 / IOP)
        s_clk          : in  std_logic;
        s_reset_n      : in  std_logic;
        s_cs_n         : in  std_logic;
        s_address      : in  std_logic_vector(2 downto 0);
        s_rw           : in  std_logic;
        s_data_in      : in  std_logic_vector(7 downto 0);
        s_data_out     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of trs80_fdc is
    -- Internal WD1771 Registers
    signal command : std_logic_vector(7 downto 0) := x"00";
    signal status  : std_logic_vector(7 downto 0) := x"00";
    signal track   : std_logic_vector(7 downto 0) := x"00";
    signal sector  : std_logic_vector(7 downto 0) := x"00";
    signal data    : std_logic_vector(7 downto 0) := x"00";
    signal drvsel  : std_logic_vector(7 downto 0) := x"00";

    --  bit 7 new command written
    signal trigger : std_logic_vector(7 downto 0) := x"00";
    --- bit 7      motor on/off
    --  bit 0..6   rotation speed en hz
    signal rotation : std_logic_vector(7 downto 0) := x"00";
    
begin

    process(m_clk, m_reset_n, s_reset_n)
    begin
        if m_reset_n = '0' or s_reset_n = '0' then
            command <= x"00"; 
            status  <= x"00"; 
            track   <= x"00";
            sector  <= x"00";
            data    <= x"00";
            drvsel  <= x"00";
            trigger <= x"00";
            
        elsif rising_edge(m_clk) then
            
            -- ============================
            -- MASTER SIDE: Z80 WRITE LOGIC
            -- ============================
            if m_ds_cs_n = '0' and m_wr_n = '0' then
                drvsel <= m_data_in;
            end if;
            if m_cs_n = '0' and m_wr_n = '0' then
                case m_address is
                    when "00" => -- Command
                        command <= m_data_in;
                        trigger(7) <= '1'; -- Trigger 6502 command
                        status(0) <= '1'; -- Set WD1771 BUSY bit immediately

                    when "01" => -- Track
                        track <= m_data_in;

                    when "10" => -- Sector
                        sector <= m_data_in;
                        
                    when "11" => -- Data
                        data <= m_data_in;
                        trigger(6) <= '1'; -- Trigger 6502 data

                    when others => null;
                end case;
            end if;

            -- ============================
            -- SLAVE SIDE: 6502 WRITE LOGIC
            -- ============================
            if s_cs_n = '0' then
                case s_address is
                    when "000" => -- Status  can be read and written
                        if s_rw = '0' then
                            status <= s_data_in; 
                        else
                            s_data_out <= status;
                        end if;
                        
                    when "001" => -- Track only read never written
                        if s_rw = '1' then
                            s_data_out <= track;
                        end if;

                    when "010" => -- Sector only read never written
                        if s_rw = '1' then
                            s_data_out <= sector;
                        end if;
                        
                    when "011" => -- Data  can be read and written
                        if s_rw = '0' then
                            data   <= s_data_in;
                            status(1) <= '1';     -- writing data automatically set DRQ
                        else
                            s_data_out <= data;
                            --status(1) = '0'     -- need to be checked
                        end if;

                    when "100" => -- Command only read never written
                        if s_rw = '1' then
                            s_data_out <= command;
                            trigger(7) <= '0'; -- reading command clear command trigger flag
                        end if;

                    when "101" => -- DrvSel only read never written
                        if s_rw = '1' then
                            s_data_out <= drvsel;
                        end if;
                        
                    when "110" => -- rotation
                        if s_rw = '0' then
                            rotation  <= s_data_in;
                            -- should trigger index signal generation
                        else
                            s_data_out <= rotation;
                        end if;

                    when "111" => -- trigger
                        if s_rw = '1' then
                            s_data_out <= trigger;  -- never written flags cleared by reading the corresponding register
                        end if;

                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- master mux
    m_data_out <= status when m_address = "00" else
                  track  when m_address = "01" else
                  sector when m_address = "10" else
                  data   when m_address = "11" else
                  x"FF";
                

end architecture;


