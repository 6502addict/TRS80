library ieee;
use ieee.std_logic_1164.all;

-- Altair 88-PIO printer port (output only)
-- address=0 : status port  (read=status, write=ignored)
-- address=1 : data port    (write=send, read=0x00)
-- status bit 0 = TBMT (uart_send ready), bit 1 = hardwired 1
-- format : 3-bit MC6850 CR4:CR3:CR2 (see uart_send)

entity altair_88_pio is
    port (
        clk        : in  std_logic;
        reset_n    : in  std_logic;
        serial_clk : in  std_logic;               -- x16 baud clock (e.g. MC14411)
        cs_n       : in  std_logic;               -- chip select, active low
        address         : in  std_logic;               -- 0=status port, 1=data port
        rd_n       : in  std_logic;
        wr_n       : in  std_logic;
        data_in    : in  std_logic_vector(7 downto 0);
        data_out   : out std_logic_vector(7 downto 0);
        format     : in  std_logic_vector(2 downto 0);
        tx         : out std_logic
    );
end altair_88_pio;

architecture rtl of altair_88_pio is

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

    -- write process
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            tx_req  <= '0';
            tx_data <= (others => '0');
        elsif rising_edge(clk) then
            tx_req <= '0';                      -- default: deassert
            if cs_n = '0' and wr_n = '0' and address = '1' then
                tx_data <= data_in;             -- latch data
                tx_req  <= '1';                 -- trigger uart_send
            end if;
        end if;
    end process;

    -- read process (combinatorial)
    process(cs_n, rd_n, address, tx_ready)
    begin
        data_out <= (others => '0');
        if cs_n = '0' and rd_n = '0' then
            if address = '0' then
                -- status: bit1=1 (no input device), bit0=TBMT
                data_out <= "000000" & '1' & tx_ready;
            end if;
            -- address=1 : data read returns 0x00 (default)
        end if;
    end process;

end rtl;