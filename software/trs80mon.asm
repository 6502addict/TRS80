;==============================================================
; TSMON v3 - TRS-80 Model 1 Serial Monitor
; ROM: 3000h-35FFh    RAM: 3600h-36FFh
;
; Level II BASIC invocation:
;   SYSTEM  then at *? type /12288
;   Entry point is 3000h
;
; Commands (upper or lower case, CR to execute):
;   L                Load Intel HEX from serial
;   S ssss eeee      Save memory as Intel HEX
;   G aaaa           Execute code (RET returns to monitor)
;   M ssss eeee      Hex + ASCII memory dump
;   : aaaa bb bb..   Poke bytes into memory
;   I pp             IN from port pp, display result
;   O pp bb          OUT byte bb to port pp
;   WI pp            Watch I/O port, display transitions (key to stop)
;   WM aaaa          Watch memory address, display transitions (key to stop)
;   F ssss eeee bb   Fill memory range with byte
;   C ssss eeee dddd Copy memory block to destination
;   R                Display registers (saved on last G return)
;   Q                Return to BASIC
;
; UART: status EAh (bit7=RX ready, bit6=TX ready), data EBh
;
; RAM layout (3600h-36FFh - monitor private RAM):
;   3600h  REG_AF   saved registers from G (8 bytes)
;   3602h  REG_BC
;   3604h  REG_DE
;   3606h  REG_HL
;   3608h  MEM_CNT  M command byte counter (2 bytes)
;   360Ah  spare
;   3610h  LINEBUF  56-byte input line buffer (3610h-3647h)
;   3648h  spare / stack space
;   36BEh  MON_SP   monitor stack top (grows downward)
;   36F8h  SAVED_SP BASIC SP save (2 bytes)
;
; NOTE: do not load Intel HEX data into 3600h-36FFh
; NOTE: M 0000 FFFF (full 64K) not supported - count wraps to 0
;==============================================================

UART_ST  EQU  0EAh
UART_DT  EQU  0EBh

; Monitor private RAM
REG_AF   EQU  3600h
REG_BC   EQU  3602h
REG_DE   EQU  3604h
REG_HL   EQU  3606h
MEM_CNT  EQU  3608h          ; 2-byte down-counter for M command
LINEBUF  EQU  3610h          ; 56-byte command line buffer
MON_SP   EQU  36BEh          ; monitor stack top
SAVED_SP EQU  36F8h          ; BASIC SP save

         ORG  3000h

;--- Level II BASIC module header ---
	 JP   START
;  	 DB   0AAh            ; auto-start signature
;        DB   'S','M'         ; module name (entry at 3003h)
;	 DW   3005H
;==============================================================
; ENTRY
;==============================================================
START:
         LD   (SAVED_SP),SP   ; save BASIC stack
         LD   SP,MON_SP       ; switch to monitor stack
         CALL CRLF

;==============================================================
; PROMPT LOOP
;==============================================================
PROMPT:
         LD   A,'>'
         CALL PUTCH
         LD   A,' '
         CALL PUTCH
         CALL GETLINE

         LD   A,(LINEBUF)
         CP   ':'             ; must check before uppercasing
         JP   Z,CMD_POKE
         AND  0DFh            ; force uppercase
         CP   'L'
         JP   Z,CMD_LOAD
         CP   'S'
         JP   Z,CMD_SAVE
         CP   'G'
         JP   Z,CMD_GO
         CP   'M'
         JP   Z,CMD_MEM
         CP   'I'
         JP   Z,CMD_IN
         CP   'O'
         JP   Z,CMD_OUT
         CP   'W'
         JP   Z,CMD_WATCH
         CP   'F'
         JP   Z,CMD_FILL
         CP   'C'
         JP   Z,CMD_COPY
         CP   'R'
         JP   Z,CMD_REG
         CP   'Q'
         JP   Z,CMD_QUIT
         JP   PROMPT

CMD_QUIT:
         LD   SP,(SAVED_SP)
         RET

;==============================================================
; CRLF
;==============================================================
CRLF:
         LD   A,0Dh
         CALL PUTCH
         LD   A,0Ah
         JP   PUTCH

;==============================================================
; PUTCH  - send A to serial, preserves all registers
;==============================================================
PUTCH:
         PUSH AF
PUTCH1:  IN   A,(UART_ST)
         AND  40h             ; bit6 = TX ready
         JR   Z,PUTCH1
         POP  AF
         OUT  (UART_DT),A
         RET

;==============================================================
; PUTSTR  - print null-terminated string at HL
;==============================================================
PUTSTR:
         LD   A,(HL)
         OR   A
         RET  Z
         CALL PUTCH
         INC  HL
         JR   PUTSTR

;==============================================================
; GETCH  - wait for byte from serial, return in A
;==============================================================
GETCH:
         IN   A,(UART_ST)
         AND  80h             ; bit7 = RX ready
         JR   Z,GETCH
         IN   A,(UART_DT)
         RET

;==============================================================
; KBHIT  - check for keypress without blocking
;          returns: C=0 no key,  C=1 key pressed (consumed)
;==============================================================
KBHIT:
         IN   A,(UART_ST)
         AND  80h
         RET  Z               ; Z=1, C=0: no key available
         IN   A,(UART_DT)     ; consume the key
         SCF                  ; C=1: key was pressed
         RET

;==============================================================
; FLUSH  - drain RX buffer (call after HEX load)
;==============================================================
FLUSH:
         IN   A,(UART_ST)
         AND  80h
         RET  Z
         IN   A,(UART_DT)
         JR   FLUSH

;==============================================================
; GETLINE  - read one line into LINEBUF, null-terminated
;            echoes chars, handles BS/DEL
;==============================================================
GETLINE:
         LD   HL,LINEBUF
         LD   B,55
GL1:     CALL GETCH
         CP   0Dh
         JR   Z,GL_END
         CP   08h
         JR   Z,GL_BS
         CP   7Fh
         JR   Z,GL_BS
         LD   D,A
         LD   A,B
         OR   A
         JR   Z,GL1
         LD   A,D
         CALL PUTCH
         LD   (HL),A
         INC  HL
         DEC  B
         JR   GL1
GL_BS:   LD   A,B
         CP   55
         JR   Z,GL1
         DEC  HL
         INC  B
         LD   A,08h
         CALL PUTCH
         LD   A,' '
         CALL PUTCH
         LD   A,08h
         CALL PUTCH
         JR   GL1
GL_END:  LD   (HL),0
         CALL CRLF
         RET

;==============================================================
; SKIPSP  - advance DE past spaces
;==============================================================
SKIPSP:
         LD   A,(DE)
         CP   ' '
         RET  NZ
         INC  DE
         JR   SKIPSP

;==============================================================
; PUTHEX2  - print A as 2 uppercase hex digits
;            preserves BC, DE, HL
;==============================================================
PUTHEX2:
         PUSH AF
         RRCA
         RRCA
         RRCA
         RRCA
         CALL PH1
         POP  AF
PH1:     AND  0Fh
         ADD  A,30h
         CP   3Ah
         JR   C,PH2
         ADD  A,7
PH2:     JP   PUTCH

;==============================================================
; PUTHEX4  - print HL as 4 uppercase hex digits
;==============================================================
PUTHEX4:
         LD   A,H
         CALL PUTHEX2
         LD   A,L
         JP   PUTHEX2

;==============================================================
; GETHEX2  - read 2 hex digits from serial, return in A
;            updates checksum in C, destroys B
;==============================================================
GETHEX2:
         CALL GH1
         RLCA
         RLCA
         RLCA
         RLCA
         LD   B,A
         CALL GH1
         OR   B
         LD   B,A
         LD   A,C
         ADD  A,B
         LD   C,A
         LD   A,B
         RET
GH1:     CALL GETCH
         SUB  '0'
         CP   10
         RET  C
         AND  0DFh
         SUB  7
         RET

;==============================================================
; BUFHEX4  - parse 4 hex digits from (DE), return HL
;            DE advances past the digits, destroys A, B
;==============================================================
BUFHEX4:
         CALL BUFHEX2
         LD   H,A
         CALL BUFHEX2
         LD   L,A
         RET
BUFHEX2:
         CALL BH1
         RLCA
         RLCA
         RLCA
         RLCA
         LD   B,A
         CALL BH1
         OR   B
         RET
BH1:     LD   A,(DE)
         INC  DE
         SUB  '0'
         CP   10
         RET  C
         AND  0DFh
         SUB  7
         RET

;==============================================================
; CMD_LOAD  - receive Intel HEX records from serial
;==============================================================
CMD_LOAD:
         CALL CRLF
LOAD1:   CALL GETCH
         CP   ':'
         JR   NZ,LOAD1
         LD   C,0
         CALL GETHEX2
         LD   D,A
         CALL GETHEX2
         LD   H,A
         CALL GETHEX2
         LD   L,A
         CALL GETHEX2
         CP   01h
         JR   Z,LOAD_EOF
         LD   A,D
         OR   A
         JR   Z,LOAD_CK
LOAD2:   CALL GETHEX2
         LD   (HL),A
         INC  HL
         DEC  D
         JR   NZ,LOAD2
LOAD_CK: CALL GETHEX2
         LD   A,'.'
         CALL PUTCH
         JR   LOAD1
LOAD_EOF:
         CALL GETHEX2
;         CALL FLUSH           ; discard trailing terminal chars
         LD   HL,MSG_OK
         CALL PUTSTR
         JP   PROMPT

;==============================================================
; CMD_SAVE  - dump memory range as Intel HEX
; Syntax: S ssss eeee
;==============================================================
CMD_SAVE:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX4         ; HL = start
         PUSH HL
         CALL SKIPSP
         CALL BUFHEX4         ; HL = end
         POP  DE
         EX   DE,HL           ; HL = start, DE = end
         CALL CRLF
SAVE_LP:
         LD   A,E
         SUB  L
         LD   C,A
         LD   A,D
         SBC  A,H
         JR   C,SAVE_EOF
         OR   A
         JR   NZ,SAVE_16
         LD   A,C
         CP   15
         JR   NC,SAVE_16
         LD   B,C
         INC  B
         JR   SAVE_REC
SAVE_16: LD   B,16
SAVE_REC:
         PUSH DE
         LD   A,':'
         CALL PUTCH
         LD   C,0
         LD   A,B
         CALL PUTHEX2
         LD   A,C
         ADD  A,B
         LD   C,A
         LD   A,H
         CALL PUTHEX2
         LD   A,C
         ADD  A,H
         LD   C,A
         LD   A,L
         CALL PUTHEX2
         LD   A,C
         ADD  A,L
         LD   C,A
         XOR  A
         CALL PUTHEX2
SAVE_DT: LD   A,(HL)
         CALL PUTHEX2
         LD   A,C
         ADD  A,(HL)
         LD   C,A
         INC  HL
         DJNZ SAVE_DT
         LD   A,C
         NEG
         CALL PUTHEX2
         CALL CRLF
         POP  DE
         JR   SAVE_LP
SAVE_EOF:
         LD   HL,EOF_STR
         CALL PUTSTR
         CALL CRLF
         JP   PROMPT

EOF_STR: DB   ':00000001FF',0

;==============================================================
; CMD_GO  - execute code at address, capture registers on return
; Syntax: G aaaa
;==============================================================
CMD_GO:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX4         ; HL = target address
         LD   DE,GO_RET
         PUSH DE
         JP   (HL)
GO_RET:
         PUSH AF
         PUSH BC
         PUSH DE
         PUSH HL
         POP  HL
         LD   (REG_HL),HL
         POP  HL
         LD   (REG_DE),HL
         POP  HL
         LD   (REG_BC),HL
         POP  HL
         LD   (REG_AF),HL     ; H=A, L=F (little-endian stack layout)
         JP   PROMPT

;==============================================================
; CMD_MEM  - hex + ASCII memory dump
; Syntax: M ssss eeee
;
; Uses down-counter MEM_CNT instead of HL>DE comparison
; to correctly handle ranges ending at FFFFh.
; D = bytes to print this line throughout the inner loops.
; PUTCH/PUTHEX2/CRLF preserve B, D, E, HL.
;==============================================================
CMD_MEM:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX4         ; HL = start
         PUSH HL
         CALL SKIPSP
         CALL BUFHEX4         ; HL = end
         POP  DE              ; DE = start
         LD   A,L
         SUB  E
         LD   C,A
         LD   A,H
         SBC  A,D             ; BC = end - start
         LD   B,A
         INC  BC              ; BC = count
         LD   (MEM_CNT),BC
         EX   DE,HL           ; HL = start
         CALL CRLF

MEM_LINE:
         LD   BC,(MEM_CNT)
         LD   A,B
         OR   C
         JP   Z,PROMPT        ; count = 0: done

         ; D = min(16, count)
         LD   A,B
         OR   A
         JR   NZ,MEM_FULL     ; count >= 256
         LD   A,C
         CP   16
         JR   NC,MEM_FULL
         LD   D,A             ; last partial line
         JR   MEM_UPD
MEM_FULL:
         LD   D,16
MEM_UPD:
         LD   A,C
         SUB  D
         LD   C,A
         LD   A,B
         SBC  A,0
         LD   B,A
         LD   (MEM_CNT),BC

         PUSH HL              ; save line start for ASCII pass
         CALL PUTHEX4
         LD   A,':'
         CALL PUTCH
         LD   A,' '
         CALL PUTCH

         LD   E,D             ; E = real-byte countdown (D preserved)
         LD   B,16
MEM_HEX:
         LD   A,E
         OR   A
         JR   Z,MEM_PAD
         LD   A,(HL)
         CALL PUTHEX2
         LD   A,' '
         CALL PUTCH
         INC  HL
         DEC  E
         DJNZ MEM_HEX
         JR   MEM_SEP
MEM_PAD: LD   A,' '
         CALL PUTCH
         CALL PUTCH
         CALL PUTCH
         DJNZ MEM_PAD
MEM_SEP: LD   A,' '
         CALL PUTCH

         POP  HL              ; restore line start
         LD   B,D             ; ASCII loop: exactly D chars
MEM_ASC: LD   A,(HL)
         CP   20h
         JR   C,MEM_DOT
         CP   7Fh
         JR   C,MEM_PRT
MEM_DOT: LD   A,'.'
MEM_PRT: CALL PUTCH
         INC  HL
         DJNZ MEM_ASC
         ; HL = line_start + D = first address of next line

         CALL CRLF
         JR   MEM_LINE

;==============================================================
; CMD_POKE  - write bytes into memory
; Syntax: :aaaa bb bb bb ...
;==============================================================
CMD_POKE:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX4         ; HL = target address
POKE_LP: CALL SKIPSP
         LD   A,(DE)
         OR   A
         JR   Z,POKE_END
         CALL BUFHEX2
         LD   (HL),A
         INC  HL
         JR   POKE_LP
POKE_END:
         JP   PROMPT

;==============================================================
; CMD_IN  - read I/O port
; Syntax: I pp
;==============================================================
CMD_IN:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX2
         LD   C,A
         IN   A,(C)           ; ED 78
         CALL PUTHEX2
         CALL CRLF
         JP   PROMPT

;==============================================================
; CMD_OUT  - write I/O port
; Syntax: O pp bb
;==============================================================
CMD_OUT:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX2
         LD   C,A
         CALL SKIPSP
         CALL BUFHEX2
         OUT  (C),A           ; ED 79
         CALL CRLF
         JP   PROMPT

;==============================================================
; CMD_WATCH  - dispatch WI or WM
;==============================================================
CMD_WATCH:
         LD   A,(LINEBUF+1)
         AND  0DFh
         CP   'I'
         JP   Z,CMD_WI
         CP   'M'
         JP   Z,CMD_WM
         JP   PROMPT

;==============================================================
; CMD_WI  - watch I/O port, print transitions until keypress
; Syntax: WI pp
;
; Registers during loop:
;   C = port number  (preserved by PUTCH/PUTHEX2/KBHIT)
;   B = previous value
;   D = new value (temp)
;==============================================================
CMD_WI:
         LD   DE,LINEBUF+2
         CALL SKIPSP
         CALL BUFHEX2         ; A = port
         LD   C,A
         IN   A,(C)           ; read initial value
         LD   B,A
         CALL PUTHEX2
         CALL CRLF
WI_LOOP:
         CALL KBHIT
         JR   C,WI_DONE       ; key pressed: stop
         IN   A,(C)
         CP   B               ; changed?
         JR   Z,WI_LOOP
         LD   D,A             ; save new value
         LD   A,B
         CALL PUTHEX2         ; print old
         LD   HL,STR_ARR
         CALL PUTSTR          ; " -> "
         LD   A,D
         CALL PUTHEX2         ; print new
         CALL CRLF
         LD   B,D             ; update previous
         JR   WI_LOOP
WI_DONE:
         JP   PROMPT

;==============================================================
; CMD_WM  - watch memory address, print transitions until keypress
; Syntax: WM aaaa
;
; Registers during loop:
;   HL = memory address  (saved/restored around PUTSTR)
;   B  = previous value
;   D  = new value (temp)
;==============================================================
CMD_WM:
         LD   DE,LINEBUF+2
         CALL SKIPSP
         CALL BUFHEX4         ; HL = address to watch
         LD   A,(HL)          ; read initial value
         LD   B,A
         CALL PUTHEX2
         CALL CRLF
WM_LOOP:
         CALL KBHIT
         JR   C,WM_DONE
         LD   A,(HL)
         CP   B
         JR   Z,WM_LOOP
         LD   D,A             ; save new value
         LD   A,B
         CALL PUTHEX2         ; print old  (HL preserved)
         PUSH HL              ; save address across PUTSTR
         LD   HL,STR_ARR
         CALL PUTSTR          ; " -> "
         POP  HL              ; restore address
         LD   A,D
         CALL PUTHEX2         ; print new  (HL preserved)
         CALL CRLF
         LD   B,D
         JR   WM_LOOP
WM_DONE:
         JP   PROMPT

;==============================================================
; CMD_FILL  - fill memory range with a byte
; Syntax: F ssss eeee bb
;==============================================================
CMD_FILL:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX4         ; HL = start
         PUSH HL
         CALL SKIPSP
         CALL BUFHEX4         ; HL = end
         PUSH HL
         CALL SKIPSP
         CALL BUFHEX2         ; A = fill byte
         LD   C,A             ; C = fill byte (preserved)
         POP  DE              ; DE = end
         POP  HL              ; HL = start
FILL_LP:
         LD   (HL),C          ; write fill byte (opcode 71h)
         LD   A,H
         CP   D
         JR   NZ,FILL_NXT
         LD   A,L
         CP   E
         JR   Z,FILL_END
FILL_NXT:
         INC  HL
         JR   FILL_LP
FILL_END:
         JP   PROMPT

;==============================================================
; CMD_COPY  - copy memory block
; Syntax: C ssss eeee dddd
;   copies [ssss..eeee] to dddd
;==============================================================
CMD_COPY:
         LD   DE,LINEBUF+1
         CALL SKIPSP
         CALL BUFHEX4         ; HL = source start
         PUSH HL
         CALL SKIPSP
         CALL BUFHEX4         ; HL = source end
         PUSH HL
         CALL SKIPSP
         CALL BUFHEX4         ; HL = destination
         EX   DE,HL           ; DE = destination (HL = parse ptr, discard)
         POP  BC              ; BC = source end
         POP  HL              ; HL = source start
COPY_LP:
         LD   A,(HL)
         LD   (DE),A
         LD   A,H
         CP   B
         JR   NZ,COPY_NXT
         LD   A,L
         CP   C
         JR   Z,COPY_END
COPY_NXT:
         INC  HL
         INC  DE
         JR   COPY_LP
COPY_END:
         JP   PROMPT

;==============================================================
; CMD_REG  - display registers saved on last G return
; Output: A=xx F=xx BC=xxxx DE=xxxx HL=xxxx
;
; LD (REG_AF),HL stores: (REG_AF)=L=F, (REG_AF+1)=H=A
; so LD HL,(REG_AF) gives H=A, L=F
;==============================================================
CMD_REG:
         LD   HL,STR_A
         CALL PUTSTR
         LD   HL,(REG_AF)
         LD   A,H             ; A register
         CALL PUTHEX2
         LD   HL,STR_F
         CALL PUTSTR
         LD   HL,(REG_AF)
         LD   A,L             ; F register
         CALL PUTHEX2
         LD   HL,STR_BC
         CALL PUTSTR
         LD   HL,(REG_BC)
         CALL PUTHEX4
         LD   HL,STR_DE
         CALL PUTSTR
         LD   HL,(REG_DE)
         CALL PUTHEX4
         LD   HL,STR_HL
         CALL PUTSTR
         LD   HL,(REG_HL)
         CALL PUTHEX4
         CALL CRLF
         JP   PROMPT

;==============================================================
; Strings
;==============================================================
MSG_OK:  DB   'OK',0Dh,0Ah,0
STR_ARR: DB   ' -> ',0
STR_A:   DB   'A=',0
STR_F:   DB   ' F=',0
STR_BC:  DB   ' BC=',0
STR_DE:  DB   ' DE=',0
STR_HL:  DB   ' HL=',0

         END
