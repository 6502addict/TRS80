#define LANG_EN   0
#define LANG_FR   1
#define LANG_ES   2
#define LANG_DE   3

#define TERM_TVI950      0
#define TERM_DATANETICS  1 
#define TERM_APPLE2      2 

#define HOTSPOT __inline__ __attribute__ ((always_inline, hot))

#define KBD_MOD_CTRL   0x01
#define KBD_MOD_SHIFT  0x02
#define KBD_MOD_ALT    0x04
#define KBD_MOD_WINDOW 0x08


#define ASCII_NUL 0x00
#define ASCII_SOH 0x01
#define ASCII_STX 0x02
#define ASCII_ETX 0x03
#define ASCII_EOT 0x04
#define ASCII_ENQ 0x05
#define ASCII_ACK 0x06
#define ASCII_BEL 0x07
#define ASCII_BS  0x08
#define ASCII_HT  0x09
#define ASCII_LF  0x0A
#define ASCII_VT  0x0B
#define ASCII_FF  0x0C
#define ASCII_CR  0x0D
#define ASCII_SO  0x0E
#define ASCII_SI  0x0F
#define ASCII_DLE 0x10
#define ASCII_DC1 0x11
#define ASCII_DC2 0x12
#define ASCII_DC3 0x13
#define ASCII_DC4 0x14
#define ASCII_NAK 0x15
#define ASCII_SYN 0x16
#define ASCII_ETB 0x17
#define ASCII_CAN 0x18
#define ASCII_EM  0x19
#define ASCII_SUB 0x1A
#define ASCII_ESC 0x1B
#define ASCII_FS  0x1C
#define ASCII_GS  0x1D
#define ASCII_RS  0x1E
#define ASCII_US  0x1F
#define ASCII_DEL 0x7F 

#define KBD_KEY_F1  0x3A
#define KBD_KEY_F2  0x3B
#define KBD_KEY_F3  0x3C
#define KBD_KEY_F4  0x3D
#define KBD_KEY_F5  0x3E
#define KBD_KEY_F6  0x3F
#define KBD_KEY_F7  0x40
#define KBD_KEY_F8  0x41
#define KBD_KEY_F9  0x42
#define KBD_KEY_F10 0x43
#define KBD_KEY_F11 0x44
#define KBD_KEY_F12 0x45

#define KBD_KEY_CAPSLOCK   0x39
#define KBD_KEY_NUMLOCK    0x53
#define KBD_KEY_DELETE     0x4C
#define KBD_KEY_BACKSPACE  0x08

#define KEY_ENTER    0x8000
#define KEY_UP       0x8001
#define KEY_DOWN     0x8002
#define KEY_RIGHT    0x8003
#define KEY_LEFT     0x8004
#define KEY_INSERT   0x8005
#define KEY_DELETE   0x8006
#define KEY_PGUP     0x8007
#define KEY_PGDN     0x8008
#define KEY_HOME     0x8009
#define KEY_END      0x800A
#define KEY_PAUSE    0x800B 

#define KEY_F1       0x800C
#define KEY_F2       0x800D
#define KEY_F3       0x800E
#define KEY_F4       0x800F
#define KEY_F5       0x8010
#define KEY_F6       0x8011
#define KEY_F7       0x8012
#define KEY_F8       0x8013
#define KEY_F9       0x8014
#define KEY_F10      0x8015
#define KEY_F11      0x8016
#define KEY_F12      0x8017

#define KEY_BKTAB    0x8019   // BACKTAB → ESC 49
#define KEY_PRINT    0x8018   // PRINT   → ESC 50 / ESC 4C

#define KEY_CAPSLCK  0x4000
#define KEY_PRTSCR   0x4001
#define KEY_SCRLCK   0x4002
#define KEY_NUMLCK   0x4003

#define CAPS_LOCK  0x01
#define NUM_LOCK   0x02
#define MOD_ALT    0x04
#define MOD_CTRL   0x08

extern bool    debug;
extern bool    capslock_state;
extern bool    numlock_state;
extern bool    scrolllock_state;
extern uint8_t lang;
extern uint8_t term;
