library ieee;
use ieee.std_logic_1164.all;


entity trs80_printer is
    port (
        clk        : in  std_logic;
        reset_n    : in  std_logic;
        serial_clk : in  std_logic;               -- x16 baud clock (e.g. MC14411)
        cs_n       : in  std_logic;               -- chip select, active low
        rd_n       : in  std_logic;
        wr_n       : in  std_logic;
        data_in    : in  std_logic_vector(7 downto 0);
        data_out   : out std_logic_vector(7 downto 0);
        format     : in  std_logic_vector(2 downto 0);
        tx         : out std_logic
    );
end trs80_printer;

architecture rtl of trs80_printer is

    component uart_send is
        port (
            clk     : in  std_logic;
            reset_n : in  std_logic;
            tx      : out std_logic;
            req     : in  std_logic;
            ready   : out std_logic;
            ack     : out std_logic;
            format  : in  std_logic_vector(2 downto 0);
            data_in : in  std_logic_vector(7 downto 0)
        );
    end component;

    signal tx_req   : std_logic := '0';
    signal tx_ready : std_logic;
    signal tx_ack   : std_logic;
    signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');

begin

    u_uart_send : uart_send
        port map (
            clk     => serial_clk,
            reset_n => reset_n,
            tx      => tx,
            req     => tx_req,
            ready   => tx_ready,
            ack     => tx_ack,
            format  => format,
            data_in => tx_data
        );

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            tx_req  <= '0';
            tx_data <= (others => '0');
        elsif rising_edge(clk) then
            if cs_n = '0' and wr_n = '0' then
                tx_data <= data_in;
                tx_req  <= '1';                    -- assert and hold
            elsif tx_req = '1' and tx_ready = '0' then
                tx_req <= '0';                     -- UART accepted, release
            end if;
        end if;
    end process;


    process(cs_n, rd_n, tx_ready)
    begin
        if cs_n = '0' and rd_n = '0' then
            -- TRS-80 Model I Status:
            -- Bit 7: Often ignored or used for Fault
            -- Bit 6: Busy (1 = Busy, 0 = Ready)
            -- Bits 5-0: Should generally be high or consistent with a real controller
            data_out <= '0' & (not tx_ready) & "111111"; 
        else
            data_out <= (others => 'Z'); -- Ensure you aren't contending the bus
        end if;
    end process;

end rtl;