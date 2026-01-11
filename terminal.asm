;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Uart1 intterrupt handler 
;;; on receive character 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;--------------------------
; UART receive character
; in a FIFO buffer 
; CTRL+C (ASCII 3)
; reboot MCU  
;--------------------------
UartRxHandler: ; console receive char 
    btjf UART_SR,#UART_SR_RXNE,5$ 
	ld a,UART_DR 
	cp a,#CTRL_C 
	jrne 2$
	_swreset 	
2$:
	push a 
	ld a,#rx_queue 
	add a,rx_tail 
	clrw x 
	ld xl,a 
	pop a 
	ld (x),a 
	ld a,rx_tail 
	inc a 
	and a,#RX_QUEUE_SIZE-1
	ld rx_tail,a 
;	bres UART_SR,#UART_SR_RXNE
5$:	iret 


;---------------------------------------------
; initialize UART, 115200 8N1
; FMSTR = 16Mhz 
; input:
;	none       
; output:
;   none
;---------------------------------------------
uart_init:
.IF STM8L151
    bset CLK_PCKENR1,#CLK_PCKENR1_USART1 
.ENDIF 
; init UART at 115200 BAUD, 16Mhz/115200=0x8b   
    mov UART_BRR2,#0xb
    mov UART_BRR1,#0x8
  	mov UART_CR2,#(1<<UART_CR2_TEN)|(1<<UART_CR2_REN)|(1<<UART_CR2_RIEN);
	bset UART_CR1,#UART_CR1_PIEN
    clr rx_head 
	clr rx_tail
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;     TERMIO 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;--------------------------------
; print blank space 
;-------------------------------
space:
    ld a,#SPACE 
    callr putchar 
    ret 

;-------------------------
; print many spaces 
; input:
;    A    count 
;-------------------------
spaces:
    push a
    ld a,#SPACE  
1$:
    callr putchar 
    dec (1,sp)
    jrne 1$ 
    _drop 1 
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
; wait for next character from terminal 
; input:
;   none 
; output: 
;   A     character 
;----------------------------------------
getchar:
	pushw x 
	ld a,rx_head
1$:	  
    wfi 
	cp a,rx_tail
    jreq 1$
	clrw x 
	add a,#rx_queue 
	ld xl,a  
	inc rx_head 
	ld a,#RX_QUEUE_SIZE-1 
	and a,rx_head  
	_straz rx_head  
	ld a,(x)
	popw x 
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

;------------------------------
; print sero terminated string 
; input:
;    X   string address 
;-----------------------------
puts:
    ld a,(x)
    jreq 9$
    call putchar 
    incw x 
    jra puts 
9$:
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
; uppercase lower letters 
    cp a,#'a 
	jrmi 4$
	and a,#0x5F 
4$: cpw y,#IN+IN_SIZE-1
	jrpl 1$ ; buffer full ignre character 
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

