-- =============================================================================
-- Module  : video_ctrl
-- Purpose : VGA timing controller with character grid management
-- =============================================================================
--
-- Generates standard VGA sync signals (hsync, vsync) and all control signals
-- needed to drive a character-based video display.
--
-- Default timing: 800x600 @ 60Hz (pixel clock 40 MHz)
--   htotal = hswidth + hbp + hdisp + hfp = 128 + 88 + 800 + 40 = 1056
--   vtotal = vswidth + vbp + vdisp + vfp =   4 + 23 + 600 +  1 =  628
--   hpol = vpol = '1'  (positive sync for 800x600 @ 60Hz)
--
--   64 chars x 16 rows, 12 pixel-clocks/char
--
-- 32-col mode on TRS-80 Model 1 is implemented as: VRAM stays 64-wide, but
-- only even-indexed columns are read, and each character is displayed at
-- double width (24 pixel-clocks instead of 12). This matches the original
-- hardware behavior where the MODSEL bit stretches chars horizontally.
--
-- The character grid is vertically centered inside the 600-line display area.
-- Top and bottom margins are output as blank pixels.
--
-- For each character cell, load_sr is asserted one character-width ahead of
-- the first pixel, giving downstream logic time to load the shift register.
-- address and row are presented at the same time as load.
--
-- Output signals:
--   enable   : high when current pixel is inside the 800x600 active window
--   blank    : high when inside the window but nothing to draw (margins or inter-row gap)
--   load     : strobe to load the shift register for the next character cell
--   address  : character RAM address (vcpos * 64 + hcpos)
--   row      : scanline index within the current character cell (0..7)
-- =============================================================================

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity video_ctrl IS
    generic(
        htotal  : integer   := 1056;                             -- total horizontal pixels per line (visible + blanking)
        hdisp   : integer   := 800;                              -- horizontal visible pixels
        hpol    : std_logic := '1';                              -- hsync polarity ('0' = active low, '1' = active high)
        hswidth : integer   := 128;                              -- hsync pulse width in pixels
        hfp     : integer   := 40;                               -- horizontal front porch in pixels
        hbp     : integer   := 88;                               -- horizontal back porch in pixels
        vtotal  : integer   := 628;                              -- total lines per frame (visible + blanking)
        vdisp   : integer   := 600;                              -- vertical visible lines
        vpol    : std_logic := '1';                              -- vsync polarity ('0' = active low, '1' = active high)
        vswidth : integer   := 4;                                -- vsync pulse width in lines
        vbp     : integer   := 23;                               -- vertical back porch in lines
        vfp     : integer   := 1                                 -- vertical front porch in lines
    );
    port(
        reset_n     : in  std_logic;                             -- reset signal
        clock       : in  std_logic;                             -- video clock
        vsync       : out std_logic;                             -- vertical sync
        hsync       : out std_logic;                             -- horizontal sync
        enable      : out std_logic;                             -- pixel valid
        blank       : out std_logic;                             -- blank pixel
        load        : out std_logic;                             -- load registers
        row         : out std_logic_vector(3 downto 0);          -- row inside the font
        address     : out std_logic_vector(9 downto 0)           -- character RAM address
    );
end video_ctrl;

architecture behavior OF video_ctrl IS
begin
    process (reset_n, clock)
        variable hpos       : integer range 0 TO htotal - 1 := 0; -- current horizontal pixel counter
        variable vpos       : integer range 0 TO vtotal - 1 := 0; -- current vertical line counter
        variable next_evt   : integer range 0 to htotal - 1 := 0; -- hpos value for next SR load
        variable hcpos      : integer range 0 to 64;              -- character column counter (0..64; 64 = end-of-line sentinel)
        variable vcpos      : integer range 0 to 16;              -- current character row (0..15, +1 guard)
        variable sline      : integer range 0 to 8;               -- scanline within current char cell

        -- Horizontal display window boundaries (pixel clock units)
        --   shdisp : first visible pixel = hswidth + hbp
        --   ehdisp : last+1 visible pixel = shdisp + hdisp
        constant shdisp : integer := hswidth + hbp;          -- 128 + 88        = 216
        constant ehdisp : integer := hswidth + hbp + hdisp;  -- 128 + 88 + 800  = 1016

        -- Vertical display window boundaries (line units)
        constant svdisp : integer := vswidth + vbp;          -- 4 + 23          = 27
        constant evdisp : integer := vswidth + vbp + vdisp;  -- 4 + 23 + 600    = 627

        -- Character cell width in pixel clocks
        --   64-col: 12 clk/char (64 * 12 = 768 active clocks, 16 px margin each side)
        constant char_w : integer := 12;

        -- Character cell height in scanlines (text mode: 8 visible + 1 blank = 9 total vpos pairs)
        constant char_h_text : integer := 12;  -- was 8

        -- Number of character columns
        constant cols : integer := 64;

        -- Shift register preload offset (pixels before shdisp)
        --   preload = char_width + 3-cycle pipeline (load -> load_d1 -> load_chs -> load_sr)
        constant preload : integer := char_w + 4;      -- 15

        -- Horizontal centering: 800 - 768 = 32 px total, 16 each side
        -- (same for both modes since 64*12 = 32*24 = 768)
        constant hmargin_left : integer := 16;

        -- Vertical centering margins (in vpos units; vpos counts full scanlines,
        -- char row logic runs at half rate so 1 char line = 2 vpos units)
        -- 16 rows x 9 lines x 2 = 288 active vpos; (600-288)/2 = 156 top/bottom
        constant scanlines : integer := char_h_text;
        constant tmargin   : integer := svdisp + 92; -- was 108
        constant bmargin   : integer := evdisp - 92; -- was 108
 
    BEGIN
        if (reset_n = '0') then
            hpos     := 0;
            vpos     := 0;
            sline    := 0;
            hcpos    := 0;
            vcpos    := 0;
            hsync    <= not hpol;
            vsync    <= not vpol;
            enable   <= '0';
            blank    <= '0';
            load     <= '0';

        elsif rising_edge(clock) then
            -- Advance horizontal counter; on end of line, advance vertical counter
            if (hpos < htotal - 1) then
                hpos := hpos + 1;
            else
                hpos := 0;
                -- First SR load event is preload clocks before the (margined) display start
                next_evt := shdisp + hmargin_left - preload;
                hcpos    := 0;

                if (vpos < vtotal - 1) then
                    vpos := vpos + 1;
                    -- Character row logic runs only on even vpos lines (half-rate)
                    if vpos mod 2 = 0 then
                        if (vpos >= tmargin) then
                            if sline < scanlines then
                                sline := sline + 1;
                            else
                                sline := 0;
                                if vcpos < 16 then
                                    vcpos := vcpos + 1;
                                end if;
                            end if;
                        else
                            vcpos := 0;
                            sline := 0;
                        end if;
                    end if;
                else
                    vpos := 0;
                end if;
            end if;

            -- vsync: active (vpol polarity) during the first vswidth lines
            if (vpos < vswidth) then
                vsync <= vpol;
            else
                vsync <= not vpol;
            end if;
            -- hsync: active (hpol polarity) during the first hswidth pixels
            if (hpos < hswidth) then
                hsync <= hpol;
            else
                hsync <= not hpol;
            end if;

            -- Active vertical display area
            if ((vpos >= svdisp) and (vpos < evdisp)) then

                -- Pixel enable: high only within the horizontal display window
                if (hpos >= shdisp) and (hpos < ehdisp) then
                    enable <= '1';
                else
                    enable <= '0';
                end if;

                -- Blank: active on the inter-row blank scanline or outside char margins
                if (sline = char_h_text) or (vpos < tmargin) or (vpos >= bmargin) then
                    blank <= '1';
                else
                    blank <= '0';
                end if;

                -- Shift register load: fires one char_width before each character cell.
                -- hcpos is an explicit counter (incremented after each load, reset at EOL).
                if hpos = next_evt and hcpos < cols then
                    address <= std_logic_vector(to_unsigned(vcpos * cols + hcpos, 10));
                    row     <= std_logic_vector(to_unsigned(sline, 4));
                    load    <= '1';
                    next_evt := next_evt + char_w;
                    hcpos    := hcpos + 1;
                else
                    load <= '0';
                end if;
            end if;
        end if;
    end process;

end behavior;


