;------------------------------------------------------------------------------
;2.	Pulse Width Modulation (PWM) of motor speed
;a.	Now, modify your code so that the speed of a DC motor is controlled using PWM 
;on TA1 (Pin P1.1). Demonstrate your ability to control the speed of the motor by 
;stepping through the speed sequence {stationary, slow, medium, fast} using your 
;button attached to P2.3. Use good coding practice. What duty cycle values did you 
;choose for the four speeds? Demonstrate your working system to your evaluator. 
;------------------------------------------------------------------------------

            .cdecls     C,LIST,"msp430fr2433.h"
            .def        RESET
            .text
;========================
; Constants
;========================
LEDBIT      .equ        BIT1                ; P1.1 (TA0.1)
BTNBIT      .equ        BIT3                ; P2.3 (button, active-low)

; Timer base: 
CCR0_VAL    .equ        331            ; 

; Duty (counts relative to )
DUTY_99     .equ        329              ; Fast
DUTY_50     .equ        100              ; Medium
DUTY_10     .equ        30               ; Slow
DUTY_0      .equ        0                ; Stationary

;========================
; RAM (BSS)
;========================
            .bss        DutyIdx,1           ; duty cycle index: 0..3

;========================
; Reset / Init
;========================
RESET:
            mov.w       #__STACK_END, SP                ; set stack
            mov.w       #WDTPW|WDTHOLD, &WDTCTL         ; stop watchdog
            bic.w       #LOCKLPM5, &PM5CTL0             ; unlock GPIO 

; FR2433 mapping: P1.1 TA0.1 is PRIMARY: P1SEL1=1, P1SEL0=0
            bis.b       #LEDBIT, &P1DIR                 ; output (safe)
            bis.b       #LEDBIT, &P1SEL1                ; 
            bic.b       #LEDBIT, &P1SEL0                ; 

;--- P2.3 button (input w/ pull-up, interrupt on H->L) ---
            bic.b       #BTNBIT, &P2DIR                 ; input
            bis.b       #BTNBIT, &P2REN                 ; port enable resistor
            bis.b       #BTNBIT, &P2OUT                 ; pull-up
            bis.b       #BTNBIT, &P2IES                 ; Port 2 Interrupt Edge Select High
            bic.b       #BTNBIT, &P2IFG                 ; Clear pending Port 2 Interrupt Flag 
            bis.b       #BTNBIT, &P2IE                  ; Port 2 Interrupt Enable

;--- Timer_A0 PWM on CCR1 (OUTMOD_7 Reset/Set) ---
            mov.w       #CCR0_VAL, &TA0CCR0             ; Set Timer0_A3 Capture/Compare 0 value =Period
            mov.w       #OUTMOD_7, &TA0CCTL1            ; Set Timer0_A3 Capture/Compare Control 1 = outmode
            mov.w       #DUTY_99, &TA0CCR1              ; Set Timer0_A3 Capture/Compare 1 = duty cycle

; TA0 clock: SMCLK, divider /8; Up mode; clear TAR
            mov.w       #TASSEL__SMCLK + ID__8 + MC__UP + TACLR, &TA0CTL ;Timer0_A3 Control source,input devider,counting mode selection

;--- State variable ---
            mov.b       #0, &DutyIdx                    ; index into DutyTable

; Enable global interrupts
            bis.w       #GIE, SR                         ;enable global interrupts
;========================
; Main Loop (idle)
;========================
MainLoop:
            nop
            jmp         MainLoop

;========================
; Port 2 ISR
;========================
P2_ISR:
    push.w  R12
    push.w  R13

    mov.w   &P2IV, R12          ; clears highest P2 IFG
    cmp.w   #0x0008, R12        ; was it P2.3 Interrupt ?
    jne     done                ;if the Interrupt is not from P2.3 jump to done

    mov.b   &DutyIdx, R12       ;else move the current duty index to register 13
    inc.b   R12                 ;increment the current duty index by 1
    and.b   #3, R12             ; wrap 0..3
    mov.b   R12, &DutyIdx       ;make the value in register 13 the new duty index

    rla     R12                 ; 
    mov.w   #DutyTable, R13
    add.w   R12, R13
    mov.w   0(R13), R12
    mov.w   R12, &TA0CCR1

done:
    pop.w   R13
    pop.w   R12
    reti
;========================
; Tables
;========================
DutyTable:
            .word       DUTY_99
            .word       DUTY_50
            .word       DUTY_10
            .word       DUTY_0
;========================
; Interrupt Vectors / Stack
;========================
            .global     __STACK_END
            .sect       .stack

            .sect       PORT2_VECTOR
            .short      P2_ISR

            .sect       ".reset"
            .short      RESET