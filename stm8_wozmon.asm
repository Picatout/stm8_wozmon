;--------------------------------
;  with this version of wozmon 
;  for stm8 I follow exact model 
;  used by Steve Wozniak only 
;  exception is taking advantage 
;  of extension that STM8 bring 
;  over 6502 cpu. 
;--------------------------------


    .module STM8_WOZMON 

    .include "inc/stm8s207.inc" 
    .include "inc/nucleo_8s207.inc"
    .include "inc/ascii.inc"
    .include "inc/gen_macros.inc" 

    STACK_SIZE=256 
    IN_SIZE=128 ; input buffer size 

;;-----------------------------------
    .area SSEG (ABS)
;; I prefer to put stack at end of RAM. 	
;;-----------------------------------
    .org RAM_SIZE-STACK_SIZE  
stack_space: .ds STACK_SIZE ; stack size 256 bytes maximum  
stack_full: ; after RAM end    

;--------------------------------------
    .area DATA  (ABS)
	.org 4
;--------------------------------------	
; bytes order of words is inverted for stm8
; compared to Apple I wozmon  
; examine memory address 
XAMADR: .blkw 1
; store address 
STORADR: .blkw 1 
; to hold hex number  parsed 
; also last address for BLOK_XAM  
LAST: .blkw 1
; save Y register 
YSAV: .blkw 1 
; operating mode 0=read byte, '.'=block read, ':'=store 
MODE: .blkb 1 

;; set input buffer at page 1 
;; stm8 default stack is at end of RAM 
;;---------------------------------------
   .area DATA (ABS)
   .org 0x100 
;;---------------------------------------
IN: .ds IN_SIZE ; input buffer 

;;--------------------------------------
    .area HOME 
;; interrupt vector table at 0x8000
;;--------------------------------------

    int RESET			; reset vector 

;;----------------------------------------
;; no interrupt used so program code 
;; can start after reset vector 
    .area  CODE (ABS)
    .org 0x8004  
;;----------------------------------------
; hardware initialisation 
RESET: 
; keep Fmaster at reset default, 2Mhz  
; stack pointer is a RAM_SIZE-1 at reset 
; no need to initialize it.
; init UART at 9600 BAUD, 2Mhz/9600=0x00d0 
;    clr UART_BRR2 ; not needed already 0 at reset 
    mov UART_BRR1,#0xd 
  	mov UART_CR2,#((1<<UART_CR2_TEN)|(1<<UART_CR2_REN)|(1<<UART_CR2_RIEN));
	bset UART,#UART_CR1_PIEN
;--------------------------------------------------
; command line interface
; input formats:
;       hex_number  -> display byte at that address 
;       hex_number.hex_number -> display bytes in that range 
;       hex_number: hex_byte [hex_byte]*  -> modify content of RAM or peripheral registers 
;       hex_numberR  -> run machine code a hex_number  address  
;----------------------------------------------------
; operating modes
XAM=0
XAM_BLOK='.
STOR=': 

GETLINE: 
    ld a,#CR 
    call ECHO 
    ld a,#'# 
    call ECHO
    clrw y 
    jra NEXTCHAR 
BACKSPACE:
    tnzw y 
    jreq NEXTCHAR 
    call ECHO 
    ld a,#SPACE 
    call ECHO 
    ld a,#BS 
    call ECHO 
    decw y 
NEXTCHAR:
    btjf UART_SR,#UART_SR_RXNE,. 
    ld a,UART_DR
    cp a,#BS  
    jreq BACKSPACE 
    cp a,#ESC 
    jreq GETLINE ; rejected characters cancel input, start over  
    cp a,#'`
    jrmi UPPER ; already uppercase 
; uppercase character
; all characters from 0x60..0x7f 
; are folded to 0x40..0x5f     
    and a,#0XDF  
UPPER: ; there is no lower case letter in buffer 
    ld (IN,y),a 
    call ECHO
    cp a,#CR 
    jreq EOL
    incw y 
    jra NEXTCHAR  
EOL: ; end of line, now analyse input 
    ldw y,#-1
    clr a  
SETMODE: 
    _straz MODE  
BLSKIP: ; skip blank  
    incw y 
NEXTITEM:
    ld a,(IN,y)
    cp a,#CR ; 
    jreq GETLINE ; end of input line  
    cp a,#XAM_BLOK
    jrmi BLSKIP 
    jreq SETMODE 
    cp a,#STOR 
    jreq SETMODE 
    cp a,#'R 
    jreq RUN
    _stryz YSAV ; save for comparison
    clrw x 
NEXTHEX:
    ld a,(IN,y)
    xor a,#0x30 
    cp a,#10 
    jrmi DIG 
    cp a,#0x71 
    jrmi NOTHEX 
    sub a,#0x67
DIG: 
    push #4
    swap a 
HEXSHIFT:
    sll a 
    rlcw x  
    dec (1,sp)
    jrne HEXSHIFT
    pop a 
    incw y
    jra NEXTHEX
NOTHEX:
    cpw y,YSAV 
    jrne GOTNUMBER
    jp GETLINE ; no hex number  
GOTNUMBER: 
    _ldaz MODE 
    jrne NOTREAD ; not READ mode  
; set XAM and STOR address 
    _strxz XAMADR 
    _strxz STORADR 
    _strxz LAST 
    clr a 
    jra NXTPRNT 
NOTREAD:  
; which mode then?        
    cp a,#': 
    jrne XAM_BLOCK
    ld a,xl 
    _ldxz STORADR 
    ld (x),a 
    incw x 
    _strxz STORADR 
TONEXTITEM:
    jra NEXTITEM 
RUN:
    _ldxz XAMADR 
    jp (x)
XAM_BLOCK:
    _strxz LAST 
    _ldxz XAMADR
    incw x 
    ld a,xl
NXTPRNT:
    jrne PRDATA 
    ld a,#CR 
    call ECHO 
    ld a,xh 
    call PRBYTE 
    ld a,xl 
    call PRBYTE 
    ld a,#': 
    call ECHO 
PRDATA:
    ld a,#SPACE 
    call ECHO
    ld a,(x)
    call PRBYTE
    incw x
XAMNEXT:
    cpw x,LAST 
    jrugt TONEXTITEM
MOD8CHK:
    ld a,xl 
    and a,#7 
    jra NXTPRNT
PRBYTE:
    push a 
    swap a 
    call PRHEX 
    pop a 
PRHEX:
    and a,#15 
    add a,#'0
    cp a,#'9+1  
    jrmi ECHO 
    add a,#7 
ECHO:
    btjf UART_SR,#UART_SR_TXE,.
    ld UART_DR,a 
    RET 

;----------------------------
; code to test 'R' command 
; blink LED on NUCLEO board 
;----------------------------
.if 1
r_test:
    bset PC_DDR,#5
    bset PC_CR1,#5
1$: bcpl PC_ODR,#5 
; delay 
    ld a,#4
    clrw x
2$:
    decw x 
    jrne 2$
    dec a 
    jrne 2$ 
; if key exit 
    btjf UART_SR,#UART_SR_RXNE,1$
    ld a,UART_DR 
; reset MCU to ensure monitor
; with peripherals in known state
    _swreset

;------------------------------------
; another program to test 'R' command
; print ASCII characters to terminal
; in loop 
;-------------------------------------
ascii:
    ld a,#SPACE
1$:
    call ECHO 
    inc a 
    cp a,#127 
    jrmi 1$
    ld a,#CR 
    call ECHO 
; if key exit 
    btjf UART_SR,#UART_SR_RXNE,ascii
    ld a,UART_DR 
; reset MCU to ensure monitor
; with peripherals in known state
    _swreset

.endif 

