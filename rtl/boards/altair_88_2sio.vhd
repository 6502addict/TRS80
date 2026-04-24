library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

-- MITS Altair 88-2SIO Serial I/O Board
-- Two MC6850 ACIA ports
-- Address map (base address set by generic, default 0x10 = octal 020):
--   base+0 : Port 0 Control (write) / Status (read)
--   base+1 : Port 0 Data
--   base+2 : Port 1 Control (write) / Status (read)
--   base+3 : Port 1 Data

entity altair_88_2sio is
    port (
        cpu_clk     : in  std_logic;
        serial_clk  : in  std_logic;        -- 16x baud clock
        reset_n     : in  std_logic;

        -- CPU interface (8-bit I/O address)
        address     : in  std_logic_vector(1 downto 0);
        data_in     : in  std_logic_vector(7 downto 0);
        data_out    : out std_logic_vector(7 downto 0);
        cs_n        : in  std_logic;
        rd_n        : in  std_logic;
        wr_n        : in  std_logic;

        -- Interrupt outputs
        irq_n       : out std_logic;

        -- Port 0 serial
        uart0_rx    : in  std_logic;
        uart0_tx    : out std_logic;

        -- Port 1 serial
        uart1_rx    : in  std_logic;
        uart1_tx    : out std_logic
    );
end entity altair_88_2sio;

architecture rtl of altair_88_2sio is

    component mc6850_uart is
        port (
            phi2        : in  std_logic;
            serial_clk  : in  std_logic;
            reset_n     : in  std_logic;
            cs_n        : in  std_logic;
            rw          : in  std_logic;
            address     : in  std_logic;
            data_in     : in  std_logic_vector(7 downto 0);
            data_out    : out std_logic_vector(7 downto 0);
            irq_n       : out std_logic;
            rx          : in  std_logic;
            tx          : out std_logic
        );
    end component;

    signal cs0_n      : std_logic;
    signal cs1_n      : std_logic;
    signal irq0_n     : std_logic;
    signal irq1_n     : std_logic;
    signal uart0_data : std_logic_vector(7 downto 0);
    signal uart1_data : std_logic_vector(7 downto 0);

begin

    -- address decode: base+0/1 = port 0, base+2/3 = port 1
    cs0_n <= '0' when cs_n = '0' and address(1) = '0' else '1';
    cs1_n <= '0' when cs_n = '0' and address(1) = '1' else '1';

    irq_n <= irq0_n and irq1_n; 
    
    -- data bus mux
    data_out <= uart0_data when cs0_n = '0' and rd_n = '0' else
                uart1_data when cs1_n = '0' and rd_n = '0' else
                (others => '0');

    port0: mc6850_uart        port map (phi2       => cpu_clk,
                                        serial_clk => serial_clk,
                                        reset_n    => reset_n,
                                        cs_n       => cs0_n,
                                        rw         => wr_n,
                                        address    => address(0),
                                        data_in    => data_in,
                                        data_out   => uart0_data,
                                        irq_n      => irq0_n,
                                        rx         => uart0_rx,
                                        tx         => uart0_tx);

    port1: mc6850_uart        port map (phi2       => cpu_clk,
                                        serial_clk => serial_clk,
                                        reset_n    => reset_n,
                                        cs_n       => cs1_n,
                                        rw         => wr_n,
                                        address    => address(0),
                                        data_in    => data_in,
                                        data_out   => uart1_data,
                                        irq_n      => irq1_n,
                                        rx         => uart1_rx,
                                        tx         => uart1_tx
        );

end architecture rtl;