;------------------------------------------------------------------------------
; MSP430FR2433 - Problem 2 
;------------------------------------------------------------------------------

            .cdecls     C,LIST,"msp430FR2433.h"
            .def        RESET
            .text
;========================
; Constants Definition
;========================
LEDBIT      .equ        BIT1                ; P1.1
BTN         .equ        BIT3                ; P2.3 (button)
 
; Timer base: SMCLK/64 = 1 000 000/64 = 15625 Hz
CCR0_VAL    .equ        331                 ; period counts
DUTY_75     .equ        329                 ; ~75% example (must be <= CCR0)

;========================
; Initialization section
;========================
RESET:
            mov.w       #__STACK_END, SP              ; Set stack pointer
            mov.w       #WDTPW+WDTHOLD, &WDTCTL      ; Stop WDT
            bic.w       #LOCKLPM5, &PM5CTL0          ; Unlock GPIO Pins

; --- P1.1 -> Timer output (route TAx.1 to P1.1 via PRIMARY function) ---
            bis.b       #LEDBIT, &P1DIR              ; P1.1 output capable
            bis.b       #LEDBIT, &P1SEL0             ; SEL0 = 1
            bic.b       #LEDBIT, &P1SEL1             ; SEL1 = 0

; --- Configure P2.3 button (pull-up, falling-edge interrupt) ---
            bic.b       #BTN, &P2DIR
            bis.b       #BTN, &P2REN
            bis.b       #BTN, &P2OUT                 ; pull-up
            bis.b       #BTN, &P2IES                 ; falling edge first (press)
            bic.b       #BTN, &P2IFG
            bis.b       #BTN, &P2IE

; --- Timer0_A PWM on CCR1 (Reset/Set) ---
            mov.w       #CCR0_VAL, &TA0CCR0          ; Period
            mov.w       #OUTMOD_7, &TA0CCTL1         ; PWM mode: Reset/Set
            mov.w       #DUTY_75,  &TA0CCR1          ; Duty cycle (example)

            mov.w       #TASSEL__SMCLK + ID__8 + MC__UP + TACLR, &TA0CTL
            mov.w       #TAIDEX_7, &TA0EX0           ; /8 x /8 => /64 total
     ;--- START FAST first time ---
            mov.w       #DUTY_FAST, &TA0CCR1
            mov.b       #3, &DutyIdx          ; index 3 = FAST (matches table below)

     
;========================
; Main Loop
;========================
MainLoop:
            nop
            jmp         MainLoop

;========================
; Port 2 ISR
;========================
P2_ISR:
            ; Are we on falling (press) or rising (release)?
            bit.b       #BTN, &P2IES
            jz          on_release

on_press:
            ; TODO: advance duty table / do your action here

            bic.b       #BTN, &P2IFG     ; clear IFG
            bic.b       #BTN, &P2IES     ; next edge = rising (release)
            reti

on_release:
            bic.b       #BTN, &P2IFG     ; clear IFG
            bis.b       #BTN, &P2IES     ; arm falling edge (press)
            reti

;========================
; Interrupt Vectors 
;========================
            .global     __STACK_END
            .sect       .stack

            .sect       ".reset"         ; MSP430 RESET Vector
            .short      RESET

            .sect       PORT2_VECTOR     ; Port 2 vector (P2.3 ISR)
            .short      P2_ISR