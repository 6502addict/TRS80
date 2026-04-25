library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- MC6850 ACIA compatible wrapper for uart_send/uart_receive
-- clock must be 16x baud rate
--
-- Address mapping:
--   0 (write): Control Register (CR)
--   0 (read):  Status Register (SR)
--   1 (write): Transmit Data Register (TDR)
--   1 (read):  Receive Data Register (RDR)

entity mc6850_uart is
    port (
        phi2        : in  std_logic;                     -- 6502 phi2 clock
        serial_clk  : in  std_logic;                     -- 16x baud clock
        reset_n     : in  std_logic;

        -- CPU interface
        cs_n        : in  std_logic;
        rw          : in  std_logic;
        address     : in  std_logic;
        data_in     : in  std_logic_vector(7 downto 0);
        data_out    : out std_logic_vector(7 downto 0);

        -- Interrupt output
        irq_n       : out std_logic;

        -- Physical UART interface
        rx          : in  std_logic;
        tx          : out std_logic
    );
end entity mc6850_uart;


architecture rtl of mc6850_uart is
    -- ... [Keep Component Declarations for uart_send/receive] ...
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

    signal cr               : std_logic_vector(7 downto 0) := (others => '0');
    signal format           : std_logic_vector(2 downto 0);  -- CR4:CR3:CR2

    signal master_reset     : std_logic := '0';

    -- TX signals
    signal tx_req           : std_logic := '0';
    signal tx_ready         : std_logic := '1';
    signal tx_ready_prev    : std_logic := '1';
    signal tx_ready_sync    : std_logic_vector(1 downto 0) := "11";
    signal tx_ack           : std_logic;
    signal tx_ack_prev      : std_logic;
    signal tx_ack_sync      : std_logic_vector(1 downto 0) := "00";
    signal tx_data          : std_logic_vector(7 downto 0) := (others => '0');

    -- RX signals
    signal rx_req           : std_logic := '0';
    signal rx_ready         : std_logic;
    signal rx_ack           : std_logic;
    signal rx_ack_prev      : std_logic;
    signal rx_ack_sync      : std_logic_vector(1 downto 0) := "00";
    signal rx_data          : std_logic_vector(7 downto 0);
    signal parity_err       : std_logic;

    signal rdr          : std_logic_vector(7 downto 0) := (others => '0');
    signal rdrf         : std_logic := '0';
    signal ovrn         : std_logic := '0';
    signal tdre         : std_logic := '1';
    signal irq_flag     : std_logic := '0';
    signal status_reg   : std_logic_vector(7 downto 0);

    -- Internal reset that combines hardware reset and 6850 software Master Reset
    signal internal_res_n : std_logic;
    signal sw_reset       : std_logic := '0';


begin

    -- Software reset logic: MC6850 CR1:0 = "11"
    internal_res_n <= reset_n and (not sw_reset);

    -- 1. UART INSTANTIATIONS
    send: uart_send
        port map (
            clk     => serial_clk,
            reset_n => internal_res_n,
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
            reset_n      => internal_res_n,
            rx           => rx,
            format       => format,
            req          => rx_req, 
            ready        => rx_ready,
            ack          => rx_ack,
            data_out     => rx_data,
            parity_error => parity_err
        );

    -- Format and Status mapping
    format <= cr(4 downto 2);
    status_reg <= irq_flag & parity_err & ovrn & "000" & tdre & rdrf;
    irq_flag   <= rdrf or (tdre and (not cr(6)) and cr(5));
    irq_n      <= not irq_flag;

    -- 2. THE PHI2 (15MHz) INTERFACE PROCESS
    process(phi2, reset_n)
    begin
        if reset_n = '0' then
            cr          <= (others => '0');
            tdre        <= '1';
            rdrf        <= '0';
            ovrn        <= '0';
            tx_req      <= '0';
            rx_req      <= '0';
            sw_reset    <= '0';
        elsif rising_edge(phi2) then
            -- Default software reset to off unless CR says otherwise
            sw_reset <= '0';
            
            tx_ack_sync   <= tx_ack_sync(0) & tx_ack;
            tx_ack_prev   <= tx_ack_sync(1);
            rx_ack_sync   <= rx_ack_sync(0) & rx_ack;
            rx_ack_prev   <= rx_ack_sync(1);
            tx_ready_sync <= tx_ready_sync(0) & tx_ready;
            tx_ready_prev <= tx_ready_sync(1);
        
            -- must be released as soon as possible
            if tx_ready_sync(1) = '0' and tx_ready_prev = '1' then
                tx_req <= '0';
            end if;
                
            -- rising edge of tx ack uart_send ready to send another byte
            if tx_ack_sync(1) = '1' and tx_ack_prev = '0' then
                tdre    <= '1';
            end if;

            -- rising edge of rx ack new byte received ready to capture
            if rx_ack_sync(1) = '1' and rx_ack_prev = '0' then
                rdr <= rx_data;
                if rdrf = '1' then
                    ovrn <= '1';
                end if;
                rdrf   <= '1';
            end if;

            if cs_n = '0' then
                if address = '0' then
                    if rw = '0' then
                        cr <= data_in;
                        if data_in(1 downto 0) = "11" then
                            sw_reset <= '1';
                            tdre     <= '1';
                            rdrf     <= '0';
                        end if;
                    else
                        data_out <= status_reg;
                    end if;
                else
                    if rw = '0' then 
                        tx_data   <= data_in;
                        tx_req    <= '1'; 
                        tdre      <= '0';
                    else -- Read RDR
                        data_out <= rdr;
                        rdrf     <= '0';
                        ovrn     <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;

