library IEEE;
    use IEEE.std_logic_1164.all;
    use ieee.numeric_std.all; 
    use IEEE.math_real.all;


entity video_screen is
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
        blink_clock : in  std_logic;
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
end video_screen;

architecture behavior of video_screen is


component video_ctrl IS
    generic(
        htotal      : integer   := 800;
        hdisp       : integer   := 640;
        hpol        : std_logic := '1';
        hswidth     : integer   := 96;    
        hfp         : integer   := 16;
        hbp         : integer   := 48;
        vtotal      : integer   := 525;
        vdisp       : integer   := 480;
        vpol        : std_logic := '1';
        vswidth     : integer   := 2;
        vbp         : integer   := 33;
        vfp         : integer   := 10
    );
    port(
        reset_n     : in  std_logic;
        clock       : in  std_logic;
        ctrl        : in  std_logic_vector(7 downto 0);
        vsync       : out std_logic;
        hsync       : out std_logic;
        enable      : out std_logic;
        blank       : out std_logic;
        load        : out std_logic;
        row         : out std_logic_vector(2 downto 0); 
        address     : out std_logic_vector(9 downto 0)
    );
end component;

component video_charset_2513 is
    port (
        clock   : in  std_logic;
        rden    : in  std_logic;
        address : in  std_logic_vector(10 downto 0);
        q       : out std_logic_vector(7 downto 0)
    );
end component;

component video_ram is
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

component video_shifter is
    port (
        clock    : in  std_logic;
        mode80   : in  std_logic;                     -- ctrl(0): '1'=80col '0'=40col
        data     : in  std_logic_vector(7 downto 0);
        load     : in  std_logic;
        shiftout : out std_logic
    );
end component;

component video_dac is
    port(
        clock       : in  std_logic;
        enable      : in  std_logic;
        blank       : in  std_logic;
        pixel       : in  std_logic;
        rgb         : out std_logic_vector(11 downto 0)
    );
end component;


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
signal chs_row      : std_logic_vector(2  downto 0);
signal chs_data     : std_logic_vector(7  downto 0);
signal txt_data     : std_logic_vector(7  downto 0);
signal aux_data     : std_logic_vector(7  downto 0);

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
signal attr_d1       : std_logic_vector(7 downto 0) := x"00";
signal attr_d2       : std_logic_vector(7 downto 0) := x"00";


-- video control register
signal ctrl         : std_logic_vector(7 downto 0)  := x"00";

begin
    txt_wren              <= '1' when vtxt_cs_n = '0' and rw = '0' else '0';
    txt_rden              <= '1' when vtxt_cs_n = '0' and rw = '1' else '0';

    chs_addr(2 downto 0)  <= chs_row;
    chs_addr(9 downto 3)  <= glyph(6 downto 0);
    chs_addr(10)          <= '0';

    vg: video_ctrl         generic map (htotal      => htotal,
                                        hdisp       => hdisp,
                                        hpol        => hpol,
                                        hswidth     => hswidth,
                                        hfp         => hfp,
                                        hbp         => hbp,
                                        vtotal      => vtotal,
                                        vdisp       => vdisp,
                                        vpol        => vpol,
                                        vswidth     => vswidth,
                                        vbp         => vbp,
                                        vfp         => vfp)
                              port map (reset_n     => reset_n,
                                        clock       => video_clock,
                                        ctrl        => ctrl,
                                        vsync       => vsync_d0,
                                        hsync       => hsync_d0,
                                        enable      => enable_d0,
                                        blank       => blank_d0,
                                        load        => load,
                                        row         => chs_row,
                                        address     => cell_addr);
                                    
    vr: video_ram          generic map (SIZE_BYTES  => 1024)
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


    c0: video_charset_2513    port map (address     => chs_addr,
                                        rden        => load_chs,
                                        clock       => video_clock,
                                        q           => chs_data);
 
    sr: video_shifter         port map (clock       => video_clock,
                                        mode80      => ctrl(0),
                                        data        => chs_data,
                                        load        => load_sr,
                                        shiftout    => pixel);

    vd: video_dac             port map (clock       => video_clock,
                                        enable      => enable,
                                        blank       => blank,
                                        pixel       => pixel,
                                        rgb         => rgb);
                  
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

            -- attributes syncrhonization
            attr_d1   <= attr;
            attr_d2   <= attr_d1;
        end if;
    end process;

    video_data <= txt_data;
    
end behavior;
