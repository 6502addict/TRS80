#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "bsp/board.h"
#include "tusb.h"
#include "kbd_ringbuffer.h"
#include "kbd.h"
#include "trs80.h"

void kbd_reset(void);

/* ---- TRS-80 side state ---- */
static bool trs80_shift_held = false;
static bool first = true;

/* For each currently-pressed USB scancode, remember what we actually sent
   so we can issue the right break and re-evaluate shift on release.       */

static struct {
    uint8_t pos;          // matrix position, or 0xFF if not held 
    bool    needed_shift;
} active[256] = { [0 ... 255] = { 0xFF, false } };



//------------------------------------------------------------------------------------------------------------------------
//    FLAGS                              NORMAL                     SHIFTED                           ALT  PC KBD MAPPING
//------------------------------------------------------------------------------------------------------------------------
const int kbd_map_trs80_en[128][4] = {
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x00
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x01
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x02
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x03
    { CAPS_LOCK | MOD_CTRL,                T_A,         TRS_SHIFT |     T_A,                   TRS_NONE }, // 0x04 A
    { CAPS_LOCK | MOD_CTRL,                T_B,         TRS_SHIFT |     T_B,                   TRS_NONE }, // 0x05 B
    { CAPS_LOCK | MOD_CTRL,                T_C,         TRS_SHIFT |     T_C,                   TRS_NONE }, // 0x06 C
    { CAPS_LOCK | MOD_CTRL,                T_D,         TRS_SHIFT |     T_D,                   TRS_NONE }, // 0x07 D
    { CAPS_LOCK | MOD_CTRL,                T_E,         TRS_SHIFT |     T_E,                   TRS_NONE }, // 0x08 E
    { CAPS_LOCK | MOD_CTRL,                T_F,         TRS_SHIFT |     T_F,                   TRS_NONE }, // 0x09 F
    { CAPS_LOCK | MOD_CTRL,                T_G,         TRS_SHIFT |     T_G,                   TRS_NONE }, // 0x0a G
    { CAPS_LOCK | MOD_CTRL,                T_H,         TRS_SHIFT |     T_H,                   TRS_NONE }, // 0x0b H
    { CAPS_LOCK | MOD_CTRL,                T_I,         TRS_SHIFT |     T_I,                   TRS_NONE }, // 0x0c I
    { CAPS_LOCK | MOD_CTRL,                T_J,         TRS_SHIFT |     T_J,                   TRS_NONE }, // 0x0d J
    { CAPS_LOCK | MOD_CTRL,                T_K,         TRS_SHIFT |     T_K,                   TRS_NONE }, // 0x0e K
    { CAPS_LOCK | MOD_CTRL,                T_L,         TRS_SHIFT |     T_L,                   TRS_NONE }, // 0x0f L
    { CAPS_LOCK | MOD_CTRL,                T_M,         TRS_SHIFT |     T_M,                   TRS_NONE }, // 0x10 M
    { CAPS_LOCK | MOD_CTRL,                T_N,         TRS_SHIFT |     T_N,                   TRS_NONE }, // 0x11 N
    { CAPS_LOCK | MOD_CTRL,                T_O,         TRS_SHIFT |     T_O,                   TRS_NONE }, // 0x12 O
    { CAPS_LOCK | MOD_CTRL,                T_P,         TRS_SHIFT |     T_P,                   TRS_NONE }, // 0x13 P
    { CAPS_LOCK | MOD_CTRL,                T_Q,         TRS_SHIFT |     T_Q,                   TRS_NONE }, // 0x14 A 
    { CAPS_LOCK | MOD_CTRL,                T_R,         TRS_SHIFT |     T_R,                   TRS_NONE }, // 0x15 R
    { CAPS_LOCK | MOD_CTRL,                T_S,         TRS_SHIFT |     T_S,                   TRS_NONE }, // 0x1S S
    { CAPS_LOCK | MOD_CTRL,                T_T,         TRS_SHIFT |     T_T,                   TRS_NONE }, // 0x17 T
    { CAPS_LOCK | MOD_CTRL,                T_U,         TRS_SHIFT |     T_U,                   TRS_NONE }, // 0x18 U
    { CAPS_LOCK | MOD_CTRL,                T_V,         TRS_SHIFT |     T_V,                   TRS_NONE }, // 0x19 V
    { CAPS_LOCK | MOD_CTRL,                T_W,         TRS_SHIFT |     T_W,                   TRS_NONE }, // 0x1a Z
    { CAPS_LOCK | MOD_CTRL,                T_X,         TRS_SHIFT |     T_X,                   TRS_NONE }, // 0x1b X
    { CAPS_LOCK | MOD_CTRL,                T_Y,         TRS_SHIFT |     T_Y,                   TRS_NONE }, // 0x1c Y
    { CAPS_LOCK | MOD_CTRL,                T_Z,         TRS_SHIFT |     T_Z,                   TRS_NONE }, // 0x1d W
    { 0,                                   T_1,         TRS_SHIFT |     T_1,                   TRS_NONE }, // 0x1e 1!
    { 0,                                   T_2,         TRS_SHIFT |     T_2,                   TRS_NONE }, // 0x1f 2"
    { 0,                                   T_3,         TRS_SHIFT |     T_3,                   TRS_NONE }, // 0x20 3#
    { 0,                                   T_4,         TRS_SHIFT |     T_4,                   TRS_NONE }, // 0x21 4$
    { 0,                                   T_5,         TRS_SHIFT |     T_5,                   TRS_NONE }, // 0x22 5%
    { 0,                                   T_6,         TRS_SHIFT |     T_6,                   TRS_NONE }, // 0x23 6&
    { 0,                                   T_7,         TRS_SHIFT |     T_7,                   TRS_NONE }, // 0x24 7'
    { 0,                                   T_8,         TRS_SHIFT |     T_8,                   TRS_NONE }, // 0x25 8(
    { 0,                                   T_9,         TRS_SHIFT |     T_9,                   TRS_NONE }, // 0x26 9)
    { 0,                                   T_0,         TRS_SHIFT |     T_0,                   TRS_NONE }, // 0x27 0
    { 0,                               T_ENTER,                     T_ENTER,                    T_ENTER }, // 0x28 ENTER
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x29 ESCAPE
    { 0,                                T_LEFT,                      T_LEFT,                     T_LEFT }, // 0x2a BACKSPACE
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x2b BACKTAB
    { 0,                               T_SPACE,                     T_SPACE,                    T_SPACE }, // 0x2c SPACE
    { 0,                               T_MINUS,                    TRS_NONE,                   TRS_NONE }, // 0x2d -_
    { 0,                   TRS_SHIFT | T_MINUS,         TRS_SHIFT | T_COMMA,                   TRS_NONE }, // 0x2e =+
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x2f [{
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x30 ]}
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x31 \|
    { 0,                   TRS_SHIFT |     T_3,                    TRS_NONE,                   TRS_NONE }, // 0x32 #~
    { 0,                                T_SEMI,                     T_COLON,                   TRS_NONE }, // 0x33 ;:
    { 0,                   TRS_SHIFT |     T_7,         TRS_SHIFT |     T_2,                   TRS_NONE }, // 0x34 '"
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x35 `~
    { 0,                               T_COMMA,         TRS_SHIFT | T_COMMA,                   TRS_NONE }, // 0x36 ,<
    { 0,                                 T_DOT,         TRS_SHIFT |   T_DOT,                   TRS_NONE }, // 0x37 .>
    { 0,                   TRS_SHIFT |     T_1,                    TRS_NONE,                   TRS_NONE }, // 0x38 /?
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x39  CAPSLOCK
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3a  F1
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3b  F2
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3c  F3
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3d  F4
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3e  F5
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3f  F6
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x40  F7
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x41  F8
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x42  F9
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x43  F10
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x44  F11
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x45  F12
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x46  PRINT
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x47  SCRLCK
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x48  PAUSE
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x49  INSERT
    { 0,                               T_CLEAR,                     T_CLEAR,                    T_CLEAR }, // 0x4a  HOME
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x4b  PGUP
    { 0,                                T_LEFT,                      T_LEFT,                     T_LEFT }, // 0x4c  DELETE
    { 0,                               T_BREAK,                     T_BREAK,                    T_BREAK }, // 0x4d  END
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x4e  PGDN
    { 0,                               T_RIGHT,                     T_RIGHT,                   TRS_NONE }, // 0x4f  RIGHT
    { 0,                                T_LEFT,                      T_LEFT,                   TRS_NONE }, // 0x50  LEFT
    { 0,                                T_DOWN,                      T_DOWN,                   TRS_NONE }, // 0x51  DOWN
    { 0,                                  T_UP,                        T_UP,                   TRS_NONE }, // 0x52  UP
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x53  NUMLCK
    { 0,                               T_SLASH,                     T_SLASH,                   TRS_NONE }, // 0x54 numpad /
    { 0,                   TRS_SHIFT | T_COLON,         TRS_SHIFT | T_COLON,                   TRS_NONE }, // 0x55 numpad *
    { 0,                               T_MINUS,                     T_MINUS,                   TRS_NONE }, // 0x56 numpad -
    { 0,                   TRS_SHIFT |  T_SEMI,         TRS_SHIFT |  T_SEMI,                   TRS_NONE }, // 0x57 numpad +
    { 0,                               T_ENTER,                     T_ENTER,                    T_ENTER }, // 0x58 numpad enter
    { NUM_LOCK,                            T_1,                    TRS_NONE,                   TRS_NONE }, // 0x59 numpad 1
    { NUM_LOCK,                            T_2,                      T_DOWN,                     T_DOWN }, // 0x5a numpad 2
    { NUM_LOCK,                            T_3,                    TRS_NONE,                   TRS_NONE }, // 0x5b numpad 3
    { NUM_LOCK,                            T_4,                      T_LEFT,                     T_LEFT }, // 0x5c numpad 4
    { NUM_LOCK,                            T_5,                    TRS_NONE,                   TRS_NONE }, // 0x5n numpad 5
    { NUM_LOCK,                            T_6,                     T_RIGHT,                    T_RIGHT }, // 0x5e numpad 6
    { NUM_LOCK,                            T_7,                    TRS_NONE,                   TRS_NONE }, // 0x5f numpad 7
    { NUM_LOCK,                            T_8,                        T_UP,                       T_UP }, // 0x60 numpad 8
    { NUM_LOCK,                            T_9,                    TRS_NONE,                   TRS_NONE }, // 0x61 numpad 9
    { NUM_LOCK,                            T_0,                    TRS_NONE,                   TRS_NONE }, // 0x62 numpad 0
    { NUM_LOCK,                          T_DOT,                      T_LEFT,                     T_LEFT }, // 0x63 numpad .
    { NUM_LOCK,            TRS_SHIFT | T_COMMA,           TRS_SHIFT | T_DOT,                   TRS_NONE }, // 0x64 <>
};


//------------------------------------------------------------------------------------------------------------------------
//    FLAGS                              NORMAL                     SHIFTED                           ALT  PC KBD MAPPING
//------------------------------------------------------------------------------------------------------------------------
const int kbd_map_trs80_fr[128][4] = {
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x00
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x01
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x02
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x03
    { CAPS_LOCK | MOD_CTRL,                T_Q,         TRS_SHIFT |     T_Q,                   TRS_NONE }, // 0x04 Q
    { CAPS_LOCK | MOD_CTRL,                T_B,         TRS_SHIFT |     T_B,                   TRS_NONE }, // 0x05 B
    { CAPS_LOCK | MOD_CTRL,                T_C,         TRS_SHIFT |     T_C,                   TRS_NONE }, // 0x06 C
    { CAPS_LOCK | MOD_CTRL,                T_D,         TRS_SHIFT |     T_D,                   TRS_NONE }, // 0x07 D
    { CAPS_LOCK | MOD_CTRL,                T_E,         TRS_SHIFT |     T_E,                   TRS_NONE }, // 0x08 E
    { CAPS_LOCK | MOD_CTRL,                T_F,         TRS_SHIFT |     T_F,                   TRS_NONE }, // 0x09 F
    { CAPS_LOCK | MOD_CTRL,                T_G,         TRS_SHIFT |     T_G,                   TRS_NONE }, // 0x0a G
    { CAPS_LOCK | MOD_CTRL,                T_H,         TRS_SHIFT |     T_H,                   TRS_NONE }, // 0x0b H
    { CAPS_LOCK | MOD_CTRL,                T_I,         TRS_SHIFT |     T_I,                   TRS_NONE }, // 0x0c I
    { CAPS_LOCK | MOD_CTRL,                T_J,         TRS_SHIFT |     T_J,                   TRS_NONE }, // 0x0d J
    { CAPS_LOCK | MOD_CTRL,                T_K,         TRS_SHIFT |     T_K,                   TRS_NONE }, // 0x0e K
    { CAPS_LOCK | MOD_CTRL,                T_L,         TRS_SHIFT |     T_L,                   TRS_NONE }, // 0x0f L
    { CAPS_LOCK | MOD_CTRL,            T_COMMA,         TRS_SHIFT | T_SLASH,                   TRS_NONE }, // 0x10 ,/
    { CAPS_LOCK | MOD_CTRL,                T_N,         TRS_SHIFT |     T_N,                   TRS_NONE }, // 0x11 N
    { CAPS_LOCK | MOD_CTRL,                T_O,         TRS_SHIFT |     T_O,                   TRS_NONE }, // 0x12 O
    { CAPS_LOCK | MOD_CTRL,                T_P,         TRS_SHIFT |     T_P,                   TRS_NONE }, // 0x13 P
    { CAPS_LOCK | MOD_CTRL,                T_A,         TRS_SHIFT |     T_A,                   TRS_NONE }, // 0x14 A 
    { CAPS_LOCK | MOD_CTRL,                T_R,         TRS_SHIFT |     T_R,                   TRS_NONE }, // 0x15 R
    { CAPS_LOCK | MOD_CTRL,                T_S,         TRS_SHIFT |     T_S,                   TRS_NONE }, // 0x1S S
    { CAPS_LOCK | MOD_CTRL,                T_T,         TRS_SHIFT |     T_T,                   TRS_NONE }, // 0x17 T
    { CAPS_LOCK | MOD_CTRL,                T_U,         TRS_SHIFT |     T_U,                   TRS_NONE }, // 0x18 U
    { CAPS_LOCK | MOD_CTRL,                T_V,         TRS_SHIFT |     T_V,                   TRS_NONE }, // 0x19 V
    { CAPS_LOCK | MOD_CTRL,                T_Z,         TRS_SHIFT |     T_Z,                   TRS_NONE }, // 0x1a Z
    { CAPS_LOCK | MOD_CTRL,                T_X,         TRS_SHIFT |     T_X,                   TRS_NONE }, // 0x1b X
    { CAPS_LOCK | MOD_CTRL,                T_Y,         TRS_SHIFT |     T_Y,                   TRS_NONE }, // 0x1c Y
    { CAPS_LOCK | MOD_CTRL,                T_W,         TRS_SHIFT |     T_W,                   TRS_NONE }, // 0x1d W
    { 0,                    TRS_SHIFT |    T_6,                         T_1,                   TRS_NONE }, // 0x1e &1
    { 0,                                   T_E,                         T_2,                   TRS_NONE }, // 0x1f é2~
    { 0,                    TRS_SHIFT |    T_2,                         T_3,       TRS_SHIFT |      T_3 }, // 0x20 "3#
    { 0,                    TRS_SHIFT |    T_7,                         T_4,                   TRS_NONE }, // 0x21 '4{
    { 0,                    TRS_SHIFT |    T_8,                         T_5,                   TRS_NONE }, // 0x22 (5[
    { 0,                               T_MINUS,                         T_6,                   TRS_NONE }, // 0x23 -6|
    { 0,                                   T_E,                         T_7,       TRS_SHIFT |      T_7 }, // 0x24 è7`
    { 0,                              TRS_NONE,                         T_8,                   TRS_NONE }, // 0x25 _8
    { 0,                                   T_C,                         T_9,                   TRS_NONE }, // 0x26 ç9
    { 0,                                   T_A,                         T_0,                       T_AT }, // 0x27 à0@
    { 0,                               T_ENTER,                     T_ENTER,                    T_ENTER }, // 0x28 ENTER
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x29 ESCAPE
    { 0,                                T_LEFT,                      T_LEFT,                     T_LEFT }, // 0x2a BACKSPACE
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x2b BACKTAB
    { 0,                               T_SPACE,                     T_SPACE,                    T_SPACE }, // 0x2c SPACE
    { 0,                   TRS_SHIFT |     T_9,                         T_C,                   TRS_NONE }, // 0x2d )°]
    { 0,                   TRS_SHIFT | T_MINUS,          TRS_SHIFT | T_SEMI,                   TRS_NONE }, // 0x2e =+
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x2f ^¨
    { 0,                   TRS_SHIFT |     T_4,                    TRS_NONE,                   TRS_NONE }, // 0x30 $£
    { 0,                   TRS_SHIFT | T_COLON,                         T_U,                   TRS_NONE }, // 0x31 *µ
    { 0,                   TRS_SHIFT |     T_3,                    TRS_NONE,                   TRS_NONE }, // 0x32 ?? 
    { 0,                                   T_M,          TRS_SHIFT |    T_M,                   TRS_NONE }, // 0x33 M
    { 0,                                   T_U,          TRS_SHIFT |    T_5,                   TRS_NONE }, // 0x34 ù%
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x35 ??
    { 0,                                T_SEMI,                       T_DOT,                   TRS_NONE }, // 0x36
    { 0,                               T_COLON,                     T_SLASH,                   TRS_NONE }, // 0x37
    { 0,                   TRS_SHIFT |     T_1,                    TRS_NONE,                   TRS_NONE }, // 0x38
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x39  CAPSLOCK
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3a  F1
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3b  F2
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3c  F3
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3d  F4
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3e  F5
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x3f  F6
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x40  F7
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x41  F8
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x42  F9
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x43  F10
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x44  F11
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x45  F12
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x46  PRINT
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x47  SCRLCK
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x48  PAUSE
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x49  INSERT
    { 0,                               T_CLEAR,                     T_CLEAR,                    T_CLEAR }, // 0x4a  HOME
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x4b  PGUP
    { 0,                                T_LEFT,                      T_LEFT,                     T_LEFT }, // 0x4c  DELETE
    { 0,                               T_BREAK,                     T_BREAK,                    T_BREAK }, // 0x4d  END
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x4e  PGDN
    { 0,                               T_RIGHT,                     T_RIGHT,                   TRS_NONE }, // 0x4f  RIGHT
    { 0,                                T_LEFT,                      T_LEFT,                   TRS_NONE }, // 0x50  LEFT
    { 0,                                T_DOWN,                      T_DOWN,                   TRS_NONE }, // 0x51  DOWN
    { 0,                                  T_UP,                        T_UP,                   TRS_NONE }, // 0x52  UP
    { 0,                              TRS_NONE,                    TRS_NONE,                   TRS_NONE }, // 0x53  NUMLCK
    { 0,                               T_SLASH,                     T_SLASH,                   TRS_NONE }, // 0x54  numpad /
    { 0,                   TRS_SHIFT | T_COLON,         TRS_SHIFT | T_COLON,                   TRS_NONE }, // 0x55  numpad *
    { 0,                               T_MINUS,                     T_MINUS,                   TRS_NONE }, // 0x56  numpad -
    { 0,                   TRS_SHIFT |  T_SEMI,         TRS_SHIFT |  T_SEMI,                   TRS_NONE }, // 0x57  numpad +
    { 0,                               T_ENTER,                     T_ENTER,                    T_ENTER }, // 0x58  numpad enter
    { NUM_LOCK,                            T_1,                    TRS_NONE,                   TRS_NONE }, // 0x59  numpad 1
    { NUM_LOCK,                            T_2,                      T_DOWN,                     T_DOWN }, // 0x5a  numpad 2
    { NUM_LOCK,                            T_3,                    TRS_NONE,                   TRS_NONE }, // 0x5b  numpad 3
    { NUM_LOCK,                            T_4,                      T_LEFT,                     T_LEFT }, // 0x5c  numpad 4
    { NUM_LOCK,                            T_5,                    TRS_NONE,                   TRS_NONE }, // 0x5n  numpad 5
    { NUM_LOCK,                            T_6,                     T_RIGHT,                    T_RIGHT }, // 0x5e  numpad 6
    { NUM_LOCK,                            T_7,                    TRS_NONE,                   TRS_NONE }, // 0x5f  numpad 7
    { NUM_LOCK,                            T_8,                        T_UP,                       T_UP }, // 0x60  numpad 8
    { NUM_LOCK,                            T_9,                    TRS_NONE,                   TRS_NONE }, // 0x61  numpad 9
    { NUM_LOCK,                            T_0,                    TRS_NONE,                   TRS_NONE }, // 0x62  numpad 0
    { NUM_LOCK,                        T_COMMA,                      T_LEFT,                     T_LEFT }, // 0x63  numpad .
    { NUM_LOCK,            TRS_SHIFT | T_COMMA,           TRS_SHIFT | T_DOT,                   TRS_NONE }, // 0x64  <>
};

// language map pointer table — order must match LANG_EN/LANG_FR
// if you need more keybable mapping add them in this table
static const int (*kbd_map[])[4] = {
    kbd_map_trs80_en,
    kbd_map_trs80_fr,
};


void trs80_send(KbdRingBuffer *krb, uint8_t code) {
  KbdAddKey(krb, (uint8_t) code);
}

void kbd_reset_full(KbdRingBuffer *krb) {
  for (uint8_t pos = 0; pos < 64; pos++)
    trs80_send(krb, 0x80 | pos);
  trs80_shift_held = false;
  for (int i = 0; i < 256; i++) {
    active[i].pos         = 0xFF;
    active[i].needed_shift = false;
  }
}


static void trs80_set_shift(KbdRingBuffer *krb, bool want)
{
    if (want == trs80_shift_held) return;
    trs80_send(krb, want ? TRS_MAKE(T_SHIFT) : TRS_BREAK(T_SHIFT));
    trs80_shift_held = want;
}

static bool any_held_needs_shift(void)
{
    for (int i = 0; i < 256; i++)
        if (active[i].pos != 0xFF && active[i].needed_shift)
            return true;
    return false;
}


void kbd_decode_trs80(KbdRingBuffer *krb, uint8_t kc, uint8_t mod, bool is_break)
{
    bool host_shift = mod & (KEYBOARD_MODIFIER_LEFTSHIFT |
                             KEYBOARD_MODIFIER_RIGHTSHIFT);
    bool host_altgr = mod & KEYBOARD_MODIFIER_RIGHTALT;

    if (first) {
      kbd_reset_full(krb);
      first = false;
    }

    if (!is_break && kc == KBD_KEY_DELETE  && mod == (KBD_MOD_ALT | KBD_MOD_CTRL))
      kbd_reset();

    if (!is_break) {
      
        // ---------- MAKE ---------- 
        if (active[kc].pos != 0xFF)
	  return;          // already held, ignore repeat 

        uint8_t col    = host_altgr ? 3 : (host_shift ? 2 : 1);
        uint8_t target = kbd_map[lang][kc][col];
        if (target == TRS_NONE)
	  return;

        uint8_t pos         = target & 0x3F;
        bool    needs_shift = target & TRS_SHIFT;

        // Bring TRS-80 shift in line with what this key needs BEFORE pressing it 
        trs80_set_shift(krb, needs_shift);

        trs80_send(krb, TRS_MAKE(pos));
        active[kc].pos          = pos;
        active[kc].needed_shift = needs_shift;
    } else {
        // ---------- BREAK ---------- 
        if (active[kc].pos == 0xFF) return;          // nothing to release 

        trs80_send(krb, TRS_BREAK(active[kc].pos));
        active[kc].pos = 0xFF;

        // If no remaining held key needs shift, drop shift on the TRS-80 side 
        if (trs80_shift_held && !any_held_needs_shift())
	  trs80_set_shift(krb, false);
    }
}

