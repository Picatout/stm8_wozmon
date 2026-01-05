;;---------------------------------------
;; WOZMON on STM8 
;; personnal version, more structured
;;
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

    .module STM8_PICMON 

    .include "config.inc" 
    .include "inc/ascii.inc"
    .include "inc/gen_macros.inc" 

    STACK_SIZE=256 
    IN_SIZE=128 ; input buffer size 
    RX_QUEUE_SIZE=16

;;-----------------------------------
    .area SSEG (ABS)
;; I prefer to put stack at end of RAM. 	
;;-----------------------------------
    .org RAM_SIZE-STACK_SIZE  
stack_space: .ds STACK_SIZE ; stack size 256 bytes maximum  
stack_full: ; after RAM end    

;;--------------------------------------
    .area HOME 
;; interrupt vector table at 0x8000
;;--------------------------------------

    int reset  			    ; RESET vector 
	int NonHandledInterrupt ; trap instruction 
	int NonHandledInterrupt ;int0 TLI   external top level interrupt
	int NonHandledInterrupt ;int1 AWU   auto wake up from halt
	int NonHandledInterrupt ;int2 CLK   clock controller
	int NonHandledInterrupt ;int3 EXTI0 gpio A external interrupts
	int NonHandledInterrupt ;int4 EXTI1 gpio B external interrupts
	int NonHandledInterrupt ;int5 EXTI2 gpio C external interrupts
	int NonHandledInterrupt ;int6 EXTI3 gpio D external interrupts
	int NonHandledInterrupt ;
	int NonHandledInterrupt ;int8 beCAN RX interrupt
	int NonHandledInterrupt ;int9 beCAN TX/ER/SC interrupt
	int NonHandledInterrupt ;int10 SPI End of transfer
	int NonHandledInterrupt ;int11 TIM1 update/overflow/underflow/trigger/break
	int NonHandledInterrupt ; int12 TIM1 capture/compare
	int NonHandledInterrupt ;int13 TIM2 update /overflow
	int NonHandledInterrupt ;int14 TIM2 capture/compare
	int NonHandledInterrupt ;int15 TIM3 Update/overflow
	int NonHandledInterrupt ;int16 TIM3 Capture/compare
	int NonHandledInterrupt ;int17 UART1 TX completed
	int NonHandledInterrupt ;int18 UART1 RX full 
	int NonHandledInterrupt ;int19 I2C 
	int NonHandledInterrupt ;int20 UART3 TX completed
	int NonHandledInterrupt ;int21 UART3 RX full
	int NonHandledInterrupt ;int22 ADC2 end of conversion
	int NonHandledInterrupt	;int23 TIM4 update/overflow ; used as msec ticks counter
	int NonHandledInterrupt ;int24 flash writing EOP/WR_PG_DIS
	int NonHandledInterrupt ;int25  not used
	int NonHandledInterrupt ;int26  not used
	int NonHandledInterrupt ;int27  not used
	int NonHandledInterrupt ;int28  not used
	int NonHandledInterrupt ;int29  not used

;--------------------------------------
    .area DATA (ABS)
	.org 4
; I reserve page 0 for system variables. 
; As stm8, address in this range 
; can be accessed with short code 
; sdasstm8 assembler don't code
; them, so I created a set of macros in 
; "inc/gen_macros.inc" 
; to supplement the assembler 
; all macros name's begin with '_' 
;--------------------------------------	
mode: .blkb 1 ; command mode 
xamadr: .blkw 1 ; examine address 
storadr: .blkw 1 ; store address 
last: .blkw 1   ; last address parsed from input 
rx1_queue: .ds RX_QUEUE_SIZE ; UART1 receive circular queue 
rx1_head:  .blkb 1 ; rx1_queue head pointer
rx1_tail:   .blkb 1 ; rx1_queue tail pointer  

;; set input buffer at page 1 
;;---------------------------------------
   .area DATA (ABS)
   .org 0x100 
;;---------------------------------------
IN: .ds IN_SIZE ; input buffer 
free: ; 0x180 free RAM xamadr here, size=stack_space-free+1

;;--------------------------------------
    .area CODE
;;--------------------------------------

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; non handled interrupt 
; reset MCU
;;;;;;;;;;;;;;;;;;;;;;;;;;;
NonHandledInterrupt:
	_swreset ; see "inc/gen_macros.inc"


;---------------------------
; hardware initialisation 
;---------------------------
reset: 
; stack pointer is a RAM_SIZE-1 at reset 
; no need to initialize it.
    clr CLK_CKDIVR ; 16Mhz HSI 
.IF STM8L151
    bset CLK_PCKENR1,#CLK_PCKENR1_USART1 
.ENDIF 
; init UART at 115200 BAUD, 16Mhz/115200=0x8b   
    mov UART_BRR2,#0xb
    mov UART_BRR1,#0x8
  	mov UART_CR2,#((1<<UART_CR2_TEN)|(1<<UART_CR2_REN));|(1<<UART_CR2_RIEN));
;	bset UART_CR1,#UART_CR1_PIEN

;--------------------------------------------------
; command line interface
; input formats:
;       hex_number  -> display byte at that address 
;       hex_number.hex_number -> display bytes in that range 
;       hex_number: hex_byte [hex_byte]*  -> modify content of RAM or peripheral registers 
;       R  -> run binary code at xamadr address  
;----------------------------------------------------
; operatiing modes 
    NOP=0
    READ=1 ; single address or block
    STORE=2 

    ; get next character from input buffer 
    .macro _next_char 
    ld a,(y)
    incw y 
    .endm ; 4 bytes, 2 cy 

cli: 
    ld a,#CR 
    call putchar 
    ld a,#'# 
    call putchar ; prompt character 
    call getline
; analyze input line      
    ldw y,#IN  
    _clrz mode 
next_char:     
    _next_char
    tnz a     
    jrne parse01
; at end of line 
    tnz mode 
    jreq cli 
    call exam_block 
    jra cli 
parse01:
    cp a,#'R 
    jrne 4$
    _ldxz xamadr   
    jp (x) ; run machine code
4$: cp a,#':
    jrne 5$ 
    call modify 
    jra cli     
5$:
    cp a,#'. 
    jrne 8$ 
    tnz mode 
    jreq cli ; here mode should be set to 1 
    jra next_char 
8$: 
    cp a,#SPACE 
    jrmi next_char ; skip separator and invalids characters  
    call parse_hex ; maybe an hexadecimal number 
    tnz a ; unknown token ignore rest of line
    jreq cli 
    tnz mode 
    jreq 9$
    call exam_block
    jra next_char
9$:
    _strxz xamadr 
    _strxz storadr
    _incz mode
    jra next_char 

;-------------------------------------
; modify RAM or peripheral register 
; read byte list from input buffer
;--------------------------------------
modify:
1$: 
; skip spaces 
    _next_char 
    cp a,#SPACE 
    jreq 1$ 
    call parse_hex
    tnz a 
    jreq 9$ 
    ld a,xl 
    _ldxz storadr 
    ld (x),a 
    incw x 
    _strxz storadr
    jra 1$ 
9$: _clrz mode 
    ret 

;-------------------------------------------
; display memory in range 'xamadr'...'last' 
;-------------------------------------------    
    ROW_SIZE=1
    VSIZE=1
exam_block:
    _vars VSIZE
    _ldxz xamadr
new_row: 
    ld a,#8
    ld (ROW_SIZE,sp),a ; bytes per row 
    ld a,#CR 
    call putchar 
    call print_adr ; display address and first byte of row 
    call print_mem ; display byte at address  
row:
    incw x 
    cpw x,last 
    jrugt 9$ 
    dec (ROW_SIZE,sp)
    jreq new_row  
    call print_mem  
    jra row 
9$:
    _clrz mode 
    _drop VSIZE 
    ret  

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
    push #0 ; digits count 
    clrw x
1$:    
    xor a,#0x30
    cp a,#10 
    jrmi 2$   ; 0..9 
    cp a,#0x71
    jrmi 9$
    sub a,#0x67  
2$: push #4
    swap a 
3$:
    sll a 
    rlcw x 
    dec (1,sp)
    jrne 3$
    pop a
    inc (1,sp) ; digits count  
    _next_char 
    tnz a 
    jrne 1$
9$: ; end of hex number
    decw y  ; put back last character  
    pop a 
    tnz a 
    jreq 10$
    _strxz last 
10$:
    ret 

;-----------------------------------
;  print address in xamadr variable
;  followed by ': '  
;  input: 
;    X     address to print 
;  output:
;   X      not modified 
;-------------------------------------
print_adr: 
    callr print_word 
    ld a,#': 
    callr putchar 
    jra space

;-------------------------------------
;  print byte at memory location 
;  pointed by X followed by ' ' 
;  input:
;     X     memory address 
;  output:
;    X      not modified 
;-------------------------------------
print_mem:
    ld a,(x) 
    call print_byte 
    

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;     TERMIO 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------
; print blank space 
;-------------------------------
space:
    ld a,#SPACE 
    callr putchar 
    ret 

;-------------------------------
;  print hexadecimal number 
; input:
;    X  number to print 
; output:
;    none 
;--------------------------------
print_word: 
    ld a,xh
    call print_byte 
    ld a,xl 
    call print_byte 
    ret 

;---------------------
; print byte value 
; in hexadecimal 
; input:
;    A   value to print 
; output:
;    none 
;-----------------------
print_byte:
    push a 
    swap a 
    call print_digit 
    pop a 

;-------------------------
; print lower nibble 
; as digit 
; input:
;    A     hex digit to print
; output:
;   none:
;---------------------------
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
;-------------------------------------
getline:
    ldw y,#IN 
1$:
    clr (y) 
    callr getchar 
    cp a,#CR 
    jreq 9$ 
    cp a,#BS 
    jrne 2$
    callr delback 
    jra 1$ 
2$: 
    cp a,#ESC 
    jrne 3$
    ldw y,#IN
    clr(y)
    ret 
3$:    
    cp a,#SPACE 
    jrmi 1$  ; ignore others control char 
    callr putchar
    ld (y),a 
    incw y 
    jra 1$
9$: callr putchar 
    ret 

;-----------------------------------
; delete character left of cursor 
; decrement Y 
; input:
;   none 
; output:
;   none 
;-----------------------------------
delback:
    cpw y,#IN 
    jreq 9$     
    callr putchar ; backspace 
    ld a,#SPACE    
    callr putchar ; overwrite with space 
    ld a,#BS 
    callr putchar ;  backspace
    decw y
9$:
    ret 

;----------------------------
; code to test 'R' command 
; blink LED on NUCLEO board 
;----------------------------
.if 0
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
; reset MCU to ensure peripherals known 
; state at monitor entry.
    _swreset 
.endif 

