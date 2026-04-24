# TRS80
TRS80 Model 1


this project is currently developped and may be unstable
I pushed it on github simply for the keyboard part


how the keyboard is handled:

the usb_to_trs80_keyboard contains the pico rp2040 to
receive the usb hid scancode decode them and convert them
into to TRS80 "virtual scan codes" use by trs80_kbd_port
vhdl module to implement the trs80 keyboard matrix


this how trs80.c create the tr80 scancodes:

each trs80 scancode is composed of a single byte

F0RRRCCC

F= Flag  '0' = Make Code / '1' = Break Code
0        always 0 execpt special cases
RRR      3 bits row in the TRS80 Matrix
CCC      3 bits columns in the TRS80 Matrix

how the tables are coded:
the first problem is that some key of keyboard are not shifed
and shifted in the destination matrix
that why each code contains a shift flag
this flag is used to activate / inactivate the shift cell in the matrix
when needed / not needed

some special case are planned:
- a reset code                     for example CTRL-ALT-BACKSPACE   
- a clear of the matrix            in case of discrepancy between
   the keyboard and trs80

these code are sent at high speed 115200 bauds 8N1 through
the serial port of the PICO

for the PICO I use a PICO Xiao RP2040 but any other pico can be used


the pin TX of the PICO is connect to one of the pin of my FPGA
(I'm testing on a DE10 Lite)

this pin is connected to my uart_receive module
uart_receive is not a full uart with registers
it just received some data an trigger ACK to say it received one

this uart_receive module is used by trs80_kbd_port
once trs80_kbd_port see an incoming byte

if bit 7 = '0' it write '1' at row / col
if bit 7 = '1' it write '0' at row / col

the matrix is implemented as a set of 8 registers
-- Matrix storage: 8 rows of 8 bits each
type matrix_t is array(0 to 7) of std_logic_vector(7 downto 0);
signal matrix : matrix_t := (others => (others => '0'));

it's in fact a small dual port memory

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;


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

the z80 bus is connected directly
and read the matrix as on a real TRS80

in the top level this is how the cpu is connected to the keyboard

    kbd_cs_n      <= '0' when address_bus(15 downto 10)  = "001110"                                         and (MREQ_n = '0') else '1';


for the rest of the TRS80

- the machine starts on the basic level II rom 1.1
- rom     from 0000 to 3000
- mon     from 3000 to 36FF small monitor I'm using for debug from serial port
- printer from 37E8 to 37E9 printer port sends the data to as serial port for capture by a terminal emulator
- video   from 3C00 to 3FFF usable text and graphic char (I still have to find the righ charset)
- ram     from 4000 to FFFF 
- uart    from   E8 to   EB working but problem with dip switches and baud rates (fixed soon) I had the wrong documentation
- tape    from   FF to   FF port FF with tape and video mode (k7 not yet implemented)
- fdc                       currently in development I'm developping a module used for the communication with a second machine
                            with a 6502 core an with support of fatfs spi master and sdcard (the 6502 part works)


I you have any information I'm intersted by:
- the charset used by the TRS80 model 1
- the basic rom used by the TRS80 model 1

and I think that the  basic rom and charset are linked
it's useless to have accentuated characters if the basic is unable to manage them

I'm also interested to know if some nationalized keyboard existed ?
I only saw standard trs80 keyboard with or without  numeric keypad

you can contact me at:

didier [AT] aida.org







