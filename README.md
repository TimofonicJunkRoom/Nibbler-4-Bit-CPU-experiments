# Nibbler-4-Bit-CPU-experiments
Sample code for the 4-Bit Nibbler DIY CPU

This program demonstrates some capabilities (and lack of others) of the the 4-Bit  Nibbler CPU board. At first it displays the author's name on the LCD display and then waits for any key input. 

Once a key is pressed it shows a 16-bit number in hexadecimal notation in the upper  left of the display and another 16-bit hex number that is added to it approx. once a second.
 
In the lower left, the lower 8 bits of the 16 bit number is displayed in  binary notation.
 
In addition, the LED on the board blinks with the same frequency.

The up- and down keys can be used to increase or decrease the number that is added  in each loop cycle. Program execution is interrupted while the left or right keys remain pressed.

Important concepts explored:

* Use of the 16 instructions of the CPU.

* How to live without a stack which makes it quite painful to jump to subroutines from different places. Instead of a stack, cascaded return jumps are used instead.

* How to live without an index register which makes it impossible to do repetitive tasks in a loop. There's no workaround for this other than not using loops and doing repetitive tasks by repeating code.
 
* Chaining 4-bit additions for 16-bit addition and subtraction (two's complement). A major complicating factor is that there
 is no 'add with carry' but only and 'add' instruction. Therefore the carry from one nibble to the next needs to be handled manually.
 
* How to convert a 4-bit hex value into an 8-bit ASCII value that can be printed on the LCD display.

* Exploring cycle times of single instructions with delay loops.

* Output to the LCD display (routines taken from Steve Chamberlain's original programs).

* Key input via the 4 input lines and the 'in' instruction.

* Hardware output to the LED that shares and output port with the LCD display control lines. Important: Sending text to the LCD display invalidates the state of the LED line as no XOR operation is used to leave the LED bit unaltered.

* Use of load and compare instructions followed by conditional jumps depending on the zero and carry flags.

