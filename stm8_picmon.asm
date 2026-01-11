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
stack_empty: ; after RAM end    

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
rx_queue: .ds RX_QUEUE_SIZE ; UART1 receive circular queue 
rx_head:  .blkb 1 ; rx_queue head pointer
rx_tail:   .blkb 1 ; rx_queue tail pointer  

;; set input buffer at page 1 
;;---------------------------------------
   .area DATA (ABS)
   .org 0x80 
;;---------------------------------------
IN: .ds IN_SIZE ; input buffer 
free: ; 0x100 free RAM xamadr here, size=stack_space-free+1

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
; unlock FLASH IAP 
    mov FLASH_PUKR,#FLASH_KEY1
    mov FLASH_PUKR,#FLASH_KEY2 
;unlock EEPROM IAP 
    mov FLASH_DUKR,#EEPROM_KEY1 
    mov FLASH_DUKR,#EEPROM_KEY2
    call uart_init 
    rim
    call hello 
    _clrz xamadr 
    _clrz storadr 
    _clrz last 

;--------------------------------------------------
; command line interface
; input formats:
;       hex_number  -> display byte at that address 
;       hex_number.hex_number -> display bytes in that range 
;       hex_number: hex_byte [hex_byte]*  -> modify content of RAM or peripheral registers 
;       R  -> run binary code at xamadr address  
;----------------------------------------------------
; operatiing modes 
    NEXT=0 ; examine next byte: [adr]<ENTER>
    READ=1 ; examine range: adr1.adr2<ENTER>
    STORE=2 ; store to memory:  adr: byte ... <ENTER>
    MOVE=3 ; move range: adr1.adr2Madr3<ENTER>

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
    jrne parse
; at end of line 
    _ldaz mode 
    jrne 1$
    call exam_next 
    jra cli 
1$:
    call exam_block 
    jra cli
parse:
    cp a,#'R 
    jrne 1$ 
    _ldxz xamadr   
    jp (x) ; run machine code
1$:
    cp a,#'M 
    jrne 2$
    call copy_range 
    jra cli
2$: cp a,#':
    jrne 5$ 
    call modify 
    jra cli     
5$:
    cp a,#'Z 
    jrne 6$
    call zero_range 
    jra cli 
6$:    
    cp a,#'. 
    jrne 7$ 
    _ldaz mode 
    cp a,#READ 
    jrne cli ; here mode should be set to 1 
    jra next_char 
7$: 
    cp a,#SPACE+1 
    jrmi next_char ; skip separator and invalids characters  
    call parse_hex ; maybe an hexadecimal number 
    tnz a ; unknown token ignore rest of line
    jreq cli 
    ld a,mode 
    jreq 9$
    cp a,#READ
    jrne next_char 
    _strxz storadr
    _incz mode ; mode=STORE 
    jra next_char
9$:
    _strxz xamadr 
    _strxz storadr
    _incz mode    ; mode=READ 
    jra next_char 

;----------------------------
; examine next byte 
;---------------------------
exam_next:
    _ldxz xamadr
    call print_adr
    call print_mem
    incw x 
    _strxz xamadr
    ret 

;----------------------
; skip spaces char 
; between tokens 
;----------------------
skip_spaces:
    _next_char 
    cp a,#SPACE 
    jreq skip_spaces
    ret 

;----------------------------
; copy memory range
; cmd format: adr1.adr2Madr3 
; adr1.adr2 is range 
; adr2 is destination 
;-----------------------------
copy_range:
    call skip_spaces    
    call parse_hex 
    tnz a 
    jreq 9$ 
    ldw x,xamadr 
    ldw y,last
    cpw y,#free_flash
    jrmi forbidden 
1$:
    cpw x,storadr 
    jrugt 9$
    ld a,(x)
    ld (y),a 
    incw x
    jreq 9$  
    incw y 
    jra 1$
9$:
    ret 

;---------------------
; set a range to zero 
; adr1.adr2Z
;---------------------
zero_range:
    ldw x,xamadr
    cpw x,#free_flash 
    jrmi forbidden  
1$: 
    cpw x,last 
    jrugt 9$
    clr (x)
    incw x 
    jrne 1$
9$:
    ret 

;-------------------------------------
; modify memory or peripheral register 
; read byte list from input buffer
; format adr: byte|quote ...   
;--------------------------------------
modify:
    ldw x,storadr 
    cpw x,#0x8080 
    jrmi 0$
    cpw x,#free_flash
    jrpl 0$ 
    call forbidden 
    jra 9$
0$: call skip_spaces 
    cp a,#'" 
    jrne 1$ 
    call store_string 
    jra 0$ 
1$:
    call parse_hex
    tnz a 
    jreq 9$
    ld a,xl
    _ldxz storadr 
    ld (x),a 
    addw x,#1 
    jrc 9$
    _strxz storadr
    jra 0$ 
9$:  
    ret 

;---------------------
; store quoted string
;--------------------
store_string:
0$:
    _next_char 
    cp a,#'" 
    jreq 9$ 
    _ldxz storadr 
    ld (x),a 
    addw x,#1 
    jrc 8$
    _strxz storadr 
    jra 0$
8$:  
    _next_char 
    tnz a 
    jreq 9$
    cp a,#'"
    jrne 8$     
9$:
    ret 

;-------------------------
; try to overwrite monitor
;--------------------------
forbidden: 
    ldw x,#error_forbidden
    call puts 
    ret 
error_forbidden: .asciz "overwriting monitor is forbidden.\r"

;-------------------------
; print firwmare info 
;-------------------------
hello:
    ld a,#27 
    call putchar 
    ld a,#'c 
    call putchar 
    ldw x,#Copyright 
    call puts 
    ldw x,#free_flash
    call print_word
    ret 
Copyright: .asciz "STM8 Picatout monitor\rFree space start at "

;-------------------------------------------
; display memory in range 'xamadr'...'last' 
;-------------------------------------------    
    ROW_SIZE=1
    CHAR_CNT=2
    START_ADR=3
    VSIZE=4
exam_block:
    _vars VSIZE
    _ldxz xamadr
new_row: 
    ldw (START_ADR,SP),x 
    ld a,#16
    ld (ROW_SIZE,sp),a ; bytes per row 
    ld a,#CR 
    call putchar 
    call print_adr ; display address and first byte of row 
row:
    cpw x,last 
    jrugt 8$
    call print_mem ; display byte at address  
    addw x,#1
    dec (ROW_SIZE,sp)
    jrc 8$ 
    jreq 8$  
    jra row
8$: ; print ASCII characters
    ld a,#16 
    sub a,(ROW_SIZE,sp)
    jreq 9$
    ld (CHAR_CNT,sp),a 
; alignement spaces to be printed     
    ld a,(ROW_SIZE,sp)
    sll a 
    add a,(ROW_SIZE,sp)
    add a,#2
    call spaces
    ldw x,(START_ADR,SP) ; row start address 
81$:
    tnz (CHAR_CNT,sp) 
    jreq new_row 
    ld a,(x)
    cp a,#SPACE
    jrmi 82$
    cp a,#127
    jrmi 83$
82$:     
    ld a,#SPACE 
83$: 
    call putchar 
    addw x,#1
    jrc 9$
    dec (CHAR_CNT,sp)
    jra 81$ 
9$:
    _strxz xamadr
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
    sub a,#'0
    jrmi 9$ ; not a digit 
    cp a,#10 
    jrmi 2$   ; 0..9 
    cp a,#'A-'0 
    jrmi 9$
    sub a,#0x7
    cp a,#16 
    jrpl 9$ 
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
    call putchar 
    call space
    ret 

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
    call space 
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

mon_end:
.word 0,0
.asciz "MONITOR END"
free_flash:
