;=================================================================================================
; 1.	Output interfacing using a transistor
;a.	Create a new assembly-only project in CCS using the MSP430. Create a code module that will 
;configure P1.1 as GPIO output, P2.3 as GPIO input with pull-up enabled. Design your code so that it 
;toggles the motor on or off each time the button attached to GPIO port P2.6 is pushed (not held). 
;Use good coding practice. You may "borrow" code from your previous labs.
;b.	Power off the circuit. Connect the ground of your microcontroller daughterboard to the ground of 
;your drive circuit. Connect the output pin P1.1 to the base resistor of your drive circuit. Keep the 
;12V motor power supply and the 3.3V microcontroller power supply SEPARATE. 
;
;IMPORTANT: Show this circuit to your instructor before you blow something up.

;c.	Power up the circuit, run your code, and debug the system. 
;d.	Demonstrate your working system to your evaluator. You must demonstrate the following:
;i.	Push and HOLD the button. The motor must change state only once. Nothing else must happen while 
;the button is being held. Then let go of the button – nothing must happen.
;ii.	Push the button once very quickly. The motor must change state only once.
;iii.	Push the button twice (about one second in between). The motor must change states each time 
;the button is pressed.

;==================================================================================================

            .cdecls     C,LIST,"msp430FR2433.h"

            .def        RESET
            .text                               ; Assemble into ROM
;============================================================
; Initialization Section (setup pins, timers, etc.)
;============================================================
RESET:
            mov.w       #__STACK_END, SP                 ; Set stack pointer
            mov.w       #WDTPW|WDTHOLD, &WDTCTL          ; Stop WDT
            bic.w       #LOCKLPM5, &PM5CTL0              ; Unlock GPIO Pins

            ; LED on P1.1 config
            bis.b       #BIT1, &P1DIR                    ; set P1.1 as output
            bic.b       #BIT0, &P1OUT                    ; start Motor OFF

            ; Button on P2.3 config
            bic.b       #BIT3, &P2DIR                    ; set P2.3 as input
            bis.b       #BIT3, &P2REN                    ; enable resistor
            bis.b       #BIT3, &P2OUT                    ; pull-up

          ; Interrupt on P2.3 
            bis.b       #BIT3, &P2IES                    ; falling edge 
            bic.b       #BIT3, &P2IFG                    ; clear pending flag
            bis.b       #BIT3, &P2IE                     ; enable P2.3 interrupt

            bis.w       #GIE, SR                         ; Global interrupt enable

;============================================================
; Main Loop (Background Program)
;============================================================

MainLoop:
            jmp         MainLoop


;============================================================
; Interrupt Service Routines (ISRs) 
;============================================================
PORT2_ISR:
         bit.b   #BIT3, &P2IES        ; check if we are on a falling edge
         jz      _release             ; If not on press jump to release

    ; Press detected (falling edge)
         xor.b   #BIT1, &P1OUT        ; Toggle Motor once
         bic.b   #BIT3, &P2IES        ; Next interrupt = rising edge
         bic.b   #BIT3, &P2IFG
         reti
_release:
    ; Release detected (if there is a rising edge)
         bis.b   #BIT3, &P2IES        ; Arm falling edge for next press
         bic.b   #BIT3, &P2IFG
    reti
;============================================================
; Interrupt Vectors
;============================================================

            .global     __STACK_END                      ; Not an interrupt vector but we need it
            .sect       .stack

            .sect       ".reset"                         ; MSP430 RESET Vector
            .short      RESET                            ; label to jump to when vector is called

            .sect       ".int41"                         ; Port 2 interrupt Vector 
            .short      PORT2_ISR                        ; label to jump to when vector is called