-- =============================================================================
-- Module  : pal_ctrl
-- Purpose : PAL composite timing controller for 16x64 / 16x32 character display
-- =============================================================================
--
-- Pixel clock: 14.75 MHz (PLL from 50 MHz)
--   htotal = hfp + hswidth + hbp + hdisp = 16 + 64 + 96 + 768 = 944
--   htotal / 14.75 MHz = 64.00 us per line  (PAL = 64.000 us)
--   hdisp  / 14.75 MHz = 52.07 us active    (fills the screen)
--   vtotal = vfp + vswidth + vbp + vdisp = 18 + 3 + 3 + 288 = 312
--   frame rate = 14.75 MHz / 944 / 312 = 50.08 Hz
--
-- Character grid (mode32 = '0'): 64 columns x 16 rows, 12 clk/char, 12 sl/row
-- Character grid (mode32 = '1'): 32 columns x 16 rows, 24 clk/char, 12 sl/row
--   (shifter runs at clk/2, so 1 real pixel = 2 clocks in 64-col mode,
--    and 1 real pixel = 4 clocks in 32-col mode)
--   Glyph: 6 pixels wide (bits 7..2 of ROM byte, bits 1..0 ignored)
--          12 scanlines per row (ROM rows 12..15 ignored)
--   16 x 12 = 192 scanlines displayed inside the 288-line window
--
-- Centering: internal margin constants shrink the active character window
--   inside the display area, same technique as video_ctrl.vhd
--
-- Composite sync at top level:
--   sync <= hsync and vsync;   -- both active low, AND gives composite
--
-- Output signals:
--   hsync   : horizontal sync (active low)
--   vsync   : vertical sync   (active low)
--   enable  : high when hpos/vpos inside active window
--   blank   : high inside window but nothing to draw
--   load    : strobe to load shift register for next character cell
--   address : character RAM address (vcpos * cols + hcpos)
--   row     : scanline index within character cell (0..11)
--   mode32  : '0' = 64 cols/6 px, '1' = 32 cols/12 px
-- =============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity pal_ctrl is
    generic(
        htotal  : integer := 944;   -- total pixels per line
        hdisp   : integer := 768;   -- visible pixels
        hswidth : integer := 64;    -- hsync pulse width
        hfp     : integer := 16;    -- horizontal front porch
        hbp     : integer := 96;    -- horizontal back porch
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
end pal_ctrl;

architecture behavior of pal_ctrl is
begin
    process (reset_n, clock)
        variable hpos     : integer range 0 to htotal - 1 := 0;
        variable vpos     : integer range 0 to vtotal - 1 := 0;
        variable next_evt : integer range 0 to htotal - 1 := 0;
        variable hcpos    : integer range 0 to 63;
        variable vcpos    : integer range 0 to 15;
        variable sline    : integer range 0 to 11;
        variable char_w   : integer range 6 to 32;
        variable preload  : integer range 9 to 32;
        variable cols     : integer range 32 to 64;

        -- shdisp : hfp + hswidth + hbp = 46 + 64 + 130 = 240
        -- ehdisp : shdisp + hdisp      = 240 + 704 = 944 = htotal
        constant shdisp  : integer := hfp + hswidth + hbp;
        constant ehdisp  : integer := hfp + hswidth + hbp + hdisp;

        -- svdisp : vfp + vswidth + vbp = 18 + 3 + 3 = 24
        -- evdisp : svdisp + vdisp      = 24 + 288 = 312 = vtotal
        constant svdisp  : integer := vfp + vswidth + vbp;
        constant evdisp  : integer := vfp + vswidth + vbp + vdisp;

        -- Centering margins (pixels/lines to skip inside the display window)
        -- 64 cols x 6 px  = 384 active px; (704-384)/2 = 160 left/right
        -- 32 cols x 12 px = 384 active px; same margins (same screen area)
        -- 16 rows x 12 sl = 192 active lines; (288-192)/2 = 48 top/bottom
        -- Adjust these constants to move the image on screen
        constant margin_left   : integer := 160;
        constant margin_right  : integer := 160;
        constant margin_top    : integer := 48;
        constant margin_bottom : integer := 48;

        -- Active character window inside the display area
        constant shdispm : integer := shdisp + margin_left;
        constant ehdispm : integer := ehdisp - margin_right;
        constant svdispm : integer := svdisp + margin_top;
        constant evdispm : integer := evdisp - margin_bottom;

        constant char_h  : integer := 12;   -- 12 scanlines per char cell
        constant nrows   : integer := 16;   -- 16 character rows

    begin
        if reset_n = '0' then
            hpos    := 0;
            vpos    := 0;
            sline   := 0;
            hcpos   := 0;
            vcpos   := 0;
            hsync   <= '1';
            vsync   <= '1';
            enable  <= '0';
            blank   <= '1';
            load    <= '0';

        elsif rising_edge(clock) then

            -- mode-dependent char width / preload / column count
            -- char_w = 6 real pixels * (2 clk/pixel in 64-col, 4 clk/pixel in 32-col)
            -- preload = char_w + 1 to cover 1-clock address/ROM pipeline
            if mode32 = '1' then
                char_w  := 24;
                preload := 25;
                cols    := 32;
            else
                char_w  := 12;
                preload := 13;
                cols    := 64;
            end if;

            -- horizontal counter
            if hpos < htotal - 1 then
                hpos := hpos + 1;
            else
                hpos     := 0;
                next_evt := shdispm - preload;
                hcpos    := 0;

                -- vertical counter
                if vpos < vtotal - 1 then
                    vpos := vpos + 1;
                    if vpos >= svdispm and vpos < evdispm then
                        if sline < char_h - 1 then
                            sline := sline + 1;
                        else
                            sline := 0;
                            if vcpos < nrows - 1 then
                                vcpos := vcpos + 1;
                            end if;
                        end if;
                    else
                        vcpos := 0;
                        sline := 0;
                    end if;
                else
                    vpos := 0;
                end if;
            end if;

            -- hsync: active low during hswidth pixels after front porch
            if hpos >= hfp and hpos < hfp + hswidth then
                hsync <= '0';
            else
                hsync <= '1';
            end if;

            -- vsync: active low during vswidth lines after vertical front porch
            if vpos >= vfp and vpos < vfp + vswidth then
                vsync <= '0';
            else
                vsync <= '1';
            end if;

            -- active display window
            if vpos >= svdisp and vpos < evdisp then
                if hpos >= shdisp and hpos < ehdisp then
                    enable <= '1';
                else
                    enable <= '0';
                end if;

                -- blank outside the margined character window
                if vpos < svdispm or vpos >= evdispm or
                   hpos < shdispm or hpos >= ehdispm then
                    blank <= '1';
                else
                    blank <= '0';
                end if;

                if hpos = next_evt then
                    address <= std_logic_vector(to_unsigned(vcpos * cols + hcpos, 10));
                    row     <= std_logic_vector(to_unsigned(sline, 4));
                    load    <= '1';
                    if hpos < ehdispm then
                        next_evt := next_evt + char_w;
                    end if;
                    if hcpos < cols - 1 then
                        hcpos := hcpos + 1;
                    end if;
                else
                    load <= '0';
                end if;

            else
                enable <= '0';
                blank  <= '1';
                load   <= '0';
            end if;

        end if;
    end process;

end behavior;