;-------------------------------------------------------------------------------
; blinkg frequency assembly code  (MSP430FR2433) 
;
; Lab requirement:
; - SMCLK/MCLK = 8 MHz
; - UART0 = 9600 baud, 8-N-1, using interrupts (RX + TX)
; - LED P1.1 blinks at user-selected frequency (1 Hz to 20 Hz), 50% duty cycle
; - Prints a prompt message asking user to send a value in RealTerm "Send" tab
; - Range check: reject >20 or <1
; RealTerm tip (easiest):
; - Set Display = "ANSI"
; - In "Send" tab choose "Hex" and send ONE byte:
;     01 = 1 Hz ... 14 = 20 Hz
;-------------------------------------------------------------------------------
            .cdecls C,LIST,"msp430FR2433.h"
            .def    RESET
;-----------------------------
; Pins configuration
;-----------------------------
LED_PIN     .equ    BIT1            ; P1.1 green LED
TX_PIN      .equ    BIT4            ; P1.4 UCA0TXD
RX_PIN      .equ    BIT5            ; P1.5 UCA0RXD

;-----------------------------
; UART 9600 baud rate confifuration
;-----------------------------
U0_UCBR     .equ    52
U0_UCBRF    .equ    1
U0_UCBRS    .equ    0x49
U0_UCOS16   .equ    1

CR          .equ    0x0D
LF          .equ    0x0A

;-------------------------------------------------------------------------------
; RAM
;-------------------------------------------------------------------------------
            .data
TXptr       .word   0               ; pointer to next TX byte
TxBusy      .byte   0               ; 1 = TX in progress, 0 = idle

RxFlag      .byte   0               ; 1 = new RX byte ready
RxByte      .byte   0               ; last received byte

CurrentHz   .byte   1               ; current freq (1..20)

;-------------------------------------------------------------------------------
; ROM strings
;-------------------------------------------------------------------------------
            .text
PromptMSG:  .byte   "Send blink freq 1-20 (HEX 01-14) then click Send",CR,LF,"> ",0
BadMSG:     .byte   "BAD (use 01-14 hex = 1-20 Hz)",CR,LF,"> ",0
OkMSG:      .byte   "OK",CR,LF,"> ",0

;-------------------------------------------------------------------------------
; Half-period table (words): counts for ACLK=32768 Hz, toggle every half-period
; CCR0 = (32768/(2*Hz)) - 1
;-------------------------------------------------------------------------------
HalfTbl:
            .word   16384   ; 1 Hz
            .word   8192    ; 2 Hz
            .word   5461    ; 3 Hz
            .word   4096    ; 4 Hz
            .word   3276    ; 5 Hz
            .word   2730    ; 6 Hz
            .word   2341    ; 7 Hz
            .word   2048    ; 8 Hz
            .word   1820    ; 9 Hz
            .word   1638    ; 10 Hz
            .word   1489    ; 11 Hz
            .word   1365    ; 12 Hz
            .word   1260    ; 13 Hz
            .word   1170    ; 14 Hz
            .word   1092    ; 15 Hz
            .word   1024    ; 16 Hz
            .word   963     ; 17 Hz
            .word   910     ; 18 Hz
            .word   862     ; 19 Hz
            .word   819     ; 20 Hz

;-------------------------------------------------------------------------------
; RESET
;-------------------------------------------------------------------------------
RESET       mov.w   #__STACK_END, SP
StopWDT     mov.w   #WDTPW|WDTHOLD, &WDTCTL

            bic.w   #LOCKLPM5, &PM5CTL0     ; unlock GPIO

;-------------------------------------------------------------------------------
; CLOCK: set DCO ~8 MHz using FLL with REFO (32768 Hz)
; 8MHz / 32768 ≈ 244.14  => (FLLN+1)=244 => FLLN=243
;-------------------------------------------------------------------------------
SetupCLK    bis.w   #SCG0, SR                    ; Disable FLL = Frequency Locked Loop to generate 16 MHz MCLK
            mov.w   #SELREF__REFOCLK, &CSCTL3    ; FLL reference CLK = REFOCLK
            clr     &CSCTL0                      ; Clear tap and mod settings for FFL fresh start

            ; choose a DCO range that supports ~8MHz (DCORSEL_3 is common)
            bic.w   #DCORSEL_7, &CSCTL1           ;DCO frequency range select: 7
            bis.w   #DCORSEL_3, &CSCTL1

            mov.w   #FLLD__1+243, &CSCTL2        ; FLLN=243, FLLD=1
            nop
            nop
            nop
            bic.w   #SCG0, SR                    ; Enable FLL

FLL_wait    bit.w   #FLLUNLOCK0|FLLUNLOCK1, &CSCTL7
            jnz     FLL_wait
            bic.w   #DCOFFG, &CSCTL7
;-------------------------------------------------------------------------------
; LED P1.1 output configuration
;-------------------------------------------------------------------------------
            bic.b   #LED_PIN, &P1OUT
            bis.b   #LED_PIN, &P1DIR
;-------------------------------------------------------------------------------
; UART pin function select (P1.4/P1.5)
;-------------------------------------------------------------------------------
            bis.b   #(TX_PIN|RX_PIN), &P1SEL0
            bic.b   #(TX_PIN|RX_PIN), &P1SEL1
;-------------------------------------------------------------------------------
; UART setup on eUSCI_A0 module
;-------------------------------------------------------------------------------
SetupUART   bis.w   #UCSWRST, &UCA0CTLW0         ; hold in reset
            ; select SMCLK
            bic.w   #(UCSSEL0|UCSSEL1), &UCA0CTLW0
            bis.w   #UCSSEL__SMCLK, &UCA0CTLW0
            mov.w   #U0_UCBR,  &UCA0BRW
            mov.b   #U0_UCBRS, &UCA0MCTLW_H
            mov.b   #(U0_UCBRF|U0_UCOS16), &UCA0MCTLW_L
            bic.w   #UCSWRST, &UCA0CTLW0         ; release reset
            bis.w   #UCRXIE, &UCA0IE             ; RX interrupt enable
            bic.w   #UCTXIE, &UCA0IE             ; TX interrupt off until needed
            mov.b   #0, &TxBusy
            mov.b   #0, &RxFlag
            mov.b   #1, &CurrentHz
;-------------------------------------------------------------------------------
; TimerA0 configuration
;-------------------------------------------------------------------------------
SetupTA     mov.w   #CCIE, &TA0CCTL0
            mov.w   #(16384-1), &TA0CCR0
            mov.w   #(TASSEL__ACLK|MC__UP|ID__1), &TA0CTL
;-------------------------------------------------------------------------------
; Enable interrupts, print prompt
;-------------------------------------------------------------------------------
            nop
            bis.w   #GIE, SR
            nop

            mov.w   #PromptMSG, R15
            call    #StartTX
;-------------------------------------------------------------------------------
; MAIN LOOP
;-------------------------------------------------------------------------------
MainLoop
            tst.b   &RxFlag
            jz      MainLoop
            mov.b   #0, &RxFlag
            mov.b   &RxByte, R14          ; R14 = received value
            cmp.b   #1, R14
            jl      BadInput              ; if <1
            cmp.b   #21, R14
            jge     BadInput              ; if >=21 (i.e., >20)
            ; save CurrentHz
            mov.b   R14, &CurrentHz
            ; index = (Hz-1) * 2  (word table)
            dec.b   R14                   ; Hz-1
            mov.b   R14, R12              ; copy
            rla     R12                   ; *2 bytes offset
            ; load halfCounts from table
            mov.w   HalfTbl(R12), R13     ; R13 = halfCounts
            dec.w   R13                   ; CCR0 = halfCounts - 1
            mov.w   R13, &TA0CCR0
            ; respond OK + prompt
            mov.w   #OkMSG, R15
            call    #StartTX
            jmp     MainLoop
BadInput
            mov.w   #BadMSG, R15
            call    #StartTX
            jmp     MainLoop

;-------------------------------------------------------------------------------
; StartTX (interrupt-driven)
;-------------------------------------------------------------------------------
StartTX
            push    R14
wait_idle   tst.b   &TxBusy
            jnz     wait_idle

            mov.b   #1, &TxBusy
            mov.w   R15, &TXptr
            ; prime first byte
            mov.w   &TXptr, R14
            mov.b   @R14+, &UCA0TXBUF
            mov.w   R14, &TXptr
            bis.w   #UCTXIE, &UCA0IE      ; enable TX interrupt (UCTXIFG vector)
            pop     R14
            ret
;-------------------------------------------------------------------------------
; TimerA0 ISR: toggle LED (50% duty by toggling each half-period)
;-------------------------------------------------------------------------------
TIMER0_A0_ISR
            xor.b   #LED_PIN, &P1OUT
            reti
;-------------------------------------------------------------------------------
; USCI_A0 ISR (RX + TX) using UCA0IV
; UCA0IV values:
;   0x02 = RXIFG
;   0x04 = TXIFG
;-------------------------------------------------------------------------------
USCI_A0_ISR
            push    R15
            mov.w   &UCA0IV, R15
            cmp.w   #2, R15
            jeq     UART_RX
            cmp.w   #4, R15
            jeq     UART_TX
            pop     R15
            reti
UART_RX
            mov.b   &UCA0RXBUF, &RxByte
            mov.b   #1, &RxFlag
            pop     R15
            reti
UART_TX
            mov.w   &TXptr, R15
            tst.b   0(R15)
            jz      TX_done
            mov.b   @R15+, &UCA0TXBUF
            mov.w   R15, &TXptr
            pop     R15
            reti
TX_done
            bic.w   #UCTXIE, &UCA0IE
            mov.b   #0, &TxBusy
            pop     R15
            reti
;-------------------------------------------------------------------------------
; VECTORS
;-------------------------------------------------------------------------------
            .sect   ".reset"
            .short  RESET
            .sect   USCI_A0_VECTOR
            .short  USCI_A0_ISR
            .sect   TIMER0_A0_VECTOR
            .short  TIMER0_A0_ISR
            .sect   .stack
            .global __STACK_END