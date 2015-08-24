The PineBlaster is a microcontroller-based pseudoclock, built on the Digilent
chipKIT Max32™ Prototyping Platform. It provides for programmable pulse
sequences. It supports up to 15000 instructions, pulse periods between 50ns
and 56 seconds, and up to 2 billion repetitions of a pulse in one instruction.

The code can be loaded onto a chipkit
max32 via the arduino-like MPIDE. The device is then programmable over a
serial connection.


SETUP INSTRUCTIONS

Use MPIDE (available on the ChipKIT github) to compile and upload the code
(pineblaster.pde) to the ChipKIT MAX32.

Tested on MPIDE 0022 - 2011.12.14.

One modification is required: compiler optimisations must be disabled. This is
required so that the compiler doesn't produce unpredictable code, or multiple
code paths for the same bit of source code. So we do this to ensure our code
is deterministic.

To disable compiler optimisations, edit
<MPIDE_folder>/hardware/pic32/platforms.txt and replace all instances of '-O3'
with '-O0'.

Update: for MPIDE 0023, replace all instances of '-O2' and '-Os' with '-O0'.


USAGE INSTRUCTIONS

The Pineblaster talks serial over USB, at 115200bps. Newlines should be a
carriage return and line feed ( CRLF, '\r\n').

Pin 5 is the output, pin 3 is the hardware trigger. Both are 3.3v TTL

Commands that can be sent over serial are:


'hello'
Say hello to the pineblaster. It will say 'hello' back. Used to test
connectivity.


'hwstart'
Get the pineblaster ready for a hardware triggered run. The pineblaster
will say 'ok' when it's ready, and then will start the run when the
input on pin 3 goes high. There is a delay on the order of a few hundred
nanoseconds, this should be measured and accounted for if important. When
the program is complete, the pineblaster will say 'done'.


'start'
Starts a run immediately without waiting for a hardware trigger. This
can also be triggered by sending a CRLF by itself (useful for mashing
enter repeatedly when testing something). When the program is complete,
the pineblaster will say 'done'.

While a run is in progress with either of the above two commands,
any serial communication will be interpreted as an abort request. The
pineblaster will reset, forgetting its program, and will not be responsive
for several seconds.


'set i j k':
Program in an instruction. i, j and k are integers. i is the number of
the instruction, from 0 to 14999.  j and k are 32 bit integers for the
half-period and number of reps respectively for the pulses that the
pineblaster should produce for this instruction. The half period is
measured in CPU clock cycles (12.5ns with the built-in clock, may be
different if using an external clock) and must be at least 4. There
are some special values: if both half-period and reps are zero,
this indicates a STOP instruction.  All programs must end with such
a STOP instruction. A half period of 0 and rep number of 1 indicates
a WAIT instruction. The program will pause and resume upon a hardware
trigger. There is a minimum wait duration of approx 1us before the device
is ready for a trigger, and a delay upon resumption of the same duration
as when hardware triggering a run to begin. If these are important they
should be measured and accounted for.

Example program:

set 0 4 3
set 1 0 1
set 2 10 1
set 3 0 0

This program first pulses three times with a half-period of 4 CPU cycles (instruction 0). 
Then it waits for a hardware trigger (instruction 1).
It then pulses once with a half period of 10 CPU cycles (instruction 2).
It then stops (instruction 3).


'go high'
Sets the output to digital high. It will go low prior to a run if 'start' or 'hwstart' are called.


'go low'
Sets the output to digital low.


'reset'
Resets the device. It will be unresponsive for several seconds.







