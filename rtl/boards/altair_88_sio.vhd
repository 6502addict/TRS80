library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 88-SIO Serial I/O Board (single port)
-- serial_clk must be 16x baud rate
-- Format set by generic (hardware jumpers on real board)
--
-- Address map (address selects register):
--   address=0 write : Control register
--   address=0 read  : Status register
--   address=1 write : Transmit data
--   address=1 read  : Receive data
--
-- Control register (write):
--   bit 0 : Input interrupt enable  (1=enabled)
--   bit 1 : Output interrupt enable (1=enabled)
--   bits 7:2 : don't care
--
-- Status register (read):
--   bit 7 : Output device Ready    (0=ready, 1=not ready)
--   bit 6 : not used
--   bit 5 : Data Available         (1=data in receive buffer)
--   bit 4 : Data Overflow          (1=overrun)
--   bit 3 : Framing Error          (1=error)
--   bit 2 : Parity Error           (1=error)
--   bit 1 : Transmitter Buf Empty  (1=ready for new data)
--   bit 0 : Input device Ready     (0=ready, 1=not ready)
--
-- IRQ output: active high, asserted when:
--   input  interrupt enabled AND data available
--   output interrupt enabled AND transmitter ready

entity altair_88_sio is
    generic (
        -- format encoding (same as uart_send/uart_receive):
        -- bit2: 0=7bit, 1=8bit
        -- bit1: parity enable (8bit) or stop bits (7bit: 1=1stop, 0=2stop)
        -- bit0: 0=even, 1=odd parity
        FORMAT : std_logic_vector(2 downto 0) := "100"  -- 8N1 default
    );
    port (
        cpu_clk    : in  std_logic;        -- CPU clock
        serial_clk : in  std_logic;        -- 16x baud clock
        reset_n    : in  std_logic;
        cs_n       : in  std_logic;
        address    : in  std_logic;        -- 0=control/status, 1=data
        rd_n       : in  std_logic;
        wr_n       : in  std_logic;
        data_in    : in  std_logic_vector(7 downto 0);
        data_out   : out std_logic_vector(7 downto 0);
        irq_n      : out std_logic;
        rx         : in  std_logic;
        tx         : out std_logic
    );
end entity altair_88_sio;

architecture rtl of altair_88_sio is

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

    -- control register
    signal ctrl_reg    : std_logic_vector(1 downto 0) := "00";  -- bit1=out irq en, bit0=in irq en

    -- TX signals
    signal tx_req      : std_logic := '0';
    signal tx_ready    : std_logic := '1';
    signal tx_ready_prev  : std_logic := '1';
    signal tx_ready_sync  : std_logic_vector(1 downto 0) := "11";
    signal tx_ack      : std_logic;
    signal tx_ack_prev : std_logic;
    signal tx_ack_sync : std_logic_vector(1 downto 0) := "00";
    signal tx_data     : std_logic_vector(7 downto 0) := (others => '0');
    signal tbmt        : std_logic := '1';  -- transmitter buffer empty

    -- RX signals
    signal rx_req      : std_logic := '0';
    signal rx_ready    : std_logic;
    signal rx_ack      : std_logic;
    signal rx_ack_prev : std_logic;
    signal rx_ack_sync : std_logic_vector(1 downto 0) := "00";
    signal rx_data     : std_logic_vector(7 downto 0);
    signal parity_err  : std_logic;

    signal rdr         : std_logic_vector(7 downto 0) := (others => '0');
    signal da          : std_logic := '0';   -- data available
    signal ovrn        : std_logic := '0';   -- overrun
    signal fe          : std_logic := '0';   -- framing error (tied to parity_err from uart_receive)

    signal status_reg  : std_logic_vector(7 downto 0);

begin

    send: uart_send
        port map (
            clk     => serial_clk,
            reset_n => reset_n,
            tx      => tx,
            req     => tx_req,
            ready   => tx_ready,
            ack     => tx_ack,
            format  => FORMAT,
            data_in => tx_data
        );

    recv: uart_receive
        port map (
            clk          => serial_clk,
            reset_n      => reset_n,
            rx           => rx,
            format       => FORMAT,
            req          => rx_req,
            ready        => rx_ready,
            ack          => rx_ack,
            data_out     => rx_data,
            parity_error => parity_err
        );

    -- status register
    -- bit7: output not ready (0=ready = tbmt=1)
    -- bit6: not used
    -- bit5: data available
    -- bit4: overrun
    -- bit3: framing error
    -- bit2: parity error
    -- bit1: transmitter buffer empty
    -- bit0: input not ready (0=ready = da=1)
    status_reg <= (not tbmt) & '0' & da & ovrn & fe & parity_err & tbmt & (not da);

    irq_n <= not (ctrl_reg(0) and da) or (ctrl_reg(1) and tbmt);

    process(cpu_clk, reset_n)
    begin
        if reset_n = '0' then
            ctrl_reg      <= "00";
            tbmt          <= '1';
            da            <= '0';
            ovrn          <= '0';
            fe            <= '0';
            tx_req        <= '0';
            rx_req        <= '0';
            tx_ack_sync   <= "00";
            tx_ack_prev   <= '0';
            rx_ack_sync   <= "00";
            rx_ack_prev   <= '0';
            tx_ready_sync <= "11";
            tx_ready_prev <= '1';
        elsif rising_edge(cpu_clk) then

            -- CDC synchronizers
            tx_ack_sync   <= tx_ack_sync(0)   & tx_ack;
            tx_ack_prev   <= tx_ack_sync(1);
            rx_ack_sync   <= rx_ack_sync(0)   & rx_ack;
            rx_ack_prev   <= rx_ack_sync(1);
            tx_ready_sync <= tx_ready_sync(0) & tx_ready;
            tx_ready_prev <= tx_ready_sync(1);

            -- tx_req deassert when uart_send starts
            if tx_ready_sync(1) = '0' and tx_ready_prev = '1' then
                tx_req <= '0';
            end if;

            -- tx complete: buffer empty again
            if tx_ack_sync(1) = '1' and tx_ack_prev = '0' then
                tbmt <= '1';
            end if;

            -- rx complete: data available
            if rx_ack_sync(1) = '1' and rx_ack_prev = '0' then
                rdr  <= rx_data;
                fe   <= parity_err;  -- framing/parity from uart_receive
                if da = '1' then
                    ovrn <= '1';
                end if;
                da <= '1';
            end if;

            if cs_n = '0' then
                if address = '0' then
                    if wr_n = '0' then          -- write control register
                        ctrl_reg <= data_in(1 downto 0);
                    else                         -- read status register
                        data_out <= status_reg;
                    end if;
                else
                    if wr_n = '0' then          -- write transmit data
                        tx_data <= data_in;
                        tx_req  <= '1';
                        tbmt    <= '0';
                    else                         -- read receive data
                        data_out <= rdr;
                        da       <= '0';
                        ovrn     <= '0';
                    end if;
                end if;
            end if;

        end if;
    end process;

end architecture rtl;