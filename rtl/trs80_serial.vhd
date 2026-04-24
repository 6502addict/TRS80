library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================================
-- Module  : trs80_serial
-- Purpose : TRS-80 Model I/III RS-232 interface (UART + control/status)
-- =============================================================================
--
-- Emulates the TRS-80 RS-232 board (Model I: Radio Shack 26-1145 expansion;
-- Model III: built-in motherboard UART). Presents three I/O ports to the Z80
-- at addresses 0xE8, 0xE9, 0xEA.
--
-- Port mapping (Z80 I/O address space, 8-bit port decode):
--
--   Port 0xE8 : Modem status / UART master reset
--   Port 0xE9 : Baud rate generator / DIP switch settings
--   Port 0xEA : UART control register / UART status register
--   Port 0xEB : UART data register  (TX on write, RX on read)
--
-- ---------------------------------------------------------------------------
-- Port 0xE8 - Modem status (read) / UART reset (write)
-- ---------------------------------------------------------------------------
-- Read:
--   bit 0 : CTS  - Clear To Send    (1 = active)
--   bit 1 : DSR  - Data Set Ready   (1 = active)
--   bit 2 : RLSD - Carrier Detect   (1 = active)
--   bit 3 : RI   - Ring Indicator   (1 = active)
--   bit 4..6 : unused
--   bit 7 : reset acknowledge (1 = reset in progress)
-- Write:
--   Any value written triggers a UART master reset.
--
-- ---------------------------------------------------------------------------
-- Port 0xE9 - Baud rate (write) / DIP switch settings (read)
-- ---------------------------------------------------------------------------
-- Write (set baud rate):
--   bits 3..0 : Receive speed code
--   bits 7..4 : Transmit speed code
--   (RX and TX can be set to different rates; normally the same value is
--    written in both nibbles, e.g. 0xEE for 9600/9600.)
--
--   Speed codes:
--     0x0 =    50 baud      0x8 =  1800 baud
--     0x1 =    75 baud      0x9 =  2000 baud
--     0x2 =   100 baud      0xA =  2400 baud
--     0x3 = 134.5 baud      0xB =  3600 baud
--     0x4 =   150 baud      0xC =  4800 baud
--     0x5 =   300 baud      0xD =  7200 baud
--     0x6 =   600 baud      0xE =  9600 baud
--     0x7 =  1200 baud      0xF = 19200 baud
--
-- Read (DIP switch settings, configured at boot by the user):
--   bit 0..2 : unused
--   bit 3    : parity enable  (0 = enable)
--   bit 4    : stop bits      (0 = 1 stop, 1 = 2 stop)
--   bit 5..6 : word length    (00 = 5, 01 = 7, 10 = 6, 11 = 8)
--   bit 7    : parity sense   (0 = odd, 1 = even)
--
-- ---------------------------------------------------------------------------
-- Port 0xEA - UART control (write) / UART status (read)
-- ---------------------------------------------------------------------------
-- Write (configure UART):
--   bit 0 : RTS       (0 = RTS asserted)
--   bit 1 : DTR       (0 = DTR asserted)
--   bit 2 : TX enable (1 = enable transmitter)
--   bit 3 : parity    (1 = no parity)
--   bit 4 : stop bits (0 = 1 stop bit, 1 = 2 stop bits)
--   bits 5..6 : word length (00 = 5, 01 = 7, 10 = 6, 11 = 8)
--   bit 7 : parity sense (1 = even, 0 = odd)
--
-- Read (UART status):
--   bit 0..2 : unused
--   bit 3 : parity error       (1 = error)
--   bit 4 : framing error      (1 = error)
--   bit 5 : overrun error      (1 = error)
--   bit 6 : TBMT - transmitter buffer empty (0 = data sent / ready for next byte)
--   bit 7 : DA   - data available           (1 = received byte ready to read)
--
-- ---------------------------------------------------------------------------
-- Port 0xEB - Data register
-- ---------------------------------------------------------------------------
-- Write: byte to transmit. Writing clears TBMT until the byte is sent.
-- Read : last received byte. Reading clears the DA status bit.
--
-- ---------------------------------------------------------------------------
-- Notes on differences from Replica 1 / Altair-style serial:
--   - Four I/O ports instead of two (adds modem status and baud-rate regs).
--   - Word length, parity, stop bits, and baud rate are runtime-configurable
--     via port 0xE9/0xEA writes, not fixed by a generic.
--   - Separate "word length" encoding: 00=5, 01=7, 10=6, 11=8 (note the
--     non-sequential ordering, a TRS-80 quirk).
--   - Dedicated master-reset via write to 0xE8.
--   - Modem control/status lines (CTS/DSR/DCD/RI/RTS/DTR) are exposed,
--     unlike on the Altair 88-SIO.
-- =============================================================================

entity trs80_serial is
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
        address    : in  std_logic_vector(1 downto 0);
        rd_n       : in  std_logic;
        wr_n       : in  std_logic;
        data_in    : in  std_logic_vector(7 downto 0);
        data_out   : out std_logic_vector(7 downto 0);
        irq_n      : out std_logic;
        rx         : in  std_logic;
        tx         : out std_logic
    );
end entity trs80_serial;

architecture rtl of trs80_serial is

    component prog_clock_divider IS
        generic (bits : integer := 8);
        port (
            reset_n  : in  std_logic := '1';
            clk_in   : in  std_logic;
            divider  : in  std_logic_vector(bits -1 downto 0);  
            clk_out  : out std_logic
        );
    end component;

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

    -- TX signals
    signal tx_req           : std_logic := '0';
    signal tx_ready         : std_logic := '1';
    signal tx_ready_prev    : std_logic := '1';
    signal tx_ready_sync    : std_logic_vector(1 downto 0) := "11";
    signal tx_ack           : std_logic;
    signal tx_ack_prev      : std_logic;
    signal tx_ack_sync      : std_logic_vector(1 downto 0) := "00";
    signal tx_data          : std_logic_vector(7 downto 0) := (others => '0');
    signal tbmt             : std_logic := '1';  -- transmitter buffer empty

    -- RX signals
    signal rx_req           : std_logic := '0';
    signal rx_ready         : std_logic;
    signal rx_ack           : std_logic;
    signal rx_ack_prev      : std_logic;
    signal rx_ack_sync      : std_logic_vector(1 downto 0) := "00";
    signal rx_data          : std_logic_vector(7 downto 0);
    signal parity_err       : std_logic;

    signal rdr              : std_logic_vector(7 downto 0) := (others => '0');
    signal da               : std_logic := '0';   -- data available
    signal ovrn             : std_logic := '0';   -- overrun
    signal fe               : std_logic := '0';   -- framing error (tied to parity_err from uart_receive) 
 
    signal soft_reset_n     : std_logic := '1';
    signal tr_enable        : std_logic := '1';
    signal baud_rate        : std_logic_vector(7 downto 0);
    signal fmt_parity       : std_logic_vector(1 downto 0);
    signal fmt_len          : std_logic_vector(1 downto 0);
    signal fmt_stop         : std_logic;
    signal fmt              : std_logic_vector(2 downto 0);
    signal baud_clk         : std_logic;
    signal internal_reset_n : std_logic := '1';
    signal reset_flag       : std_logic := '0';
    signal trs_fmt          : std_logic_vector(7 downto 0);
    
begin

    send: uart_send               port map (clk          => baud_clk,
                                            reset_n      => internal_reset_n,
                                            tx           => tx,
                                            req          => tx_req,
                                            ready        => tx_ready,
                                            ack          => tx_ack,
                                            format       => fmt,
                                            data_in      => tx_data);

    recv: uart_receive            port map (clk          => baud_clk,
                                            reset_n      => internal_reset_n,
                                            rx           => rx,
                                            format       => fmt,
                                            req          => rx_req,
                                            ready        => rx_ready,
                                            ack          => rx_ack,
                                            data_out     => rx_data,
                                            parity_error => parity_err);

    baud: prog_clock_divider   generic map (bits => 8)
                                  port map (reset_n      => reset_n,
                                            clk_in       => serial_clk,
                                            divider      => baud_rate,
                                            clk_out      => baud_clk);

    fmt <= "000" when trs_fmt(7 downto 3) = "10100" else -- 7E2
           "001" when trs_fmt(7 downto 3) = "00100" else -- 7O2
           "010" when trs_fmt(7 downto 3) = "10100" else -- 7E1 
           "011" when trs_fmt(7 downto 3) = "00100" else -- 7O1
           "100" when trs_fmt(7 downto 3) = "01111" else -- 8N2
           "100" when trs_fmt(7 downto 3) = "11111" else -- 8N2
           "101" when trs_fmt(7 downto 3) = "01111" else -- 8N1
           "101" when trs_fmt(7 downto 3) = "11111" else -- 8N1
           "110" when trs_fmt(7 downto 3) = "11100" else -- 8E1
           "111" when trs_fmt(7 downto 3) = "01100" else -- 8O1
           "101"; -- Default


    internal_reset_n <= reset_n and soft_reset_n;
    
    irq_n <= '1'; --not (ctrl_reg(0) and da) or (ctrl_reg(1) and tbmt);

    process(cpu_clk, reset_n)
    begin
        if reset_n = '0' or soft_reset_n = '0' then
            tr_enable     <= '1';
            trs_fmt       <= "01111000";
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
            soft_reset_n  <= '1';
            baud_rate     <= "00000000";
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
                fe   <= parity_err; 
                if da = '1' then
                    ovrn <= '1';
                end if;
                da <= '1';
            end if;
            
            if cs_n = '0' then
                case address is
                    when "00" => 
                        -- E8     READ                WRITE
                        -- bit7:  reset flag          reset
                        -- bit6:  unused              reset
                        -- bit5:  unused              reset
                        -- bit4:  unused              reset
                        -- bit3:  1=RI  active        reset
                        -- bit2:  1=DCD active        reset
                        -- bit1:  1=DSR active        reset
                        -- bit0:  1=CTS active        reset
                        if wr_n = '0' then          
                            soft_reset_n <= '0';
                            reset_flag   <= '1';
                        end if;
                        if rd_n = '0' then                      
                            data_out <= reset_flag & "000" & "0111";  -- CTS/DSR/DCD forced RI ignored
                            reset_flag   <= '0';
                        end if;
                        
                    when "01" =>
                        -- E9     READ                WRITE
                        -- bit7:  parity 0=odd        baud rate
                        -- bit6:  length              baud rate
                        -- bit5:  length              baud rate
                        -- bit4:  stops 0=1 1=2       baud rate
                        -- bit3:  parity 0=enable     baud rate
                        -- bit2:  unused              baud rate
                        -- bit1:  unused              baud rate
                        -- bit0:  unused              baud rate
                        if wr_n = '0' then
                            baud_rate <= data_in;
                        end if;
                        if rd_n = '0' then
                            data_out <= trs_fmt;
                        end if;
                        
                    when "10" =>
                        -- EA status read            write   register
                        -- bit7:     unused           0 = RTS 0n   (not implemented)
                        -- bit6:     unused           0 = DTR On   (not implemented)
                        -- bit5:     unused           1 = transmit enable 
                        -- bit4:  1=parity error      1 = no parity
                        -- bit3:  1=framing error     0 = 1 stop bit
                        -- bit2:  1=overrun error     word length  00 = 5 (not implemented) 01 = 7 10 = 6 (not implemented) 11 = 8
                        -- bit1:  0=data sent         word length
                        -- bit0:  1=data available    1 even parity, 0 odd parity
                        if wr_n = '0' then          -- write control register
                            trs_fmt   <= data_in;
                        end if;
                        if rd_n = '0' then
                            data_out <= da & tbmt & ovrn & fe & parity_err & "000";
                        end if;
                        
                    when "11" => -- EB  data register
                        if wr_n = '0' then          -- write transmit data
                            if tr_enable = '1' then
                                tx_data <= data_in;
                                tx_req  <= '1';
                                tbmt    <= '0';
                            end if;
                        end if;
                        if rd_n = '0' then
                            data_out <= rdr;
                            da       <= '0';
                            ovrn     <= '0';
                        end if;
                    when others =>
                        null;
                end case;
            end if;    
        end if;
    end process;

end architecture rtl;