;--------------------------
; blink NUCLEO BOARD LED 
; This LED is connected 
; on PORTC pin 5
; used to test R command 
; of stm8_wozmon 
;--------------------------

    .module BLINK 

    .include "inc/stm8s207.inc" 
    .include "inc/nucleo_8s207.inc"

    ; software reset 
    .macro _swreset
    mov WWDG_CR,#0X80
    .endm 

    STACK_SIZE=256 

;;-----------------------------------
    .area SSEG (ABS)
;; I prefer to put stack at end of RAM. 	
;;-----------------------------------
    .org RAM_SIZE-STACK_SIZE  
stack_space: .ds STACK_SIZE ; stack size 256 bytes maximum  
stack_full: ; after RAM end    

;------------------------------
    .area DATA 
;------------------------------

;;--------------------------------------
    .area HOME 
;; interrupt vector table at 0x8000
;;--------------------------------------

    int RESET			; reset vector 

;;----------------------------------------
;; no interrupt used so program code 
;; can start after reset vector 
;;---------------------------
    .area CODE (ABS)
    .org 0x8004

RESET: 


blink:
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

