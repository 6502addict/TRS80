library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity trs80_fdc_bridge is
    port (
        -- Master Side (Z80 / TRS-80)
        m_clk          : in  std_logic;
        m_reset_n      : in  std_logic;
        m_cs_n         : in  std_logic;
        m_address      : in  std_logic_vector(2 downto 0); -- 37E0-37E4
        m_wr_n         : in  std_logic;
        master_rd_n    : in  std_logic;
        master_din     : in  std_logic_vector(7 downto 0);
        master_dout    : out std_logic_vector(7 downto 0);

        -- Slave Side (6502 / IOP)
        m65_clk     : in  std_logic;
        m65_cs_n    : in  std_logic;
        m65_addr    : in  std_logic_vector(2 downto 0);
        m65_wr_n    : in  std_logic;
        m65_rd_n    : in  std_logic;
        m65_din     : in  std_logic_vector(7 downto 0);
        m65_dout    : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of trs80_fdc_bridge is
    -- Internal WD1771 Registers
    signal reg_command : std_logic_vector(7 downto 0) := x"00";
    signal reg_status  : std_logic_vector(7 downto 0) := x"00";
    signal reg_track   : std_logic_vector(7 downto 0) := x"00";
    signal reg_sector  : std_logic_vector(7 downto 0) := x"00";
    signal reg_data    : std_logic_vector(7 downto 0) := x"00";
    signal reg_select  : std_logic_vector(7 downto 0) := x"00";

    -- Debug Shadow Flags (Bit 7: Cmd, Bit 6: Data, Bit 0: Select)
    signal shadow_flags : std_logic_vector(7 downto 0) := x"00";
    
begin

    -- ============================================================
    -- MASTER SIDE: Z80 WRITE LOGIC (Sets the flags)
    -- ============================================================
    process(clk, res_n)
    begin
        if res_n = '0' then
            reg_status <= x"00"; -- Not Busy
            shadow_flags <= x"00";
        elsif rising_edge(clk) then
            
            -- MASTER (Z80) SIDE WRITES
            if z80_cs_n = '0' and z80_wr_n = '0' then
                case z80_addr is
                    when "000" => -- Command Reg
                        reg_command <= z80_din;
                        shadow_flags(7) <= '1'; -- Trigger 6502 BMI
                        reg_status(0)   <= '1'; -- Set WD1771 BUSY bit immediately
                    when "011" => -- Data Reg
                        reg_data <= z80_din;
                        shadow_flags(6) <= '1'; -- Trigger 6502 BVS
                    when "100" => -- Drive Select
                        reg_select <= z80_din;
                        shadow_flags(0) <= '1'; -- New Drive Selected
                    when others => null;
                end case;
            end if;

            -- SLAVE (6502) SIDE WRITES (The Service Action)
            if m65_cs_n = '0' and m65_wr_n = '0' then
                case m65_addr is
                    when "000" => -- Status Reg
                        -- 6502 writes the result of the op (Busy off, Track 0, etc.)
                        reg_status <= m65_din; 
                    when "011" => -- Data Reg
                        -- 6502 places the byte read from "disk" here
                        reg_data <= m65_din;
                        -- Potentially set a DRQ bit in status here
                    when "111" => -- Clear Flags
                        -- 6502 can manually reset flags by writing 0 here
                        shadow_flags <= shadow_flags and m65_din;
                    when others => null;
                end case;
            end if;
            
            -- Auto-clear flag on 6502 read (Optional, but very handy)
            if m65_cs_n = '0' and m65_rd_n = '0' and m65_addr = "111" then
                 -- This allows the 'BIT' instruction to see the flag, 
                 -- and then it clears so you don't process the same CMD twice.
                 shadow_flags <= x"00"; 
            end if;
        end if;
    end process;

    -- Z80 Read Routing
    z80_dout <= reg_status when z80_addr = "000" else
                reg_track  when z80_addr = "001" else
                reg_sector when z80_addr = "010" else
                reg_data   when z80_addr = "011" else
                x"FF";

end architecture;


