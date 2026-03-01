;------------------------------------------------------------------------------
; MSP430FR2433 - 3.	Output interfacing using an h-bridge
;a.	Obtain an h-bridge chip (SN754410-11) from your TA. Rework your circuit to
; enable bi-directional control of your DC motor. (See lecture 10, slide 34).
;IMPORTANT: Show your circuit to your instructor before you blow something up.
;b.	Now, amend your code from part 2 of this section (the PWM section) to enable 
;the button attached to P2.7 to serve as an input that allows you to change the 
;direction of your motor's rotation using the h-bridge chip (SN754410-11). That is,
; pressing P2.7 should toggle whatever pins you connected to the appropriate drivers
; on the H-bridge. Demonstrate your working system to your evaluator. 
;------------------------------------------------------------------------------

            .cdecls     C,LIST,"msp430FR2433.h"
            .def        RESET
            .text
;========================
; Constants Defination
;========================
MTBIT      .equ        BIT6                ; P1.1
BTNBIT     .equ        BIT3                ; P2.3 (button)
RBTNBIT    .equ        BIT7                ; P2.7 (button)
DIRA_BIT   .equ        BIT4                ; P1.4 -> 1A
DIRB_BIT   .equ        BIT5                ; P1.5 -> 2A


CCR0_VAL    .equ        331-1            ; period
DUTY_99     .equ        309
DUTY_50     .equ        100
DUTY_10     .equ        31
DUTY_0      .equ        0

;========================
; Initialization section
;========================
RESET:
            mov.w       #__STACK_END, SP              ;Set stack pointer
            mov.w       #WDTPW+WDTHOLD,&WDTCTL       ;Stop WDT
            bic.w       #LOCKLPM5,&PM5CTL0           ;Unlock GPIO Pins


; Motor direction pins as outputs + default forward
            bis.b       #DIRA_BIT + DIRB_BIT, &P1DIR
            bis.b       #DIRA_BIT, &P1OUT
            bic.b       #DIRB_BIT, &P1OUT

;--- P1.1 -> TA0.1 ---
            bis.b       #MTBIT, &P1DIR               ;Set Pin 1.1 direction as output
            bis.b       #MTBIT, &P1SEL1              ;Multiplex pin function select SEL1 = 1 P1.1 TA0.1
            bic.b       #MTBIT, &P1SEL0              ;Multiplex pin function select SEL0 = 0 P1.1 TA0.1
;--- P2.3 button ---
            bic.b       #BTNBIT, &P2DIR              ;Configure pin 2.3 as input
            bis.b       #BTNBIT, &P2REN              ;Enable input resistor on pin2.3 enly have high or low aviid noisy data
            bis.b       #BTNBIT, &P2OUT              ;Sets pull up internal resistor the pin start high
            bis.b       #BTNBIT, &P2IES              ;Interrupt Edge Select starts from high to low
            bic.b       #BTNBIT, &P2IFG              ;Clear any interrupt flag
            bis.b       #BTNBIT, &P2IE               ;Interrupt Enable

;--- P2.7 button ---
            bic.b       #RBTNBIT, &P2DIR             ;Configure pin 2.7 as input
            bis.b       #RBTNBIT, &P2REN             ;Enable input resistor
            bis.b       #RBTNBIT, &P2OUT             ;Pull-up
            bis.b       #RBTNBIT, &P2IES             ;Interrupt on high to low
            bic.b       #RBTNBIT, &P2IFG             ;Clear any interrupt flag
            bis.b       #RBTNBIT, &P2IE              ;Enable interrupt

;--- Timer0_A ---
            mov.w       #CCR0_VAL, &TA0CCR0          ;Set Timer0_A3 Capture/Compare 0 value =Period
            mov.w       #OUTMOD_7, &TA0CCTL1         ;Set Timer0_A3 Capture/Compare Control 1 = set/ reset
            mov.w       #DUTY_99, &TA0CCR1           ;Set Timer0_A3 Capture/Compare 1 = duty cycle

            mov.w       #TASSEL__SMCLK + ID__1 + MC__UP + TACLR, &TA0CTL ;Timer0_A3 Control source,input devider,counting mode selection

;--- state variable ---
            mov.b       #0, &DirState              ; starting direction (0=FWD)
            mov.b       #0, &DutyIdx               ; initial duty index

            bis.w       #GIE, SR                      ;enable global interrupts

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
            mov.b       &P2IFG, R14
            ; --- P2.3: cycle duty through table ---
            bit.b       #BTNBIT, R14
            jz          check_dir
            mov.b       &DutyIdx, R12
            inc.b       R12
            and.b       #3, R12                    ; 0..3
            mov.b       R12, &DutyIdx
            mov.w       #DutyTable, R13
            rla         R12                        ; word index = idx * 2
            add.w       R12, R13
            mov.w       0(R13), &TA0CCR1           ; apply new duty
            bic.b       #BTNBIT, &P2IFG            ; clear only P2.3 IFG


check_dir:
            ; --- P2.7: toggle direction ONLY ---
            bit.b       #RBTNBIT, R14
            jz          isr_done

            mov.b       &DirState, R12             ; move the current direction state to register 12
            xor.b       #1, R12                    ;bitwise exclusive or operation of 1 and the current direction state
            and.b       #1, R12                    ;bitwise AND operation
            mov.b       R12, &DirState             ;move contents of reg 12 to current direction state
            cmp.b       #0, R12
            jne         set_rev


set_fwd:
            bis.b       #DIRA_BIT, &P1OUT          ; A=1, B=0
            bic.b       #DIRB_BIT, &P1OUT
            jmp         clr_dir
set_rev:
            bic.b       #DIRA_BIT, &P1OUT          ; A=0, B=1
            bis.b       #DIRB_BIT, &P1OUT
clr_dir:
            bic.b       #RBTNBIT, &P2IFG           ; clear only P2.7 IFG

isr_done:
            reti

;========================
; Tables / BSS
;========================
DutyTable:
            .word       DUTY_99
            .word       DUTY_50
            .word       DUTY_10
            .word       DUTY_0

            .bss        DirState,1
            .bss        DutyIdx,1   ; store duty cycle index state

;========================
; Interrupt Vectors
;========================
            .global __STACK_END
            .sect   .stack
        
            .sect ".int41"  
            .short P2_ISR
        
            .sect   ".reset"
            .short  RESET