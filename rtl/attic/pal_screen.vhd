library IEEE;
    use IEEE.std_logic_1164.all;
    use ieee.numeric_std.all; 
    use IEEE.math_real.all;


entity pal_screen is
    generic(
        htotal  : integer := 911;   -- total pixels per line
        hdisp   : integer := 640;   -- visible pixels
        hswidth : integer := 68;    -- hsync pulse width (4.75 µs)
        hfp     : integer := 24;    -- horizontal front porch
        hbp     : integer := 179;   -- horizontal back porch
        vtotal  : integer := 262;   -- total lines per frame
        vdisp   : integer := 192;   -- visible lines (24 rows x 8 scanlines)
        vswidth : integer := 3;     -- vsync pulse width in lines
        vfp     : integer := 32;    -- vertical front porch
        vbp     : integer := 35     -- vertical back porch
    );
    port (
        reset_n     : in  std_logic;
        video_clock : in  std_logic;
        mode32      : in  std_logic;
        phi2        : in  std_logic;
        rw          : in  std_logic;
        address_bus : in  std_logic_vector(15 downto 0);
        data_bus    : in  std_logic_vector(7  downto 0);
        vtxt_cs_n   : in  std_logic;
        video_data  : out std_logic_vector(7  downto 0);
        sync        : out std_logic;
        video       : out std_logic
  );
end pal_screen;

architecture behavior of pal_screen is


    component pal_ctrl is
        generic(
            htotal  : integer := 944;   -- total pixels per line
            hdisp   : integer := 704;   -- visible pixels
            hswidth : integer := 64;    -- hsync pulse width
            hfp     : integer := 46;    -- horizontal front porch
            hbp     : integer := 130;   -- horizontal back porch
            vtotal  : integer := 312;   -- total lines per frame
            vdisp   : integer := 288;   -- vertical visible lines
            vswidth : integer := 3;     -- vsync pulse width in lines
            vfp     : integer := 18;    -- vertical front porch
            vbp     : integer := 3      -- vertical back porch
        );
        port(
            reset_n : in  std_logic;
            clock   : in  std_logic;                        -- 14.75 MHz pixel clock
            mode32  : in  std_logic;                        -- '0'=64 cols, '1'=32 cols
            hsync   : out std_logic;                        -- horizontal sync (active low)
            vsync   : out std_logic;                        -- vertical sync   (active low)
            enable  : out std_logic;                        -- pixel valid
            blank   : out std_logic;                        -- blank pixel
            load    : out std_logic;                        -- shift register load strobe
            row     : out std_logic_vector(3 downto 0);     -- scanline within cell (0..11)
            address : out std_logic_vector(9 downto 0)      -- char RAM address
        );
    end component;

    component pal_charset_trs80 is
        port (
            clock   : in  std_logic;
            rden    : in  std_logic;
            address : in  std_logic_vector(10 downto 0);
            q       : out std_logic_vector(7  downto 0)
        );
    end component;

    component pal_ram is
        generic (
            SIZE_BYTES : positive := 512
        );
        port (
            address_a : in  std_logic_vector(integer(ceil(log2(real(SIZE_BYTES))))-1 downto 0);
            address_b : in  std_logic_vector(integer(ceil(log2(real(SIZE_BYTES))))-1 downto 0);
            clock_a   : in  std_logic;
            clock_b   : in  std_logic;
            data_a    : in  std_logic_vector(7 downto 0);
            data_b    : in  std_logic_vector(7 downto 0);
            rden_a    : in  std_logic := '1';
            rden_b    : in  std_logic := '1';
            wren_a    : in  std_logic := '0';
            wren_b    : in  std_logic := '0';
            q_a       : out std_logic_vector(7 downto 0);
            q_b       : out std_logic_vector(7 downto 0)
        );
    end component;

    component pal_shifter is
        port (
            clock    : in  std_logic;
            data     : in  std_logic_vector(7 downto 0);
            load     : in  std_logic;
            shiftout : out std_logic
        );
    end component;


signal vsync        : std_logic;
signal hsync        : std_logic;
signal pixel        : std_logic;
signal enable       : std_logic;
signal blank        : std_logic;
signal load         : std_logic;
signal load_sr      : std_logic;
signal load_d1      : std_logic;
signal load_chs     : std_logic;
signal reverse      : std_logic;
signal cell_addr    : std_logic_vector(9  downto 0);
signal glyph        : std_logic_vector(7  downto 0);
signal attr         : std_logic_vector(7  downto 0);
signal chs_addr     : std_logic_vector(10 downto 0);
signal chs_row      : std_logic_vector(3  downto 0);
signal chs_data     : std_logic_vector(7  downto 0);
signal txt_data     : std_logic_vector(7  downto 0);

signal txt_wren     : std_logic;
signal txt_rden     : std_logic;

signal vsync_d0      : std_logic;
signal hsync_d0      : std_logic;
signal enable_d0     : std_logic;
signal blank_d0      : std_logic;
signal vsync_d1      : std_logic;
signal hsync_d1      : std_logic;
signal enable_d1     : std_logic;
signal blank_d1      : std_logic;
signal vsync_d2      : std_logic;
signal hsync_d2      : std_logic;
signal enable_d2     : std_logic;
signal blank_d2      : std_logic;


begin
    txt_wren              <= '1' when vtxt_cs_n = '0' and rw = '0' else '0';
    txt_rden              <= '1' when vtxt_cs_n = '0' and rw = '1' else '0';

    chs_addr(3  downto 0)  <= chs_row;
    chs_addr(10 downto 4)  <= glyph(6 downto 0);

    vg: pal_ctrl           generic map (htotal      => htotal,
                                        hdisp       => hdisp,
                                        hswidth     => hswidth,
                                        hfp         => hfp,
                                        hbp         => hbp,
                                        vtotal      => vtotal,
                                        vdisp       => vdisp,
                                        vswidth     => vswidth,
                                        vbp         => vbp,
                                        vfp         => vfp)
                              port map (reset_n     => reset_n,
                                        clock       => video_clock,
                                        mode32      => mode32,
                                        vsync       => vsync_d0,
                                        hsync       => hsync_d0,
                                        enable      => enable_d0,
                                        blank       => blank_d0,
                                        load        => load,
                                        row         => chs_row,
                                        address     => cell_addr);
                                    
    vr: pal_ram            generic map (SIZE_BYTES  => 1024)
                              port map (address_a   => address_bus(9 downto 0),
                                        address_b   => cell_addr,
                                        clock_a     => phi2,   
                                        clock_b     => video_clock,
                                        data_a      => data_bus,
                                        data_b      => "00000000",
                                        rden_a      => txt_rden,
                                        rden_b      => load,
                                        wren_a      => txt_wren,
                                        wren_b      => '0',
                                        q_a         => txt_data,
                                        q_b         => glyph);

    c1: pal_charset_trs80     port map (address     => chs_addr(10 downto 0),
                                        rden        => load_chs,
                                        clock       => video_clock,
                                        q           => chs_data);
 
    sr: pal_shifter           port map (clock       => video_clock,
                                        data        => chs_data,
                                        load        => load_sr,
                                        shiftout    => pixel);

    vsync     <= vsync_d2;
    hsync     <= hsync_d2;
    enable    <= enable_d2;
    blank     <= blank_d2;

    process(video_clock)
    begin
        if rising_edge(video_clock) then
            -- load synchronization
            load_d1   <= load;
            load_chs  <= load_d1;
            load_sr   <= load_chs;
            
            -- vsync / hsync syncrhonization
            vsync_d1  <= vsync_d0;
            vsync_d2  <= vsync_d1;
            hsync_d1  <= hsync_d0;
            hsync_d2  <= hsync_d1;
            
            -- enable syncrhonization
            enable_d1 <= enable_d0;
            enable_d2 <= enable_d1;
            
            -- blanking syncrhonization
            blank_d1  <= blank_d0;
            blank_d2  <= blank_d1;
        end if;
    end process;

    video      <= pixel and enable and not blank;
    sync       <= hsync and vsync;
    
    video_data <= txt_data;
end behavior;
