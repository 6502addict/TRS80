library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- i8251 USART compatible wrapper (async mode only)
-- serial_clk must be 16x baud rate
--
-- C/D mapping:
--   cd=0 (write): Transmit Data Register (TDR)
--   cd=0 (read):  Receive Data Register (RDR)
--   cd=1 (write): Mode word (first write after reset), then Command word
--   cd=1 (read):  Status Register
--
-- Mode byte (async):
--   bits 1:0 = baud rate factor (10=16x, used here)
--   bits 3:2 = char length (10=7bit, 11=8bit)
--   bit  4   = parity enable
--   bit  5   = even parity (1=even, 0=odd)
--   bits 7:6 = stop bits (01=1, 11=2)
--
-- Command byte:
--   bit 0 = TXEN
--   bit 2 = RXEN
--   bit 4 = ER  (error reset)
--   bit 6 = IR  (internal reset -> back to mode phase)
--
-- Status byte:
--   bit 0 = TXRDY
--   bit 1 = RXRDY
--   bit 2 = TXEMPTY
--   bit 3 = PE  (parity error)
--   bit 4 = OE  (overrun error)
--   bit 7 = DSR (tied to 1)

entity i8251_uart is
    port (
        clk        : in  std_logic;        -- CPU clock
        serial_clk : in  std_logic;        -- 16x baud clock
        reset_n    : in  std_logic;
        cs_n       : in  std_logic;
        cd         : in  std_logic;        -- 0=data, 1=control/status
        rd_n       : in  std_logic;
        wr_n       : in  std_logic;
        data_in    : in  std_logic_vector(7 downto 0);
        data_out   : out std_logic_vector(7 downto 0);
        txrdy      : out std_logic;
        rxrdy      : out std_logic;
        rx         : in  std_logic;
        tx         : out std_logic
    );
end entity i8251_uart;

architecture rtl of i8251_uart is

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

    component uart_receive is
        port (
            clk          : in  std_logic;
            reset_n      : in  std_logic;
            rx           : in  std_logic;
            format       : in  std_logic_vector(2 downto 0);
            req          : in  std_logic;
            ready        : out std_logic;
            ack          : out std_logic;
            data_out     : out std_logic_vector(7 downto 0);
            parity_error : out std_logic
        );
    end component;

    signal mode_reg    : std_logic_vector(7 downto 0) := (others => '0');
    signal cmd_reg     : std_logic_vector(7 downto 0) := (others => '0');
    signal mode_phase  : std_logic := '0';  -- '0'=awaiting mode, '1'=awaiting command
    signal format      : std_logic_vector(2 downto 0);

    signal sw_reset    : std_logic := '0';
    signal int_res_n   : std_logic;

    -- TX signals
    signal tx_req      : std_logic := '0';
    signal tx_ready    : std_logic := '1';
    signal tx_ready_prev  : std_logic := '1';
    signal tx_ready_sync  : std_logic_vector(1 downto 0) := "11";
    signal tx_ack      : std_logic;
    signal tx_ack_prev : std_logic;
    signal tx_ack_sync : std_logic_vector(1 downto 0) := "00";
    signal tx_data     : std_logic_vector(7 downto 0) := (others => '0');

    -- RX signals
    signal rx_req      : std_logic := '0';
    signal rx_ready    : std_logic;
    signal rx_ack      : std_logic;
    signal rx_ack_prev : std_logic;
    signal rx_ack_sync : std_logic_vector(1 downto 0) := "00";
    signal rx_data     : std_logic_vector(7 downto 0);
    signal parity_err  : std_logic;

    signal rdr         : std_logic_vector(7 downto 0) := (others => '0');
    signal rdrf        : std_logic := '0';
    signal ovrn        : std_logic := '0';
    signal tdre        : std_logic := '1';
    signal status_reg  : std_logic_vector(7 downto 0);

begin

    int_res_n <= reset_n and (not sw_reset);

    send: uart_send
        port map (
            clk     => serial_clk,
            reset_n => int_res_n,
            tx      => tx,
            req     => tx_req,
            ready   => tx_ready,
            ack     => tx_ack,
            format  => format,
            data_in => tx_data
        );

    recv: uart_receive
        port map (
            clk          => serial_clk,
            reset_n      => int_res_n,
            rx           => rx,
            format       => format,
            req          => rx_req,
            ready        => rx_ready,
            ack          => rx_ack,
            data_out     => rx_data,
            parity_error => parity_err
        );

    -- 8251 mode byte to uart_send/receive format (6850 encoding)
    -- format(2): 0=7bit, 1=8bit  <- mode_reg(3)
    -- format(0): 0=even, 1=odd   <- not mode_reg(5)
    -- format(1): for 8bit=parity_enable, for 7bit=1stop(1)/2stop(0)
--    format(2) <= mode_reg(3);
--    format(0) <= not mode_reg(5);
--    format(1) <= (mode_reg(4) and mode_reg(3)) or (not mode_reg(7) and not mode_reg(3));

    format(2) <= mode_reg(3) and mode_reg(2);
    format(0) <= not mode_reg(5);
    format(1) <= (mode_reg(4) and mode_reg(3) and mode_reg(2)) or (not mode_reg(7) and not (mode_reg(3) and mode_reg(2)));


    -- 8251 status register
    -- bit7=DSR(1) bit6=SYNDET(0) bit5=FE(0) bit4=OE bit3=PE bit2=TXEMPTY bit1=RXRDY bit0=TXRDY
    status_reg <= '1' & '0' & '0' & ovrn & parity_err & tdre & rdrf & tdre;

    txrdy <= tdre and cmd_reg(0);  -- TXEN gate
    rxrdy <= rdrf and cmd_reg(2);  -- RXEN gate

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            mode_reg   <= (others => '0');
            cmd_reg    <= (others => '0');
            mode_phase <= '0';
            sw_reset   <= '0';
            tdre       <= '1';
            rdrf       <= '0';
            ovrn       <= '0';
            tx_req     <= '0';
            rx_req     <= '0';
        elsif rising_edge(clk) then
            sw_reset <= '0';

            -- CDC synchronizers (identical to mc6850)
            tx_ack_sync   <= tx_ack_sync(0)   & tx_ack;
            tx_ack_prev   <= tx_ack_sync(1);
            rx_ack_sync   <= rx_ack_sync(0)   & rx_ack;
            rx_ack_prev   <= rx_ack_sync(1);
            tx_ready_sync <= tx_ready_sync(0) & tx_ready;
            tx_ready_prev <= tx_ready_sync(1);

            if tx_ready_sync(1) = '0' and tx_ready_prev = '1' then
                tx_req <= '0';
            end if;

            if tx_ack_sync(1) = '1' and tx_ack_prev = '0' then
                tdre <= '1';
            end if;

            if rx_ack_sync(1) = '1' and rx_ack_prev = '0' then
                rdr  <= rx_data;
                if rdrf = '1' then
                    ovrn <= '1';
                end if;
                rdrf <= '1';
            end if;

            if cs_n = '0' then
                if cd = '1' then
                    if wr_n = '0' then
                        -- Write: mode or command depending on phase
                        if mode_phase = '0' then
                            mode_reg   <= data_in;
                            mode_phase <= '1';
                        else -- rd_n = '0'
                            if data_in(6) = '1' then
                                -- IR bit: internal reset back to mode phase
                                mode_phase <= '0';
                                sw_reset   <= '1';
                            else
                                cmd_reg <= data_in;
                                if data_in(4) = '1' then
                                    -- ER bit: reset error flags
                                    ovrn <= '0';
                                end if;
                            end if;
                        end if;
                    else
                        data_out <= status_reg;
                    end if;
                else
                    if wr_n = '0' then
                        tx_data   <= data_in;
                        tx_req  <= '1';
                        tdre    <= '0';
                    else
                        data_out <= rdr;
                        rdrf     <= '0';
                        ovrn     <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;