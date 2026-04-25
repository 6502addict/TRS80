-- =============================================================================
-- Module  : trs80_kbd_port
-- Purpose : TRS-80 Model I keyboard matrix, fed by UART make/break stream
-- =============================================================================
--
-- Receives matrix events from an external source (Xiao RP2040) over UART
-- and maintains an 8x8 bit matrix. The Z80 reads the matrix as memory-mapped
-- at $3800..$3BFF: each address bit A0..A7 selects one matrix row; the read
-- returns the OR of all selected rows (authentic TRS-80 Model I behavior).
--
-- Wire protocol (115200 baud, 8N1):
--   0x00..0x3F  = matrix make     (position = row*8 + col, row bits 5..3, col bits 2..0)
--   0x55        = RESET pulse     (pulse reset_out for one clock)
--   0x80..0xBF  = matrix break    (position = byte and 0x7F)
--   all other   = ignored
--
-- CPU interface:
--   Read-only. address(7..0) selects rows. data_out = OR of selected rows.
--   cs_n active low during $3800..$3BFF reads.
--
-- =============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity trs80_kbd_port is
    port (
        clock     : in  std_logic;                        -- CPU/bus clock
        kbd_clk   : in  std_logic;                        -- 1.8432 MHz (16x 115200 baud)
        reset_n   : in  std_logic;
        cs_n      : in  std_logic;                        -- active low during $3800..$3BFF
        address   : in  std_logic_vector(7 downto 0);     -- row select: each bit selects a row
        data_out  : out std_logic_vector(7 downto 0);     -- OR of selected rows
        rx        : in  std_logic;                        -- UART from Xiao
        reset_out : out std_logic                         -- pulses high for one clock on 0x55
    );
end entity trs80_kbd_port;

architecture rtl of trs80_kbd_port is

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

    -- Matrix storage: 8 rows of 8 bits each
    type matrix_t is array(0 to 7) of std_logic_vector(7 downto 0);
    signal matrix : matrix_t := (others => (others => '0'));

    -- UART receive signals (kbd_clk domain)
    signal rx_ready      : std_logic;
    signal rx_ack        : std_logic;
    signal rx_data       : std_logic_vector(7 downto 0);

    -- rx_ack synchronized to clock domain + edge detect
    signal rx_ack_sync   : std_logic_vector(1 downto 0) := "00";
    signal rx_ack_prev   : std_logic := '0';

begin

    recv: uart_receive port map (clk          => kbd_clk,
                                 reset_n      => reset_n,
                                 rx           => rx,
                                 format       => "101",     -- 8N1
                                 req          => '1',       -- always accept bytes
                                 ready        => rx_ready,
                                 ack          => rx_ack,
                                 data_out     => rx_data,
                                 parity_error => open);

    -- Matrix update + RESET pulse on rising edge of rx_ack
    process(clock)
        variable pos : integer range 0 to 63;
        variable row : integer range 0 to 7;
        variable col : integer range 0 to 7;
    begin
        if rising_edge(clock) then
            reset_out <= '0';  -- default: no pulse

            if reset_n = '0' then
                matrix      <= (others => (others => '0'));
                rx_ack_sync <= "00";
                rx_ack_prev <= '0';
            else
                -- Synchronize rx_ack from kbd_clk domain
                rx_ack_sync <= rx_ack_sync(0) & rx_ack;
                rx_ack_prev <= rx_ack_sync(1);

                -- Rising edge of synchronized rx_ack: a new byte is valid
                if rx_ack_sync(1) = '1' and rx_ack_prev = '0' then
                    case rx_data is
                        when x"55" =>
                            reset_out <= '1';

                        when others =>
                            pos := to_integer(unsigned(rx_data(5 downto 0)));
                            row := pos / 8;
                            col := pos mod 8;
                            if rx_data(7) = '0' and rx_data(6) = '0' then
                                -- make: 0x00..0x3F
                                matrix(row)(col) <= '1';
                            elsif rx_data(7) = '1' and rx_data(6) = '0' then
                                -- break: 0x80..0xBF
                                matrix(row)(col) <= '0';
                            end if;
                            -- 0x40..0x54, 0x56..0x7F, 0xC0..0xFF: ignored (bit 6 set)
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- Bus read: asynchronous OR of selected rows (authentic TRS-80 behavior)
    process(cs_n, address, matrix)
        variable acc : std_logic_vector(7 downto 0);
    begin
        if cs_n = '0' then
            acc := (others => '0');
            for r in 0 to 7 loop
                if address(r) = '1' then
                    acc := acc or matrix(r);
                end if;
            end loop;
            data_out <= acc;
        else
            data_out <= (others => '0');
        end if;
    end process;

end architecture rtl;