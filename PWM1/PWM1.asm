;============================================================
; Timer-only blink on P1.1 using TA0.1 (CCR1) OUTMODE
; ON=3s, OFF=1s  -> Period=4s, Duty=75%
; ACLK=32768 Hz, divide by 2 => 16384 Hz
; CCR0=65535 (4s), CCR1=49152 (3s)
;============================================================

;============================================================
; Directives Section (define any constants with .equ)
;============================================================
            .cdecls     C,LIST,"msp430FR2433.h"
            .def        RESET
            .text                               ; Assemble into ROM


;============================================================
; Initialization Section (setup pins, timers, etc.)
;============================================================
RESET:
            mov.w       #__STACK_END, SP                ; Set stack pointer
            mov.w       #WDTPW|WDTHOLD, &WDTCTL         ; Stop WDT
            bic.w       #LOCKLPM5, &PM5CTL0             ; Unlock GPIO Pins

;------------------------------------------------------------
; P1.1 must be driven by timer output TA0.1 (not GPIO software)
; Select TA0.1 function on P1.1 (pin mux)
;------------------------------------------------------------
            bis.b       #BIT1, &P1SEL0                  ; P1.1 -> TA0.1
            bic.b       #BIT1, &P1SEL1
            bis.b       #BIT1, &P1DIR                   ; output (safe)

;------------------------------------------------------------
; Timer_A0 configuration (hardware generates the waveform)
; OUTMOD_7 Reset/Set: 
;   SET at TAR=0, RESET at TAR=CCR1
; Add OUT so it starts ON immediately (more visible)
;------------------------------------------------------------
            mov.w       #OUTMOD_7|OUT, &TA0CCTL        ; Reset/Set, start HIGH

            bis.w       #TACLR, &TA0CTL
            bis.w       #TASSEL_1|ID_1|MC_1, &TA0CTL
            
            mov.w       #65535,   &TA0CCR0              ; 4 seconds period
            mov.w       #49152,   &TA0CCR1              ; 3 seconds ON
 ;           bis.w       #CCIE,    &TA0CCTL0

;============================================================
; Main Loop (Background Program) NOT ALLOWED TO CHANGE
;============================================================
MainLoop:
            nop
            jmp         MainLoop


;============================================================
; Interrupt Service Routines (ISRs) (Foreground Program(s))
; NOT ALLOWED TO CHANGE (not used)
;============================================================


;============================================================
; Interrupt Vectors
;============================================================
            .global     __STACK_END                     ; Not an interrupt vector but we need it
            .sect       .stack

            .sect       ".reset"                        ; MSP430 RESET Vector (use straight quotes)
            .short      RESET                           ; label to jump to when vector is called
            .end