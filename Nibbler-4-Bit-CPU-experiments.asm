; ====================================================================================;
; x-martin-led-delay-and-add.asm
; 
; @version    1.0 2015-11-29
; @copyright  Copyright (c) 2015 Martin Sauter, martin.sauter@wirelessmoves.com
; @license    GNU General Public License v3
; @since      Since Release 1.0
;
; Version History
; ===============
;
; 1.0, 29. Nov. 2015, Initial version
;
; ################################################################################
; # This library is free software; you can redistribute it and/or
; # modify it under the terms of the GNU AFFERO GENERAL PUBLIC LICENSE
; # License as published by the Free Software Foundation; either
; # version 3 of the License, or any later version.
; #
; # This library is distributed in the hope that it will be useful,
; # but WITHOUT ANY WARRANTY; without even the implied warranty of
; # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; # GNU AFFERO GENERAL PUBLIC LICENSE for more details.
; #
; # You should have received a copy of the GNU Affero General Public
; # License along with this library.  If not, see <http://www.gnu.org/licenses/>.
; ################################################################################
;
; This program demonstrates some capabilities (and lack of others) of the the 4-Bit 
; Nibbler CPU board. At first it displays the author's name on the LCD display 
; and then waits for any key input. 
;
; Once a key is pressed it shows a 16-bit number in hexadecimal notation in the upper 
; left of the display and another 16-bit hex number that is added to it approx. once 
; a second.
; 
; In the lower left, the lower 8 bits of the 16 bit number is displayed in 
; binary notation.
; 
; In addition, the LED on the board blinks with the same frequency.
;
; The up- and down keys can be used to increase or decrease the number that is added 
; in each loop cycle. Program execution is interrupted while the left or right keys 
; remain pressed.
;
; Important concepts explored:
;
; * Use of the 16 instructions of the CPU.
;
; * How to live without a stack which makes it quite painful to jump to subroutines 
;   from different places. Instead of a stack, cascaded return jumps are used instead.
;
; * How to live without an index register which makes it impossible to do repetitive
;   tasks in a loop. There's no workaround for this other than not using loops
;   and doing repetitive tasks by repeating code.
; 
; * Chaining 4-bit additions for 16-bit addition and subtraction
;   (two's complement). A major complicating factor is that there
;   is no 'add with carry' but only and 'add' instruction. Therefore
;   the carry from one nibble to the next needs to be handled manually.
; 
; * How to convert a 4-bit hex value into an 8-bit ASCII value that
;   can be printed on the LCD display.
;
; * Exploring cycle times of single instructions with delay loops.
; 
; * Output to the LCD display (routines taken from Steve Chamberlain's
;   original programs).
; 
; * Key input via the 4 input lines and the 'in' instruction.
; 
; * Hardware output to the LED that shares and output port with the LCD display
;   control lines. Important: Sending text to the LCD display invalidates the 
;   state of the LED line as no XOR operation is used to leave the LED bit 
;   unaltered.
;
; * Use of load and compare instructions followed by conditional jumps depending
;   on the zero and carry flags.
;
;
; ====================================================================================

; =================================================
;
; Constants used in reusables subroutine section
;
; =================================================

; OUT ports
#define PORT_CONTROL $E ; 1110 - bit 0 is low
#define PORT_LCD $D     ; 1101 - bit 1 is low

; IN ports
#define PORT_BUTTONS $E ; 1110 - bit 0 is low

; Bit flags in LCDCONTROL port
#define LCD_REG_COMMAND $4
#define LCD_REG_DATA $6

; LCD commands
#define LCD_COMMAND_INTERFACE8 $3C  ; 8-bit interface, 2-line display, 5x10 font
#define LCD_COMMAND_INTERFACE4 $2C  ; 4-bit interface, 2-line display, 5x10 font
#define LCD_COMMAND_DISPLAY $0E     ; display on, cursor on, blinking cursor off
#define LCD_COMMAND_CLEAR $01       ; clear display, home cursor
#define LCD_COMMAND_CUSROR_POS_LINE_1 $80 ; OR the desired cursor position with $80 to create a cursor position command. Line 2 begins at pos 64
#define LCD_COMMAND_CURSOR_POS_LINE_2 $C0  
#define LCD_COMMAND_CURSOR_POS_GUESS $CC

; LCD timing constants
#define LCD_CLEAR_HOME_DELAY_US 1520
#define LCD_SINGLE_COMMAND_DELAY_US 37
#define CPU_CLOCKS_PER_US 2.4576

; Button bits
#define BUTTON_LEFT  $E
#define BUTTON_RIGHT $D
#define BUTTON_DOWN  $B
#define BUTTON_UP    $7

; ========================================================
; memory locations for reusable routines start at $100
; everything below is for program specific data
; ========================================================

#define LCD_BUFFER_INDEX $10A
#define LCD_CONTROL_STATE $10E
#define RETURN_ADDRESS $10F

#define LCD_DELAY_1 $110
#define LCD_DELAY_2 $111
#define LCD_BUFFER $120

#define RETURN_ADDRESS_KEY_INPUT_CHECK  $140
#define RETURN_ADDRESS_HANDLE_BUTTON    $141

; =========================================
;
; Program specific constants and variables
;
; =========================================

; memory locations for the 16-bit adder
#define a3 $000
#define a2 $001
#define a1 $002
#define a0 $003

#define b3 $010
#define b2 $011
#define b1 $012
#define b0 $013

#define carry $020
#define temp  $021

; memory locations for the delay function
#define ONE_SEC_DELAY_RETURN_ADDRESS $030
#define LOOP_COUNTER_1               $031
#define LOOP_COUNTER_2               $032
#define LOOP_COUNTER_3               $033
#define LOOP_COUNTER_4               $034

;memory locations for the key input function
#define NEW_BUTTON_STATE             $040
#define DEBOUNCE_COUNTER_0           $041
#define DEBOUNCE_COUNTER_1           $042
#define DEBOUNCE_COUNTER_2           $043


; ===============================================
;
; Main program loop
;
; ===============================================
 
; Initialize display, etc.

    jmp lcd_init

return_lcd_init:

    jmp print_martin

return_print_martin:

    jmp init_16_bit_variables

return_init_16_bit_variables:

    ; LED off
    lit #$4
    out #PORT_CONTROL

; Wait for key input to start the program
-   lit #$0
    st RETURN_ADDRESS_KEY_INPUT_CHECK
    jmp check_for_key_input

key_check_next_0:

    ld NEW_BUTTON_STATE
    cmpi #$F
    jz -

main-loop:

    ; add the content of b0-3 to a0-a3, 
    ; result is back in a0-3
    ;==================================

    ; remember where to return 
    lit #0
    st RETURN_ADDRESS
    jmp add-16-bit

add-return-0:

    jmp print_16_bit_counter

return_print_counter:

    jmp print_a0_a1_in_binary

return_print_a0_a1_in_binary:

    ; LED on
    ; =======
    lit #0
    out #PORT_CONTROL
   
    ; wait for a second
    lit #$1 ;return address for delay subroutine
    st ONE_SEC_DELAY_RETURN_ADDRESS
    jmp delay_and_check_key_input

return_delay_and_key_check_1:

    ; handle key press event
    lit #$0
    st RETURN_ADDRESS_HANDLE_BUTTON
    jmp handle_button_press

return_handle_button_0:

    ; LED off again
    ; ================
    lit #$4
    out #PORT_CONTROL


    ; wait for a second
    lit #$0 ;return address for delay subroutine
    st ONE_SEC_DELAY_RETURN_ADDRESS
    jmp delay_and_check_key_input

return_delay_and_key_check_0:

    ; handle key press event
    lit #$1
    st RETURN_ADDRESS_HANDLE_BUTTON
    jmp handle_button_press

return_handle_button_1:

    jmp main-loop


; ===============================================
;
; program specific subroutines
;
; ===============================================


; ===============================================
;
; Handle button presses:
;
; UP:   Increase b0-3 by 1
; DOWN: Decrease b0-3 by 1
;
; ===============================================

handle_button_press:

    ;check if a key was pressed in the delay function
    ld NEW_BUTTON_STATE
    cmpi #BUTTON_UP
    jnz +

    ; UP button was pressed, increase operand by 1
    ld b0
    addi #1
    st b0

+   cmpi #BUTTON_DOWN
    jnz +

    ; DOWN button was pressed, decrease operand by 1
    ld b0
    addi #-1
    st b0

    ; determine the return address
+   ld RETURN_ADDRESS_HANDLE_BUTTON
    jz return_handle_button_0
    cmpi #1
    jz return_handle_button_1

    ; unknown return address
    jmp halt


; ===============================================
;
; init the 16 bit variables:
; 
; set a0-3 to 0
; set b0-3 to 2 (increment)
; initialize temp and carry variables
;
; ===============================================


init_16_bit_variables:

    ; load two 16 bit integers into the pseudo 16-bit register a and b
    lit #$F
    st a3
    lit #$F
    st a2
    lit #$0
    st a1
    lit #$2
    st a0

    lit #$0
    st b3
    lit #$0
    st b2
    lit #$0
    st b1
    lit #$2
    st b0

    lit #$0
    st temp
    st carry
 
    jmp return_init_16_bit_variables

; =====================================
; 
; print 16 bit counter value
;
; value taken from a0-3
; 
; =====================================

print_16_bit_counter:

    ; prepare to send an LCD command
    lit #LCD_REG_COMMAND
    st LCD_CONTROL_STATE
    lit #<LCD_COMMAND_CLEAR
    st LCD_BUFFER+1
    lit #>LCD_COMMAND_CLEAR
    st LCD_BUFFER+0
    ; remember where to return
    lit #10
    st RETURN_ADDRESS
    ; data begins at buffer index 1
    lit #1
    jmp lcd_write_buffer

next10:
    ; remember where to return
    lit #4
    st RETURN_ADDRESS
    jmp lcd_long_delay

delaynext4:

    ; prepare to send LCD character data
    lit #LCD_REG_DATA
    st LCD_CONTROL_STATE

    ; =============
    ; print a
    ; =============

    ld a3
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld a3      ;the number is 0-9
    st LCD_BUFFER+6
    lit #3
    st LCD_BUFFER+7  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+6
    lit #4
    st LCD_BUFFER+7

++  ; next digit
    ; ==========

    ld a2
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld a2      ;the number is 0-9
    st LCD_BUFFER+4
    lit #3
    st LCD_BUFFER+5  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+4
    lit #4
    st LCD_BUFFER+5

++  ; next digit
    ; ==========

    ld a1
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld a1      ;the number is 0-9
    st LCD_BUFFER+2
    lit #3
    st LCD_BUFFER+3  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+2
    lit #4
    st LCD_BUFFER+3

++  ; next digit
    ; ==========

    ld a0
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld a0      ;the number is 0-9
    st LCD_BUFFER+0
    lit #3
    st LCD_BUFFER+1  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+0
    lit #4
    st LCD_BUFFER+1

++  ; remember where to return
    lit #11
    st RETURN_ADDRESS
    ; data begins at buffer index 7 (4 digits)
    lit #7
    jmp lcd_write_buffer

next11:
    
    ; ============================
    ; print space between a and b
    ; ============================

    lit #<' '
    st LCD_BUFFER+11
    lit #>' '
    st LCD_BUFFER+10
    lit #<' '
    st LCD_BUFFER+9
    lit #>' '
    st LCD_BUFFER+8
    lit #<'-'
    st LCD_BUFFER+7
    lit #>'-'
    st LCD_BUFFER+6
    lit #<'-'
    st LCD_BUFFER+5
    lit #>'-'
    st LCD_BUFFER+4
    lit #<' '
    st LCD_BUFFER+3
    lit #>' '
    st LCD_BUFFER+2
    lit #<' '
    st LCD_BUFFER+1
    lit #>' '
    st LCD_BUFFER+0

    lit #13
    st RETURN_ADDRESS
    ; data begins at buffer index 11
    lit #11
    jmp lcd_write_buffer

next13:

    ; =============
    ; print b
    ; =============

    ld b3
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld b3      ;the number is 0-9
    st LCD_BUFFER+6
    lit #3
    st LCD_BUFFER+7  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+6
    lit #4
    st LCD_BUFFER+7

++  ; next digit
    ; ==========

    ld b2
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld b2      ;the number is 0-9
    st LCD_BUFFER+4
    lit #3
    st LCD_BUFFER+5  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+4
    lit #4
    st LCD_BUFFER+5

++  ; next digit
    ; ==========

    ld b1
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld b1      ;the number is 0-9
    st LCD_BUFFER+2
    lit #3
    st LCD_BUFFER+3  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+2
    lit #4
    st LCD_BUFFER+3

++  ; next digit
    ; ==========

    ld b0
    addi #6   ;check if the number is 0-9 or A-F
    jc +

    ld b0      ;the number is 0-9
    st LCD_BUFFER+0
    lit #3
    st LCD_BUFFER+1  
    jmp ++

+   ; the number is A-F
    addi #1           ;chars A-F start at $41 (and not at $40)
    st LCD_BUFFER+0
    lit #4
    st LCD_BUFFER+1

++  ; remember where to return
    lit #12
    st RETURN_ADDRESS
    ; data begins at buffer index 7 (4 digits)
    lit #7
    jmp lcd_write_buffer

next12:

    jmp return_print_counter


; =============================================================================
; 
; Delay and Check for Key Input
;
; This function delays for around half a second before it returns and while
; doing so checks the input port of key presses. If a key press is detected
; it waits for the key to be released (thus blocking the program) and
; returns immediatley after the key has been released (abort the delay).
;
; Return values:
;
; The key that was pressed is contained in NEW_BUTTON_STATE. The variable
; is set to $F is no key was pressed
; 
; =============================================================================


delay_and_check_key_input:
    ; wait for a second
    lit #$F
    st LOOP_COUNTER_1
    st LOOP_COUNTER_2
    st LOOP_COUNTER_3
    lit #$8
    st LOOP_COUNTER_4

inner_loop:
  
    ; inner loop, 16 iterations + load instruction
    ; 16 * 2 cycles + 2 = 34 cycles @ 2.4576 MHz = 0.000013835 s
    lit #$F
-   addi #-1  ; nop
    jc -      ; carry will be clear when result goes negative

    ;16x nested loop time
    ;16x 8 cycles of code below = 0.000052083s
    ;total: (16*0.000013835) + 0.000052083 = 0.000273443s
    ld LOOP_COUNTER_1
    addi #-1
    st LOOP_COUNTER_1
    jc inner_loop

    ;16x nested loop time
    ;16x 8 cycles of code below = 0.000052083s
    ;total: (16*0.000273443) + 0.000052083 = 0.004427171s
    ld LOOP_COUNTER_2
    addi #-1
    st LOOP_COUNTER_2
    jc inner_loop

    ; check for key input
    lit #$1
    st RETURN_ADDRESS_KEY_INPUT_CHECK
    jmp check_for_key_input

key_check_next_1:
   
    ; abort delay loop if button was pressed
    ld NEW_BUTTON_STATE
    cmpi #$F
    jnz return_from_delay
    
    ;16x nested loop time
    ;16x 8 cycles of code below = 0.000052083s
    ;total: (16*0.004427171) + 0.000052083 = 0.070886819s
    ld LOOP_COUNTER_3
    addi #-1
    st LOOP_COUNTER_3
    jc inner_loop
  
    ;16x nested loop time
    ;8x 8 cycles of code below = 0.000052083s
    ;total: (8*0.070886819s) + 0.000052083 = 0.070886819s
    ld LOOP_COUNTER_4
    addi #-1
    st LOOP_COUNTER_4
    jc inner_loop

return_from_delay:

    ; determine the return address
    ld ONE_SEC_DELAY_RETURN_ADDRESS
    jz return_delay_and_key_check_0
    cmpi #1
    jz return_delay_and_key_check_1

    ; unknown return address
    jmp halt


; =====================================
; 
; print "Martin!!!"
; 
; =====================================


print_martin:
    ; prepare to send an LCD command
    lit #LCD_REG_COMMAND
    st LCD_CONTROL_STATE
    lit #<LCD_COMMAND_CLEAR
    st LCD_BUFFER+1
    lit #>LCD_COMMAND_CLEAR
    st LCD_BUFFER+0
    ; remember where to return
    lit #8
    st RETURN_ADDRESS
    ; data begins at buffer index 1
    lit #1
    jmp lcd_write_buffer

next8:
    ; remember where to return
    lit #3
    st RETURN_ADDRESS
    jmp lcd_long_delay

delaynext3:
    ; prepare to send LCD character data
    lit #LCD_REG_DATA
    st LCD_CONTROL_STATE

    lit #<'M'
    st LCD_BUFFER+15
    lit #>'M'
    st LCD_BUFFER+14
    lit #<'a'
    st LCD_BUFFER+13
    lit #>'a'
    st LCD_BUFFER+12
    lit #<'r'
    st LCD_BUFFER+11
    lit #>'r'
    st LCD_BUFFER+10
    lit #<'t'
    st LCD_BUFFER+9
    lit #>'t'
    st LCD_BUFFER+8
    lit #<'i'
    st LCD_BUFFER+7
    lit #>'i'
    st LCD_BUFFER+6
    lit #<'n'
    st LCD_BUFFER+5
    lit #>'n'
    st LCD_BUFFER+4
    lit #<'!'
    st LCD_BUFFER+3
    lit #>'!'
    st LCD_BUFFER+2
    lit #<' '
    st LCD_BUFFER+1
    lit #>' '
    st LCD_BUFFER+0
    ; remember where to return
    lit #9
    st RETURN_ADDRESS
    ; data begins at buffer index 15
    lit #15
    jmp lcd_write_buffer

next9:
    jmp return_print_martin


; ============================================================
; 
; Print a0 and a1 in binary in the second LCD line
; 
; ============================================================

print_a0_a1_in_binary:

    ; prepare to send an LCD command
    lit #LCD_REG_COMMAND
    st LCD_CONTROL_STATE
    lit #<LCD_COMMAND_CURSOR_POS_LINE_2
    st LCD_BUFFER+1
    lit #>LCD_COMMAND_CURSOR_POS_LINE_2
    st LCD_BUFFER+0
    ; remember where to return
    lit #0
    st RETURN_ADDRESS
    ; data begins at buffer index 1
    lit #1
    jmp lcd_write_buffer

next0:

    ; prepare to send LCD character data
    lit #LCD_REG_DATA
    st LCD_CONTROL_STATE

; === nibble 1

    ld a1
    _andi #8
    jz +
    lit #<'1'
    st LCD_BUFFER+15
    lit #>'1'
    st LCD_BUFFER+14
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+15
    lit #>'0'
    st LCD_BUFFER+14
++

    ld a1
    _andi #4
    jz +
    lit #<'1'
    st LCD_BUFFER+13
    lit #>'1'
    st LCD_BUFFER+12
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+13
    lit #>'0'
    st LCD_BUFFER+12
++

    ld a1
    _andi #2
    jz +
    lit #<'1'
    st LCD_BUFFER+11
    lit #>'1'
    st LCD_BUFFER+10
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+11
    lit #>'0'
    st LCD_BUFFER+10
++

    ld a1
    _andi #1
    jz +
    lit #<'1'
    st LCD_BUFFER+9
    lit #>'1'
    st LCD_BUFFER+8
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+9
    lit #>'0'
    st LCD_BUFFER+8
++


; === nibble 0

    ld a0
    _andi #8
    jz +
    lit #<'1'
    st LCD_BUFFER+7
    lit #>'1'
    st LCD_BUFFER+6
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+7
    lit #>'0'
    st LCD_BUFFER+6
++

    ld a0
    _andi #4
    jz +
    lit #<'1'
    st LCD_BUFFER+5
    lit #>'1'
    st LCD_BUFFER+4
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+5
    lit #>'0'
    st LCD_BUFFER+4
++

    ld a0
    _andi #2
    jz +
    lit #<'1'
    st LCD_BUFFER+3
    lit #>'1'
    st LCD_BUFFER+2
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+3
    lit #>'0'
    st LCD_BUFFER+2
++

    ld a0
    _andi #1
    jz +
    lit #<'1'
    st LCD_BUFFER+1
    lit #>'1'
    st LCD_BUFFER+0
    jmp ++
+   lit #<'0'
    st LCD_BUFFER+1
    lit #>'0'
    st LCD_BUFFER+0
++

    ; remember where to return
    lit #7
    st RETURN_ADDRESS
    ; data begins at buffer index 15
    lit #15
    jmp lcd_write_buffer
       
next7:

    jmp return_print_a0_a1_in_binary



; ============================================================    
; ================ reusable subroutines ======================
; ============================================================

; ============================================================
; 
; 16-bit integer addition: Add a0-3 and b0-3 and put 
; the result back into a0-3
; 
; ============================================================


add-16-bit:

   ; delete the carry bit, it could be set from the previous calculation
   lit #0
   st carry

; first nibble
; ==============
    ld a0
    addm b0           ; a0 + b0 => a0
    st a0
    jnc +            ; jump to next nibble add if there was no overflow, i.e. carry was set during this nibble add

; second nibble
; ===============

    ld a1            ; an overflow happened in the previous nibble, add it first

    addi #1  

    jnc ++           ; jump to the normal add if adding the overflow didn't cause another overflow

    st temp          ; there was an overflow, save the current result to a temp variable
    lit #1           ; remember there was an overflow
    st carry
    ld temp          ; get back the first operand from the temp variable and continue to the normal add part
    jmp ++

+   ld a1
++  addm b1
    st a1
    jnc +            ; if there was no overflow jump to the next nibble

    lit #1           ; remember there was an overflow at this point
    st carry

; third nibble
; ===============

+   ld carry
    jz +             ; if there wasn't a carry in the previous nibble jump to the calculation

    lit #0           ; there was a carry, delete the carry indication
    st carry

    ld a2            ; there was a carry, so add it
    addi #1

    jnc ++           ; jump to the normal add if adding the overflow didn't cause another overflow

    st temp          ; there was an overflow, save the current result to a temp variable
    lit #1           ; remember there was an overflow
    st carry
    ld temp          ; get back the first operand from the temp variable and continue to the normal add part
    jmp ++

+   ld a2
++  addm b2
    st a2 

    jnc +            ; if there was no overflow jump to the next nibble

    lit #1           ; remember there was an overflow at this point
    st carry


; fourth nibble
; ===============

+   ld carry
    jz +             ; if there wasn't a carry in the previous nibble jump to the calculation

    lit #0           ; there was a carry, delete the carry indication
    st carry

    ld a3            ; there was a carry, so add it
    addi #1

    jnc ++           ; jump to the normal add if adding the overflow didn't cause another overflow

    st temp          ; there was an overflow, save the current result to a temp variable
    lit #1           ; remember there was an overflow
    st carry
    ld temp          ; get back the first operand from the temp variable and continue to the normal add part
    jmp ++

+   ld a3
++  addm b3
    st a3

    jnc +            ; if there was no overflow there's not need to set the carry

    lit #1           ; remember there was an overflow at this point
    st carry

    ; determine the return address
+   ld RETURN_ADDRESS
    jz add-return-0
    cmpi #1
    jz add-return-0   ; just a filler, replace with a real address

    ; unknown return address
    jmp halt



; =====================================
; 
; LCD Initialization
; 
; =====================================


lcd_init:
    ; To initialize the LCD from an unknown state, we must first set it to 8-bit mode three times. Then it can be set to 4-bit mode.

    ; prepare to send an LCD command
    lit #LCD_REG_COMMAND
    st LCD_CONTROL_STATE
    ; remember where to return 
    lit #1
    st RETURN_ADDRESS
    ; zero more nibbles to read from the buffer
    lit #0
    st LCD_BUFFER_INDEX
    ; the command is INTERFACE8
    lit #<LCD_COMMAND_INTERFACE8
    jmp lcd_write_nibble

next1:
    ; remember where to return
    lit #0
    st RETURN_ADDRESS
    jmp lcd_long_delay

delaynext0:
    ; remember where to return
    lit #2
    st RETURN_ADDRESS
    ; zero more nibbles to read from the buffer
    lit #0
    st LCD_BUFFER_INDEX
    ; the command is INTERFACE8
    lit #<LCD_COMMAND_INTERFACE8
    jmp lcd_write_nibble

next2:
    ; remember where to return
    lit #1
    st RETURN_ADDRESS
    jmp lcd_long_delay

delaynext1:
    ; remember where to return
    lit #3
    st RETURN_ADDRESS
    ; zero more nibbles to read from the buffer
    lit #0
    st LCD_BUFFER_INDEX
    ; the command is INTERFACE8
    lit #<LCD_COMMAND_INTERFACE8
    jmp lcd_write_nibble

next3:
    ; remember where to return
    lit #4
    st RETURN_ADDRESS
    ; zero more nibbles to read from the buffer
    lit #0
    st LCD_BUFFER_INDEX
    ; the command is INTERFACE4
    lit #<LCD_COMMAND_INTERFACE4
    jmp lcd_write_nibble

    ; The LCD is now in 4-bit mode, and we can send byte-wide commands as a pair of nibble, high nibble first.

next4:
    ; prepare to send an LCD command
    lit #LCD_REG_COMMAND
    st LCD_CONTROL_STATE

    lit #<LCD_COMMAND_INTERFACE4
    st LCD_BUFFER+5
    lit #>LCD_COMMAND_INTERFACE4
    st LCD_BUFFER+4
    lit #<LCD_COMMAND_DISPLAY
    st LCD_BUFFER+3
    lit #>LCD_COMMAND_DISPLAY
    st LCD_BUFFER+2
    lit #<LCD_COMMAND_CLEAR
    st LCD_BUFFER+1
    lit #>LCD_COMMAND_CLEAR
    st LCD_BUFFER+0

    ; remember where to return
    lit #5
    st RETURN_ADDRESS
    ; data begins at buffer index 5
    lit #5
    jmp lcd_write_buffer

next5:
    ; remember where to return
    lit #2
    st RETURN_ADDRESS
    jmp lcd_long_delay

delaynext2:

    jmp return_lcd_init

; ============================================================
; 
; LCD output
; 
; ============================================================


; use LCD_BUFFER_INDEX to get the next nibble from LCD_BUFFER, and put it in LCD_NIBBLE

lcd_write_buffer:
    ; value for LCD_BUFFER_INDEX is in the accumulator
    st LCD_BUFFER_INDEX
    
    jnz +
    ld LCD_BUFFER
    jmp lcd_write_nibble

+   cmpi #1
    jnz +
    ld LCD_BUFFER+1
    jmp lcd_write_nibble

+   cmpi #2
    jnz +
    ld LCD_BUFFER+2
    jmp lcd_write_nibble

+   cmpi #3
    jnz +
    ld LCD_BUFFER+3
    jmp lcd_write_nibble

+   cmpi #4
    jnz +
    ld LCD_BUFFER+4
    jmp lcd_write_nibble

+   cmpi #5
    jnz +
    ld LCD_BUFFER+5
    jmp lcd_write_nibble

+   cmpi #6
    jnz +
    ld LCD_BUFFER+6
    jmp lcd_write_nibble

+   cmpi #7
    jnz +
    ld LCD_BUFFER+7
    jmp lcd_write_nibble

+   cmpi #8
    jnz +
    ld LCD_BUFFER+8
    jmp lcd_write_nibble

+   cmpi #9
    jnz +
    ld LCD_BUFFER+9
    jmp lcd_write_nibble

+   cmpi #10
    jnz +
    ld LCD_BUFFER+10
    jmp lcd_write_nibble

+   cmpi #11
    jnz +
    ld LCD_BUFFER+11
    jmp lcd_write_nibble

+   cmpi #12
    jnz +
    ld LCD_BUFFER+12
    jmp lcd_write_nibble

+   cmpi #13
    jnz +
    ld LCD_BUFFER+13
    jmp lcd_write_nibble

+   cmpi #14
    jnz +
    ld LCD_BUFFER+14
    jmp lcd_write_nibble

+   ld LCD_BUFFER+15

lcd_write_nibble:
    out #PORT_LCD
    ld LCD_CONTROL_STATE
    out #PORT_CONTROL ; setup RS
    _ori #1 ; set bit 1 (E)
    out #PORT_CONTROL
    _andi #$E ; clear bit 1 (E)
    out #PORT_CONTROL

    ; wait at least LCD_SINGLE_COMMAND_DELAY_US us for the LCD
    ; each loop iteration is 6 clocks
    ; initial count = round_up(LCD_SINGLE_COMMAND_DELAY_US * CPU_CLOCKS_PER_US / 6) - 1
    ; Initial count of 15 = 16 iterations = 96 clocks = 39 us @ 2.4576 MHz.
    lit #15
-   addi #0 ; NOP
    addi #-1
    jc -    ; carry will be clear when result goes negative

    ; decrement the buffer index
    ld LCD_BUFFER_INDEX
    addi #-1
    jc lcd_write_buffer

    ; determine the return address
    ld RETURN_ADDRESS
    jz next0
    cmpi #1
    jz next1
    cmpi #2
    jz next2
    cmpi #3
    jz next3
    cmpi #4
    jz next4
    cmpi #5
    jz next5
    cmpi #7
    jz next7
    cmpi #8
    jz next8
    cmpi #9
    jz next9
    cmpi #10
    jz next10
    cmpi #11
    jz next11
    cmpi #12
    jz next12
    cmpi #13
    jz next13

    ; unknown return address
    jmp halt


; ============================================================
; 
; LCD long delay
; 
; ============================================================


lcd_long_delay:
    ; wait at least LCD_CLEAR_HOME_DELAY_US us for the LCD
    ; each loop iteration is 6 clocks
    ; initial count = round_up(LCD_CLEAR_HOME_DELAY_US * CPU_CLOCKS_PER_US / 6) - 1
    ; Initial count of 656 = $290 hex = 657 iterations = 3942 clocks = 1604 us @ 2.4576 MHz
    lit #2
    st LCD_DELAY_2
    lit #9
    st LCD_DELAY_1
    lit #0
-   addi #0 ; NOP
    addi #-1
    jc -    ; carry will be clear when result goes negative
    ld LCD_DELAY_1
    addi #-1
    st LCD_DELAY_1
    jnc +
    lit #$F
    jmp -
+   ld LCD_DELAY_2
    addi #-1
    st LCD_DELAY_2
    jnc +
    lit #$F
    jmp -
+   ; end of delay loop

    ; determine the return address
    ld RETURN_ADDRESS
    jz delaynext0
    cmpi #1
    jz delaynext1
    cmpi #2
    jz delaynext2
    cmpi #3
    jz delaynext3
    cmpi #4
    jz delaynext4

    ; unknown return address
    jmp halt


    ; jump destination when something has gone wrong...
halt:
    jmp halt


; ============================================================
; 
; check_for_key_input
;
;  * returns immediately if no input key was pressed
;  * If a key is pressed return is delayed until the key is
;    released
; 
;  Return variable:
;
;    NEW_BUTTON_STATE = $F if no key was pressed
;    NEW_BUTTON_STATE = bit of key that was pressed set to 0
;
; Example of how to check if the UP button was pressed:
;
;    ld NEW_BUTTON_STATE
;    cmpi #BUTTON_UP
;    jnz some_place       ; jump to some place if the button
;                         ; was NOT pressed!
;
; Note: input bits of buttons that are not pressed are 
;       set to 1.
;
; ============================================================

check_for_key_input:

    ;initialize button state "not pressed"
    lit #$F
    st NEW_BUTTON_STATE

    in #PORT_BUTTONS
    cmpi #$F
    jz key_not_pressed

    ;store which button(s) were pressed
    st NEW_BUTTON_STATE

restart_debounce:

    lit #$F
    st DEBOUNCE_COUNTER_0
    st DEBOUNCE_COUNTER_1
    st DEBOUNCE_COUNTER_2

debounce:
    in #PORT_BUTTONS
    cmpi #$F
    jnz restart_debounce

    ld DEBOUNCE_COUNTER_0
    addi #-1
    st DEBOUNCE_COUNTER_0
    jc debounce
    ld DEBOUNCE_COUNTER_1
    addi #-1
    st DEBOUNCE_COUNTER_1
    jc debounce
    ld DEBOUNCE_COUNTER_2
    addi #-1
    st DEBOUNCE_COUNTER_2
    jc debounce

key_not_pressed:

    ; determine the return address
    ld RETURN_ADDRESS_KEY_INPUT_CHECK
    jz key_check_next_0
    cmpi #1
    jz key_check_next_1

    ; unknown return address
    jmp halt
