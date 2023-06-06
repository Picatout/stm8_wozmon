;;---------------------------------------
;; WOZMON on STM8 following same 
;; model 
;;--------------------------------------

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;   COMMENTS 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
;; 1) Apple I keyboard interface was setting 
;;    setting bit 7 to 1 
;;     no need for it here 
;; 2) STM8 have 16 bits X,Y registers 
;;    I use this facility to avoid page 0
;;    pointers  
;; 3) STM8 have stack relative addressing 
;;    also very helpfull to avoid global 
;;    variables in RAM.  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    .module STM8_WOZMON 

    .include "inc/stm8s207.inc" 
    .include "inc/nucleo_8s207.inc"
    .include "inc/ascii.inc"
    .include "inc/gen_macros.inc" 

    STACK_SIZE=256 
    TIB_SIZE=128 ; input buffer size 

;;-----------------------------------
    .area SSEG (ABS)
;; I prefer to put stack at end of RAM. 	
;;-----------------------------------
    .org RAM_SIZE-STACK_SIZE  
stack_space: .ds STACK_SIZE ; stack size 256 bytes maximum  
stack_full: ; after RAM end    

;--------------------------------------
    .area DATA (ABS)
	.org 0 
; I reserve page 0 for system variables. 
; As 6502, address in this range 
; can be accessed with short code 
; sdasstm8 assembler don't code
; them, so I created a set of macros in 
; inc/gen_macros.inc 
; to supplement the assembler 
;--------------------------------------	
cnt: .blkb 1 ; count of character in IN buffer 
mode: .blkb 1 ; command mode 
start: .blkw 1 ; range start address 
last: .blkw 1   ; range last address 
acc16: .blkb 1 ; accumulator upper byte
acc8: .blkb 1  ; accumulator lower byte 

;; set input buffer at page 1 
;;---------------------------------------
   .area DATA (ABS)
   .org 0x100 
;;---------------------------------------
IN: .ds TIB_SIZE ; input buffer 
free: ; 0x180 free RAM start here, size=stack_space-free+1

;;--------------------------------------
    .area HOME 
;; interrupt vector table at 0x8000
;;--------------------------------------

    int reset			; RESET vector 

;;----------------------------------------
;; no interrupt used so program code 
;; can start after reset vector 
    .area  CODE (ABS)
    .org 0x8004  
;;----------------------------------------
; hardware initialisation 
reset: 
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
;       R  -> run binary code a last entered address  
;----------------------------------------------------
READ=0
READ_BLOCK=255

cli: 
    ld a,#CR 
    call putchar 
    ld a,#'# 
    call putchar ; prompt character 
    _clrz mode 
    call getline
    tnz cnt 
    jreq cli 
    ldw y,#IN  
    clrw x
    _strxz last  
parse_input:     
; parse input line      
    call next_char 
    jreq execute_cmd 
    cp a,#'R 
    jrne 4$ 
    jp run 
4$: cp a,#':
    jrne 5$ 
    jp modify 
5$:
    cp a,#'. 
    jrne 6$ 
    cpl mode
    _ldxz last 
    _strxz start 
    jra parse_input 
6$: 
    cp a,#SPACE 
    jreq parse_input ; skip blank 
    decw y 
    inc cnt 
    call parse_hex
    tnz a ; unknown token ignore rest of line  
    jreq execute_cmd
    _strxz last 
    jra parse_input 
execute_cmd:
    _ldaz mode 
    jrne exam_block
    _ldxz last 
    _strxz start 
    callr exam 
    jra cli 

;---------------------------------
;  run machine code routine 
;---------------------------------
run:
    ldw x,last  
    call (x)
    jp cli 

;-------------------------------------
; modify RAM or peripheral register 
; read byte list from input buffer
;--------------------------------------
modify:
    _ldxz last 
    _strxz start 
    callr exam 
1$:
    callr skip_blank
    call parse_hex
    tnz a 
    jreq 9$ 
    ld a,xl 
    _ldxz start 
    ld (x),a 
    incw x 
    _strxz start
    jra 1$ 
9$: jp cli 

skip_blank:
    tnz cnt 
    jreq 9$ 
    incw y
    ld a,(y)
    cp a,#SPACE 
    jreq skip_blank 
9$: ret 

;------------------------------------------
;  display byte value at 'start' address 
;------------------------------------------
exam:
    call print_adr 
    call print_byte 
    ret 

;-------------------------------------------
; display memory in range 'start'...'last' 
;-------------------------------------------    
    COUNT=1 
    ROW_SIZE=3
    VSIZE=3
exam_block:
    _vars VSIZE 
    _ldxz last 
    subw x,start 
    incw x 
    ldw (COUNT,sp),x ; bytes to display count 
new_row: 
    ld a,#8
    ld (ROW_SIZE,sp),a ; bytes per row 
    call exam ; display address and first byte of row 
row:
    ldw x,(COUNT,sp)
    decw x 
    jreq 9$ 
    ldw (COUNT,sp),x 
    dec (ROW_SIZE,sp)
    jrne 1$ 
    ld a,#CR 
    call putchar
    _ldxz start 
    incw x 
    _strxz start 
    jra new_row 
1$:
    _ldxz start
    incw x 
    _strxz start
    call print_byte 
    jra row 
9$:
    _drop VSIZE 
    jp cli  

;---------------------------
; read next character from 
; TIB
; input:
;   none:
; output:
;    A 
; side effect: 
;    Y  incremented 
;    cnt decremented 
;----------------------------- 
next_char:
    ld a,cnt 
    jreq 9$ 
    ld a,(y)
    dec cnt 
    incw y 
9$: ret 

;----------------------------
; parse hexadecimal number 
; from input buffer 
; input:
;    A   first character 
;    Y   pointer to TIB 
; output: 
;    X     number 
;    Y     point after number 
;-----------------------------      
parse_hex:
    push #0 
    clrw x
    _strxz acc16 
1$:    
    callr next_char 
    jreq 8$
    xor a,#0x30
    cp a,#10 
    jrmi 2$   ; 0..9 
    add a,#0x8f  
    jrnc 9$ 
    add a,#10 ; 'A..'F 
2$: 
    sllw x  ; x*16
    sllw x 
    sllw x 
    sllw x 
    _straz acc8 
    addw x,acc16 ; x+=digit 
    inc (1,sp) ; increment digit count 
    jra 1$
8$: ; end of line 
    pop a   
    ret 
9$: ; end of hex number
    pop a
    decw y  ; put back last character  
    inc cnt 
    ret 

;-----------------------------------
;  print address in start variable 
;  input: 
;    none 
;  output:
;   none 
;-------------------------------------
print_adr:
    _ldxz start 
    callr print_hex 
    ld a,#': 
    callr putchar 
    jra space 

;-------------------------------------
; print byte at 'start' address 
; input:
;   none 
; output:
;   none 
;--------------------------------------
print_byte:
    _ldxz start
    ld a,(x)
    clrw x 
    ld xl,a 
    callr print_hex 
space:
    ld a,#SPACE 
    callr putchar 
    ret 


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;     TERMIO 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;-------------------------------
;  print hexadecimal number 
; input:
;    X  number to print 
; output:
;    none 
;--------------------------------
print_hex: 
    ld a,xh
    tnz a 
    jreq 1$ 
    swap a 
    call print_digit 
    ld a,xh 
    call print_digit 
1$: 
    ld a,xl 
    swap a 
    call print_digit
    ld a,xl 
    call print_digit
    ret 

print_digit: 
    and a,#15 
    add a,#'0 
    cp a,#'9+1 
    jrmi 1$
    add a,#7 
1$:
    call putchar 
9$:
    ret 

;---------------------------------------
; get next character from terminal 
; like Apple I foldback ASCII code 
; from 0x60..0x7f to 0x40..0x5f
; input:
;   none 
; output: 
;   A     character 
;----------------------------------------
getchar:
    btjf UART_SR,#UART_SR_RXNE,. 
    ld a,UART_DR 
    cp a,#'a 
    jrmi 9$
    cp a,#'z+1 
    jrpl 9$
    and a,#0xDF ; upper case  
9$:
    ret 

;---------------------------------------
; send character to terminal 
; input:
;    A    character to send 
; output:
;    none 
;----------------------------------------    
putchar:
    btjf UART_SR,#UART_SR_TXE,. 
    ld UART_DR,a 
    ret 

;------------------------------------
;  read text line from terminal 
;  put it in IN buffer 
;  CR to terminale input.
;  BS to deleter character left 
;  input:
;   none 
;  output:
;    IN      input line ASCIZ no CR  
;    cnt     line length 
;-------------------------------------
getline:
    ldw y,#IN 
    clr cnt 
1$:
    callr getchar 
    cp a,#CR 
    jreq 9$ 
    cp a,#BS 
    jrne 2$
    callr delback 
    jra 1$ 
2$: cp a,#SPACE 
    jrmi 1$  ; ignore others control char 
    callr putchar
    ld (y),a 
    incw y 
    inc cnt 
    jra 1$
9$: callr putchar 
;    clr (y)
    ret 

;-----------------------------------
; delete character left of cursor 
; decrement cnt and Y 
; input:
;   none 
; output:
;   none 
;-----------------------------------
delback:
    tnz cnt  
    jreq 9$
    decw y 
    dec cnt 
    call putchar 
    ld a,#SPACE 
    call putchar 
    ld a,#BS 
    call putchar 
9$:
    ret 


