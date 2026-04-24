library ieee;
    use ieee.std_logic_1164.all;
    use  IEEE.STD_LOGIC_ARITH.all;
    use  IEEE.STD_LOGIC_UNSIGNED.all;

entity TRS80 is
    port (
        ADC_CLK_10          : in     std_logic;
        MAX10_CLK1_50       : in     std_logic;
        MAX10_CLK2_50       : in     std_logic;

--        DRAM_ADDR           : out    std_logic_vector(12 downto 0);
--        DRAM_BA             : out    std_logic_vector(1 downto 0);
--        DRAM_CAS_N          : out    std_logic;
--        DRAM_CKE            : out    std_logic;
--        DRAM_CLK            : out    std_logic;
--        DRAM_CS_N           : out    std_logic;
--        DRAM_DQ             : inout  std_logic_vector(15 downto 0);
--        DRAM_LDQM           : out    std_logic;
--        DRAM_RAS_N          : out    std_logic;
--        DRAM_UDQM           : out    std_logic;
--        DRAM_WE_N           : out    std_logic;

        HEX0                : out    std_logic_vector(7 downto 0);
        HEX1                : out    std_logic_vector(7 downto 0);
        HEX2                : out    std_logic_vector(7 downto 0);
        HEX3                : out    std_logic_vector(7 downto 0);
        HEX4                : out    std_logic_vector(7 downto 0);
        HEX5                : out    std_logic_vector(7 downto 0);

        KEY                 : in     std_logic_vector(1 downto 0);

        LEDR                : out    std_logic_vector(9 downto 0);

        SW                  : in     std_logic_vector(9 downto 0);

        VGA_B               : out    std_logic_vector(3 downto 0);
        VGA_G               : out    std_logic_vector(3 downto 0);
        VGA_HS              : out    std_logic;
        VGA_R               : out    std_logic_vector(3 downto 0);
        VGA_VS              : out    std_logic;

--        GSENSOR_CS_N        : out    std_logic;
--        GSENSOR_INT         : in     std_logic_vector(2 downto 1);
--        GSENSOR_SCLK        : out    std_logic;
--        GSENSOR_SDI         : inout  std_logic;
--        GSENSOR_SDO         : inout  std_logic;

        ARDUINO_IO          : inout  std_logic_vector(15 downto 0);
        ARDUINO_RESET_N     : inout  std_logic;

        GPIO                : inout  std_logic_vector(35 downto 0)
  );
end entity;


architecture struct of TRS80 is

    component clock_divider IS
        generic (divider : integer := 4);
        port (
            reset_n  : in  std_logic := '1';
            clk_in   : in  std_logic;
            clk_out  : out std_logic
        );
    end component;


    component mc6850_uart is
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
    end component;
    
    component EBR_RAM is
        generic (
            RAM_SIZE_KB : integer := 32  -- 8, 16, 24, 32, 40, 48, 56 or 64
        );
        port (
            clock:      in std_logic;
            cs_n:       in std_logic;
            we_n:       in std_logic;
            address:    in std_logic_vector(15 downto 0);
            data_in:    in std_logic_vector(7 downto 0);
            data_out:   out std_logic_vector(7 downto 0)
        );
    end component;    
    
    component i8251_uart is
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
    end component;

    component model1v1 is
        port (
            clock:    in std_logic;
            address:  in std_logic_vector(11 downto 0); 
            cs_n:     in std_logic;
            data_out: out std_logic_vector(7 downto 0)
        );
    end component;
    
    component trs80mon is
        port (
            clock:    in std_logic;
            address:  in std_logic_vector(10 downto 0); 
            cs_n:     in std_logic;
            data_out: out std_logic_vector(7 downto 0)
        );
    end component;
    
    component model1v2 is
        port (
            clock:    in std_logic;
            address:  in std_logic_vector(13 downto 0); 
            cs_n:     in std_logic;
            data_out: out std_logic_vector(7 downto 0)
        );
    end component;
    
    component screentest is
        port (
            clock:    in std_logic;
            address:  in std_logic_vector(11 downto 0); 
            cs_n:     in std_logic;
            data_out: out std_logic_vector(7 downto 0)
        );
    end component;
    
    component hexto7seg is
        generic (SEGMENTS : integer := 8);
        port (
            hex         : in   std_logic_vector(3 downto 0);
            seg         : out  std_logic_vector(SEGMENTS-1 downto 0)
        );
    end component;
    
    component pll
        PORT
        (
            areset      : IN STD_LOGIC  := '0';
            inclk0      : IN STD_LOGIC  := '0';
            c0          : OUT STD_LOGIC ;
            locked      : OUT STD_LOGIC 
        );
    end component;

    component video_screen is
        generic(
            htotal      :   integer   := 800;
            hdisp       :   integer   := 640;
            hpol        :   std_logic := '0';
            hswidth     :   integer   := 96;
            hfp         :   integer   := 16;
            hbp         :   integer   := 48;
            vtotal      :   integer   := 525;
            vdisp       :   integer   := 480;
            vpol        :   std_logic := '0';
            vswidth     :   integer   := 2;
            vbp         :   integer   := 33;
            vfp         :   integer   := 10
        );
        port (
            reset_n     : in  std_logic;
            video_clock : in  std_logic;
            mode        : in  std_logic;
            phi2        : in  std_logic;
            rw          : in  std_logic;
            address_bus : in  std_logic_vector(15 downto 0);
            data_bus    : in  std_logic_vector(7  downto 0);
            vtxt_cs_n   : in  std_logic;
            video_data  : out std_logic_vector(7  downto 0);
            vsync       : out std_logic;
            hsync       : out std_logic;
            rgb         : out std_logic_vector(11 downto 0)
      );
    end component;   
    
    component trs80_kbd_port is
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
    end component;
    
    component ff_port is
    port (
        clk         : in  std_logic;                       
        reset_n     : in  std_logic;
        cs_n        : in  std_logic;                       
        rd_n        : in  std_logic;                       
        wr_n        : in  std_logic;                       
        data_in     : in  std_logic_vector(7 downto 0);    
        data_out    : out std_logic_vector(7 downto 0);    
        tape_in     : in  std_logic;
        tape_out    : out std_logic_vector(1 downto 0);
        motor       : out std_logic;      
        video_mode  : out std_logic
    );
    end component;

    component trs80_printer is
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
    end component;   
    
    component trs80_serial is
        generic (
            -- format encoding (same as uart_send/uart_receive):
            -- bit2: 0=7bit, 1=8bit
            -- bit1: parity enable (8bit) or stop bits (7bit: 1=1stop, 0=2stop)
            -- bit0: 0=even, 1=odd parity
            FORMAT : std_logic_vector(2 downto 0) := "100"  -- 8N1 default
        );
        port (
            cpu_clk    : in  std_logic;
            serial_clk : in  std_logic;
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
    end component;
    
    component k7_decoder is
        generic (
            -- Timing windows in cpu_clk cycles (Level II Model I, 500-baud KCS)
            CLOCK_PULSE_CYCLES : integer := 2000;   -- nominal clock-to-clock interval
            DATA_PULSE_CYCLES  : integer := 1000;   -- nominal clock-to-data interval
            TOLERANCE_CYCLES   : integer := 400;    -- ±20% window
            SILENCE_CYCLES     : integer := 8000    -- 4 cells of silence = end of transmission
        );
        port (
            cpu_clk     : in  std_logic;
            reset_n     : in  std_logic;
            motor       : in  std_logic;                       -- cassette motor on
            tape_out    : in  std_logic_vector(1 downto 0);    -- from ff_port
            bit_out     : out std_logic;                       -- decoded bit value
            bit_strobe  : out std_logic;                       -- 1 cycle pulse per bit
            byte_out    : out std_logic_vector(7 downto 0);    -- decoded byte
            byte_strobe : out std_logic                        -- 1 cycle pulse per byte
        );
    end component;
    
    component trs80_fdc is
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
    end component;
    
    signal reset_n       : std_logic;
    signal cpu_reset_n   : std_logic;
    signal cpu_reset     : std_logic;

    signal WR_n          : std_logic;
    signal RD_n          : std_logic;
    signal address_bus   : std_logic_vector(15 downto 0);
    signal cpu_data      : std_logic_vector(7 downto 0);
    signal data_bus      : std_logic_vector(7 downto 0);

    signal sfdc_data     : std_logic_vector(7 downto 0);
    signal fdc_data      : std_logic_vector(7 downto 0);
    signal ff_data       : std_logic_vector(7 downto 0);
    signal video_data    : std_logic_vector(7 downto 0);
    signal kbd_data      : std_logic_vector(7 downto 0);
    signal model1_data   : std_logic_vector(7 downto 0);
    signal ram_data      : std_logic_vector(7 downto 0);
    signal serial_data   : std_logic_vector(7 downto 0);
    signal printer_data  : std_logic_vector(7 downto 0);
    signal monrom_data   : std_logic_vector(7 downto 0);

    signal MREQ_n        : std_logic :='1';
    signal IORQ_n        : std_logic :='1';
     
    signal sfdc_cs_n     : std_logic :='1';
    signal fdc_cs_n      : std_logic :='1';
    signal drvsel_cs_n   : std_logic :='1';
    signal ff_cs_n       : std_logic :='1';
    signal ram_cs_n      : std_logic :='1';
    signal kbd_cs_n      : std_logic :='1';
    signal model1_cs_n   : std_logic :='1';
    signal video_cs_n    : std_logic :='1';
    signal serial_cs_n   : std_logic :='1';
    signal printer_cs_n  : std_logic :='1';
    signal monrom_cs_n   : std_logic :='1';
    signal monram_cs_n   : std_logic :='1';

    signal cpu_clk       : std_logic;
    signal serial_clk    : std_logic;
    signal uart_clk      : std_logic;
    signal rtc_clk       : std_logic;
    signal video_clk     : std_logic;
 
    signal rtc_clk_prev  : std_logic;
    signal rtc_cnt       : integer range 0 to 15 := 0;
    
    signal z80_int       : std_logic;
    signal rtc_int       : std_logic;
    
    signal count_down    : integer range 0 to 31 := 0;
    signal display       : std_logic_vector(23 downto 0);
        
    signal video_rgb     : std_logic_vector(11 downto 0);
    signal video_hsync   : std_logic;
    signal video_vsync   : std_logic;
    
    signal kbd_reset     : std_logic;
    signal kbd_in        : std_logic;
    signal video_mode    : std_logic;
    signal tape_out      : std_logic_vector(1 downto 0);
    signal tape_in       : std_logic;
    signal motor         : std_logic;
    signal lpt_out       : std_logic;
    signal serial_in     : std_logic;
    signal serial_out    : std_logic;
    
    
begin

    pll1: pll                          port map(areset       => not reset_n,
                                                inclk0       => MAX10_CLK1_50,
                                                c0           => video_clk,
                                                locked       => open);

    div1: clock_divider	            generic map(divider      => 50_000_000/50_000_000)
                                       port map(reset_n      => reset_n, 
                                                clk_in       => MAX10_CLK1_50,
                                                clk_out      => cpu_clk);

    div2: clock_divider	            generic map(divider      => 50_000_000/(115200*16))
                                       port map(reset_n      => reset_n, 
                                                clk_in       => MAX10_CLK1_50,
                                                clk_out      => serial_clk);

    div3: clock_divider	            generic map(divider      => 50_000_000/40)
                                       port map(reset_n      => reset_n, 
                                                clk_in       => MAX10_CLK1_50,
                                                clk_out      => rtc_clk);

    div4: clock_divider	            generic map(divider      => 50_000_000/5_068_840)
                                       port map(reset_n      => reset_n, 
                                                clk_in       => MAX10_CLK1_50,
                                                clk_out      => uart_clk);
                                                
    display <= address_bus & data_bus;
               
    
    h0 : hexto7seg                  generic map(SEGMENTS           => 8) 
                                       port map(hex                => display(3  downto  0),
                                                seg                => HEX0); 
    h1 : hexto7seg                  generic map(SEGMENTS           => 8) 
                                       port map(hex                => display(7  downto  4),
                                                seg                => HEX1); 
    h2 : hexto7seg                  generic map(SEGMENTS           => 8) 
                                       port map(hex                => display(11 downto  8),
                                                seg                => HEX2); 
    h3 : hexto7seg                  generic map(SEGMENTS           => 8) 
                                       port map(hex                => display(15 downto 12),
                                                seg                => HEX3); 
    h4 : hexto7seg                  generic map(SEGMENTS           => 8) 
                                       port map(hex                => display(19 downto 16),
                                                seg                => HEX4); 
    h5 : hexto7seg                  generic map(SEGMENTS            => 8) 
                                       port map(hex                => display(23 downto 20),
                                                seg                => HEX5);                                                 
    -- z80 interruption chain
    z80_int <=  rtc_int; -- (or flp_int or serial_int...)                                                
                                                
    cpu1 : entity work.t80s         generic map(mode         => 0, 
                                                t2write      => 1, 
                                                iowait       => 1)
                                       port map(reset_n      => cpu_reset_n,
                                                clk_n        => not cpu_clk,
                                                wait_n       => '1',
                                                int_n        => z80_int,
                                                nmi_n        => '1',
                                                busrq_n      => '1',
                                                mreq_n       => MREQ_n,
                                                iorq_n       => IORQ_n,
                                                rd_n         => RD_n,
                                                wr_n         => WR_n,
                                                a            => address_bus,
                                                di           => data_bus,
                                                do           => cpu_data);
                                                
--    rom1: model1v1                     port map(clock        => cpu_clk,
--                                                address      => address_bus(11 downto 0),
--                                                cs_n         => model1_cs_n,        
--                                                data_out     => model1_data);
                                            
    rom1: model1v2                     port map(clock        => cpu_clk,
                                                address      => address_bus(13 downto 0),
                                                cs_n         => model1_cs_n,        
                                                data_out     => model1_data);

    mon: trs80mon                      port map(clock        => cpu_clk,
                                                address      => address_bus(10 downto 0),
                                                cs_n         => monrom_cs_n,        
                                                data_out     => monrom_data);
    
    
--    rom1: screentest                   port map(clock        => cpu_clk,
--                                                address      => address_bus(11 downto 0),
--                                                cs_n         => model1_cs_n,        
--                                                data_out     => model1_data);
                                            
    ram: EBR_RAM                    generic map(RAM_SIZE_KB  => 64)
                                       port map(clock        => cpu_clk,
                                                cs_n         => ram_cs_n and monram_cs_n,
                                                we_n         => MREQ_n or WR_n or (ram_cs_n and monram_cs_n),
                                                address      => address_bus,
                                                data_in      => cpu_data,
                                                data_out     => ram_data);
                                                
    kbd: trs80_kbd_port                port map(clock        => cpu_clk,
                                                kbd_clk      => serial_clk,
                                                reset_n      => reset_n,
                                                cs_n         => kbd_cs_n,
                                                address      => address_bus(7 downto 0),
                                                data_out     => kbd_data,
                                                rx           => kbd_in,
                                                reset_out    => kbd_reset);

    ffp: ff_port                       port map(clk          => cpu_clk,
                                                reset_n      => reset_n,
                                                cs_n         => ff_cs_n,
                                                rd_n         => RD_n,
                                                wr_n         => WR_n,
                                                data_in      => cpu_data,
                                                data_out     => ff_data,
                                                tape_in      => tape_in,
                                                tape_out     => tape_out,
                                                motor        => motor,
                                                video_mode   => video_mode);
                  
   video: video_screen              generic map(htotal  => 1056,   -- total horizontal pixels per line (visible + blanking)
                                                hdisp   =>  800,   -- horizontal visible pixels
                                                hpol    =>  '1',   -- hsync polarity ('0' = active low, '1' = active high)
                                                hswidth =>  128,   -- hsync pulse width in pixels
                                                hfp     =>   40,   -- horizontal front porch in pixels
                                                hbp     =>   88,   -- horizontal back porch in pixels
                                                vtotal  =>  628,   -- total lines per frame (visible + blanking)
                                                vdisp   =>  600,   -- vertical visible lines
                                                vpol    =>  '1',   -- vsync polarity ('0' = active low, '1' = active high)
                                                vswidth =>    4,   -- vsync pulse width in lines
                                                vbp     =>   23,   -- vertical back porch in lines
                                                vfp     =>    1)   -- vertical front in lines
                                       port map(reset_n            => reset_n,
                                                video_clock        => video_clk, 
                                                mode               => video_mode,
                                                phi2               => cpu_clk,
                                                rw                 => WR_n,
                                                address_bus        => address_bus,
                                                data_bus           => cpu_data,
                                                vtxt_cs_n          => video_cs_n,
                                                video_data         => video_data,
                                                vsync              => video_vsync,
                                                hsync              => video_hsync,
                                                rgb                => video_rgb);
                                                

    prt: trs80_printer                 port map(clk                => cpu_clk,
                                                reset_n            => reset_n,
                                                serial_clk         => serial_clk,
                                                cs_n               => printer_cs_n,
                                                rd_n               => RD_n,
                                                wr_n               => WR_n,
                                                data_in            => cpu_data,
                                                data_out           => printer_data,
                                                format             => "101",
                                                tx                 => lpt_out);
                                                
    ser: trs80_serial               generic map(FORMAT             => "101")
                                       port map(cpu_clk            => cpu_clk,
                                                serial_clk         => serial_clk,
                                                reset_n            => reset_n,
                                                cs_n               => serial_cs_n,
                                                address            => address_bus(1 downto 0),
                                                rd_n               => RD_n,
                                                wr_n               => WR_n,
                                                data_in            => cpu_data,
                                                data_out           => serial_data,
                                                irq_n              => open,
                                                rx                 => serial_in,
                                                tx                 => serial_out);

        dsk: trs80_fdc                 port map(m_clk              => cpu_clk,
                                                m_reset_n          => reset_n,
                                                m_ds_cs_n          => drvsel_cs_n,
                                                m_cs_n             => fdc_cs_n,
                                                m_address          => address_bus(1 downto 0),
                                                m_wr_n             => WR_n,
                                                m_rd_n             => RD_n,
                                                m_data_in          => cpu_data,
                                                m_data_out         => fdc_data,
                                                s_clk              => cpu_clk,
                                                s_reset_n          => reset_n,
                                                s_cs_n             => sfdc_cs_n,
                                                s_address          => address_bus(2 downto 0),
                                                s_rw               => WR_n,
                                                s_data_in          => cpu_data,
                                                s_data_out         => sfdc_data);
                                                

--    k7o: k7_decoder                   port map (cpu_clk            => cpu_clk,
--                                                reset_n            => reset_n,
--                                                motor              => motor,           -- from ff_port
--                                                tape_out           => tape_out,        -- from ff_port
--                                                bit_out            => k7_bit,          -- debug
--                                                bit_strobe         => k7_bit_strobe,   -- debug
--                                                byte_out           => k7_byte,
--                                                byte_strobe        => k7_byte_strobe);

    reset_n <= KEY(0) and not kbd_reset;
    
--  Note:  MONROM is a monitor to take debug the TRS80 from a serial port    
    
    model1_cs_n   <= '0' when address_bus(15 downto 12)  < x"3"                                             and (MREQ_n = '0') else '1';
    monrom_cs_n   <= '0' when address_bus(15 downto 8)  >= x"30"    and address_bus(15 downto 8) < x"36"    and (MREQ_n = '0') else '1';  -- remote monitor rom
    monram_cs_n   <= '0' when address_bus(15 downto 8)  >= x"36"    and address_bus(15 downto 8) < x"37"    and (MREQ_n = '0') else '1';  -- remote monitor ram
    ram_cs_n      <= '0' when address_bus(15 downto 12) >= x"4"                                             and (MREQ_n = '0') else '1';
    kbd_cs_n      <= '0' when address_bus(15 downto 10)  = "001110"                                         and (MREQ_n = '0') else '1';
    video_cs_n    <= '0' when address_bus(15 downto 8)  >= x"3C"    and address_bus(15 downto 8)  < x"40"   and (MREQ_n = '0') else '1';
    drvsel_cs_n   <= '0' when address_bus(15 downto 0)  >= x"37E0"  and address_bus(15 downto 0) <= x"37E1" and (MREQ_n = '0') else '1';
    printer_cs_n  <= '0' when address_bus(15 downto 0)  >= x"37E8"  and address_bus(15 downto 0) <= x"37E9" and (MREQ_n = '0') else '1';
    fdc_cs_n      <= '0' when address_bus(15 downto 0)  >= x"37EC"  and address_bus(15 downto 0) <= x"37EF" and (MREQ_n = '0') else '1';
    
    serial_cs_n   <= '0' when address_bus(7  downto 0)  >= x"E8"    and address_bus(7  downto 0) <= x"EB"   and (IORQ_n = '0') else '1';
    ff_cs_n       <= '0' when address_bus(7  downto 0)   = x"FF"                                            and (IORQ_n = '0') else '1';
    
    -- temporary for fdc tests
    sfdc_cs_n     <= '0' when address_bus(7  downto 0)  >= x"40"    and address_bus(7 downto 0)  <= x"47"   and (IORQ_n = '0') else '1';
    
    data_bus <= cpu_data      when WR_n = '0' else  -- CPU is writing
                model1_data   when (model1_cs_n   = '0' and MREQ_n = '0' and RD_n = '0') else
                monrom_data   when (monrom_cs_n   = '0' and MREQ_n = '0' and RD_n = '0') else
                ram_data      when (monram_cs_n   = '0' and MREQ_n = '0' and RD_n = '0') else -- temporary for debug
                ram_data      when (ram_cs_n      = '0' and MREQ_n = '0' and RD_n = '0') else
                video_data    when (video_cs_n    = '0' and MREQ_n = '0' and RD_n = '0') else
                kbd_data      when (kbd_cs_n      = '0' and MREQ_n = '0' and RD_n = '0') else
                printer_data  when (printer_cs_n  = '0' and MREQ_n = '0' and RD_n = '0') else
                
                serial_data   when (serial_cs_n   = '0' and IORQ_n = '0' and RD_n = '0') else
                ff_data       when (ff_cs_n       = '0' and IORQ_n = '0' and RD_n = '0') else
                sfdc_data     when (sfdc_cs_n     = '0' and IORQ_n = '0' and RD_n = '0') else  -- temporary for debug
                x"FF";

    -- cpu_reset             
    process(cpu_clk)
    begin
        if reset_n =  '0' then
            count_down <= 0;
            cpu_reset_n <= '0';
        elsif rising_edge(cpu_clk) then
            if count_down < 31 then
                count_down <= count_down + 1;
            else
                cpu_reset_n <= '1';
            end if;
        end if;
    end process;
    
    -- rtc_int
    process(cpu_clk)
    begin
        if rising_edge(cpu_clk) then
            rtc_clk_prev <= rtc_clk;
            
            if (rtc_clk = '1' and rtc_clk_prev = '0') then
                rtc_cnt <= 4; 
            end if;
            
            if rtc_cnt /= 0 then
                rtc_int <= '0';
                rtc_cnt <= rtc_cnt - 1;
            else
                rtc_int <= '1';
            end if;
        end if;
    end process;    
    
    
    VGA_R                  <= video_rgb(11 downto 8);
    VGA_G                  <= video_rgb(7  downto 4);
    VGA_B                  <= video_rgb(3  downto 0);
    VGA_HS                 <= video_hsync;
    VGA_VS                 <= video_vsync;
    
    kbd_in                 <= ARDUINO_IO(7);
    ARDUINO_IO(1)          <= lpt_out;
    
    serial_in              <= ARDUINO_IO(2);
    ARDUINO_IO(3)          <= serial_out;
    
--    ARDUINO_IO(6 downto 5) <= tape_out;
--    ARDUINO_IO(10)         <= motor;
--    tape_in                <= ARDUINO_IO(11);
    

end;
