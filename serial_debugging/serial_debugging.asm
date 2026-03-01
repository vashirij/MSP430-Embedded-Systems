;*******************************************************************************
; FR2433 Stoplight + Serial Debug (Part 2
; SMCLK = 16MHz, UART  = 19200 baud, TX=P1.4, RX=P1.5
; Timer = ACLK 32768Hz -> 1 second tick using TA0CCR0 interrupt
; Prints: Event: TIMER_TICK, Old state: XXXXXX; New state: YYYYYY
; LED mapping (LEDs changes):
;   P2.0 LeftY   (moved off P1.4)
;   P2.1 LeftR   (moved off P1.5)
;*******************************************************************************
            .cdecls C,LIST,"msp430FR2433.h"
            .def RESET
;------------------------------------------------------------------------------
; UART SETTINGS (16MHz -> 19200)
;------------------------------------------------------------------------------
U0_UCBR     .equ    52
U0_UCBRF    .equ    0x10
U0_UCBRS    .equ    0x49
U0_UCOS16   .equ    1

TX_PIN      .equ    BIT4            ; P1.4
RX_PIN      .equ    BIT5            ; P1.5

CR          .equ    0x0D
LF          .equ    0x0A
;------------------------------------------------------------------------------
; LED MAP
;------------------------------------------------------------------------------
RightG      .equ    BIT0            ; P1.0
RightY      .equ    BIT1            ; P1.1
RightR      .equ    BIT2            ; P1.2
LeftG       .equ    BIT3            ; P1.3

LeftY_P2    .equ    BIT0            ; P2.0
LeftR_P2    .equ    BIT1            ; P2.1

P1_LEDS     .equ    (RightG|RightY|RightR|LeftG)
P2_LEDS     .equ    (LeftY_P2|LeftR_P2)

;------------------------------------------------------------------------------
; Timer tick = 1 second using ACLK (32768Hz)
;------------------------------------------------------------------------------
TICK_CCR0   .equ    (32768-1)
;------------------------------------------------------------------------------
; FSM constants
;------------------------------------------------------------------------------
NUM_STATES  .equ    6
;------------------------------------------------------------------------------
; RAM
;------------------------------------------------------------------------------
            .data
TXptr       .word   0
TxBusy      .byte   0

TickFlag    .byte   0

State       .byte   0
OldState    .byte   0
StateTmr    .byte   0
;------------------------------------------------------------------------------
; STRINGS
;------------------------------------------------------------------------------
            .text
strBoot:    .byte "UART OK (16MHz/19200)",CR,LF,0
strEvent:   .byte "Event: TIMER_TICK",CR,LF,0
strOld:     .byte "Old state: ",0
strNew:     .byte "; New state: ",0
strCRLF:    .byte CR,LF,0

st0:        .byte "LeftR_RightG",0
st1:        .byte "LeftR_RightY",0
st2:        .byte "AllRed_1",0
st3:        .byte "LeftG_RightR",0
st4:        .byte "LeftY_RightR",0
st5:        .byte "AllRed_2",0
;------------------------------------------------------------------------------
; Tables: seconds per state
;------------------------------------------------------------------------------
Timer_Table:
            .byte   5,2,2,5,2,2

; LED tables split by Port
; P1 outputs: RightG RightY RightR LeftG
LedP1_Table:
            .byte   (RightG)                ; st0
            .byte   (RightY)                ; st1
            .byte   (RightR)                ; st2
            .byte   (LeftG|RightR)          ; st3
            .byte   (RightR)                ; st4
            .byte   (RightR)                ; st5
; P2 outputs: LeftY LeftR
LedP2_Table:
            .byte   (LeftR_P2)              ; st0
            .byte   (LeftR_P2)              ; st1
            .byte   (LeftR_P2)              ; st2
            .byte   (0)                     ; st3
            .byte   (LeftY_P2)              ; st4
            .byte   (LeftR_P2)              ; st5
;------------------------------------------------------------------------------
; RESET
;------------------------------------------------------------------------------
RESET       mov.w   #__STACK_END,SP
StopWDT     mov.w   #WDTPW|WDTHOLD,&WDTCTL
            bic.w   #LOCKLPM5,&PM5CTL0

;------------------------------------------------------------------------------
; CLOCK -> 16 MHz
;------------------------------------------------------------------------------
SetupCLK    bis.w   #SCG0,SR
            mov.w   #SELREF__REFOCLK,&CSCTL3
            clr     &CSCTL0
            bis.w   #DCORSEL_5,&CSCTL1
            mov.w   #FLLD__1+486,&CSCTL2
            nop
            nop
            nop
            bic.w   #SCG0,SR
FLL_wait    bit.w   #FLLUNLOCK0+FLLUNLOCK1,&CSCTL7
            jnz     FLL_wait
            bic.w   #DCOFFG,&CSCTL7
;------------------------------------------------------------------------------
; GPIO SETUP (LEDs)
;------------------------------------------------------------------------------
            ; P1 LED pins (DON'T TOUCH P1.4/P1.5)
            bis.b   #P1_LEDS, &P1DIR
            bic.b   #P1_LEDS, &P1OUT

            ; P2 LED pins
            bis.b   #P2_LEDS, &P2DIR
            bic.b   #P2_LEDS, &P2OUT
;------------------------------------------------------------------------------
; UART PIN SETUP
;------------------------------------------------------------------------------
            bis.b   #(TX_PIN|RX_PIN),&P1SEL0
            bic.b   #(TX_PIN|RX_PIN),&P1SEL1
            bic.b   #(TX_PIN|RX_PIN),&P1DIR
;------------------------------------------------------------------------------
; UART CONFIG @ 19200 baud rate
;------------------------------------------------------------------------------
            bis.w   #UCSWRST,&UCA0CTLW0
            bis.w   #UCSSEL__SMCLK,&UCA0CTLW0

            mov.w   #U0_UCBR,&UCA0BRW
            mov.b   #U0_UCBRS,&UCA0MCTLW_H
            mov.b   #(U0_UCBRF|U0_UCOS16),&UCA0MCTLW_L

            bic.w   #UCSWRST,&UCA0CTLW0
            bis.w   #UCRXIE,&UCA0IE

            mov.b   #0,&TxBusy
;------------------------------------------------------------------------------
; TIMERA0 SETUP
;------------------------------------------------------------------------------
            mov.w   #CCIE, &TA0CCTL0
            mov.w   #TICK_CCR0, &TA0CCR0
            mov.w   #(TASSEL__ACLK|MC__UP), &TA0CTL
;------------------------------------------------------------------------------
; FSM INIT
;------------------------------------------------------------------------------
            mov.b   #0, &State
            mov.b   Timer_Table, &StateTmr
            mov.b   #0, &TickFlag

            call    #ApplyLEDs
;------------------------------------------------------------------------------
; PRINT BOOT
;------------------------------------------------------------------------------
            mov.w   #strBoot,R15
            call    #StartTX
            nop
            bis.w   #GIE,SR
            nop
;------------------------------------------------------------------------------
; MAIN LOOP
;------------------------------------------------------------------------------
MainLoop
            ; wait for 1-second tick
            tst.b   &TickFlag
            jz      MainLoop
            mov.b   #0, &TickFlag

            ; Print event each tick
            mov.w   #strEvent, R15
            call    #StartTX

            ; Update timer/state
            dec.b   &StateTmr
            jnz     MainLoop

            ; transition
            mov.b   &State, &OldState
            inc.b   &State
            cmp.b   #NUM_STATES, &State
            jl      st_ok
            mov.b   #0, &State
st_ok
            ; reload state timer (FIXED: use register index)
            mov.b   &State, R14
            mov.b   Timer_Table(R14), &StateTmr

            ; update LEDs
            call    #ApplyLEDs

            ; print transition line
            call    #PrintTransition

            jmp     MainLoop

;------------------------------------------------------------------------------
; ApplyLEDs: outputs LEDs for current State using tables
;------------------------------------------------------------------------------
ApplyLEDs
            push    R14
            mov.b   &State, R14

            ; P1: clear LED bits then set pattern
            bic.b   #P1_LEDS, &P1OUT
            mov.b   LedP1_Table(R14), R15
            bis.b   R15, &P1OUT

            ; P2: clear LED bits then set pattern
            bic.b   #P2_LEDS, &P2OUT
            mov.b   LedP2_Table(R14), R15
            bis.b   R15, &P2OUT

            pop     R14
            ret

;------------------------------------------------------------------------------
; Print Transition: "Old state: XXXXXX; New state: YYYYYY"
;------------------------------------------------------------------------------
PrintTransition
            push    R15
            mov.w   #strOld,R15
            call    #StartTX
            mov.b   &OldState,R15
            call    #StateLabel
            call    #StartTX
            mov.w   #strNew,R15
            call    #StartTX
            mov.b   &State,R15
            call    #StateLabel
            call    #StartTX
            mov.w   #strCRLF,R15
            call    #StartTX
            pop     R15
            ret

StateLabel
            cmp.b   #0,R15
            jne     sl1
            mov.w   #st0,R15
            ret
sl1         cmp.b   #1,R15
            jne     sl2
            mov.w   #st1,R15
            ret
sl2         cmp.b   #2,R15
            jne     sl3
            mov.w   #st2,R15
            ret
sl3         cmp.b   #3,R15
            jne     sl4
            mov.w   #st3,R15
            ret
sl4         cmp.b   #4,R15
            jne     sl5
            mov.w   #st4,R15
            ret
sl5         mov.w   #st5,R15
            ret

;------------------------------------------------------------------------------
; StartTX (safe): waits until idle, primes first byte, TX ISR finishes
;------------------------------------------------------------------------------
StartTX
            push    R14
wait_idle   tst.b   &TxBusy
            jnz     wait_idle
            mov.b   #1,&TxBusy
            mov.w   R15,&TXptr
            mov.w   &TXptr,R14
            mov.b   @R14+,&UCA0TXBUF
            mov.w   R14,&TXptr
            bis.w   #UCTXIE,&UCA0IE
            pop     R14
            ret

;------------------------------------------------------------------------------
; Timer ISR: sets TickFlag every 1 second
;------------------------------------------------------------------------------
TIMER0_A0_ISR
            mov.b   #1, &TickFlag
            reti

;------------------------------------------------------------------------------
; UART ISR using UCA0IV (2=RXIFG, 4=TXIFG)
;------------------------------------------------------------------------------
UART_ISR
            push    R15
            mov.w   &UCA0IV, R15

            cmp.w   #2, R15
            jeq     UART_RX
            cmp.w   #4, R15
            jeq     UART_TX

            pop     R15
            reti

UART_RX
            mov.b   &UCA0RXBUF, R15
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

;------------------------------------------------------------------------------
; VECTORS STACK
;------------------------------------------------------------------------------
            .sect   ".reset"
            .short  RESET

            .sect   USCI_A0_VECTOR
            .short  UART_ISR

            .sect   TIMER0_A0_VECTOR
            .short  TIMER0_A0_ISR

            .sect   .stack
            .global __STACK_END