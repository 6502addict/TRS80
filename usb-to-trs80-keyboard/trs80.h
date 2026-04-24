/* Matrix position encoding in the map */
#define TRS_POS(row, col)   (((row) << 3) | (col))   /* 0x00..0x3F */
#define TRS_SHIFT           0x40                      /* needs shift on TRS-80 */
#define TRS_NONE            0xFF                      /* no mapping */

/* Wire encoding (what goes to the TRS-80 consumer) */
#define TRS_MAKE(p)         ((p) & 0x3F)
#define TRS_BREAK(p)        (((p) & 0x3F) | 0x80)

/* TRS-80 Model 1 matrix positions */
// ROW 0
#define T_AT     TRS_POS(0,0)
#define T_A      TRS_POS(0,1)
#define T_B      TRS_POS(0,2)
#define T_C      TRS_POS(0,3)
#define T_D      TRS_POS(0,4)
#define T_E      TRS_POS(0,5)
#define T_F      TRS_POS(0,6)
#define T_G      TRS_POS(0,7)
// ROW 1
#define T_H      TRS_POS(1,0)
#define T_I      TRS_POS(1,1)
#define T_J      TRS_POS(1,2)
#define T_K      TRS_POS(1,3)
#define T_L      TRS_POS(1,4)
#define T_M      TRS_POS(1,5)
#define T_N      TRS_POS(1,6)
#define T_O      TRS_POS(1,7)
// ROW 2
#define T_P      TRS_POS(2,0)
#define T_Q      TRS_POS(2,1)
#define T_R      TRS_POS(2,2)
#define T_S      TRS_POS(2,3)
#define T_T      TRS_POS(2,4)
#define T_U      TRS_POS(2,5)
#define T_V      TRS_POS(2,6)
#define T_W      TRS_POS(2,7)
// ROW 3
#define T_X      TRS_POS(3,0)
#define T_Y      TRS_POS(3,1)
#define T_Z      TRS_POS(3,2)
// ROW 4
#define T_0      TRS_POS(4,0)
#define T_1      TRS_POS(4,1)
#define T_2      TRS_POS(4,2)
#define T_3      TRS_POS(4,3)
#define T_4      TRS_POS(4,4)
#define T_5      TRS_POS(4,5)
#define T_6      TRS_POS(4,6)
#define T_7      TRS_POS(4,7)
// ROW 5
#define T_8      TRS_POS(5,0)
#define T_9      TRS_POS(5,1)
#define T_COLON  TRS_POS(5,2)   /* shift+: = *  */
#define T_SEMI   TRS_POS(5,3)   /* shift+; = +  */
#define T_COMMA  TRS_POS(5,4)   /* shift+, = <  */
#define T_MINUS  TRS_POS(5,5)   /* shift+- = =  */
#define T_DOT    TRS_POS(5,6)   /* shift+. = >  */
#define T_SLASH  TRS_POS(5,7)   /* shift+/ = ?  */
// ROW 6
#define T_ENTER  TRS_POS(6,0)
#define T_CLEAR  TRS_POS(6,1)
#define T_BREAK  TRS_POS(6,2)
#define T_UP     TRS_POS(6,3)
#define T_DOWN   TRS_POS(6,4)
#define T_LEFT   TRS_POS(6,5)
#define T_RIGHT  TRS_POS(6,6)
#define T_SPACE  TRS_POS(6,7)
// ROW7
#define T_SHIFT  TRS_POS(7,0)
