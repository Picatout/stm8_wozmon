;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Uart1 intterrupt handler 
;;; on receive character 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;--------------------------
; UART receive character
; in a FIFO buffer 
; CTRL+C (ASCII 3)
; cancel program execution
; and fall back to command line
; CTRL+X reboot system 
; CTLR+Z erase EEPROM autorun 
;        information and reboot
;--------------------------
UartRxHandler: ; console receive char 
	btjf UART_SR,#UART_SR_RXNE,5$ 
	ld a,UART_DR 
	cp a,#CTRL_C 
	jrne 2$
	jp user_interrupted
2$:
	cp a,#CAN ; CTRL_X 
	jrne 3$
	_swreset 	
3$:	cp a,#CTRL_Z 
	jrne 4$
	call clear_autorun
	_swreset 
4$:
	push a 
	ld a,#rx1_queue 
	add a,rx1_tail 
	clrw x 
	ld xl,a 
	pop a 
	ld (x),a 
	ld a,rx1_tail 
	inc a 
	and a,#RX_QUEUE_SIZE-1
	ld rx1_tail,a 
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
	_vars VSIZE 
; baud rate 115200
; BRR value = 16000000/115200=0x8B  
    mov UART_BRR2,0xb 
	mov UART_BRR1,0x8  
3$:
    clr UART_DR
	mov UART_CR2,#((1<<UART_CR2_TEN)|(1<<UART_CR2_REN)|(1<<UART_CR2_RIEN));
	bset UART_CR2,#UART_CR2_SBK
    btjf UART_SR,#UART_SR_TC,.
    clr rx1_head 
	clr rx1_tail
	ret

