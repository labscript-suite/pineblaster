/*
#######################################################################
#                                                                     #
# pineblaster.pde                                                     #
#                                                                     #
# Copyright 2013, Christopher Billington                              #
#                                                                     #
# This file is used to flash a Digilent ChipKIT Max32 microcontroller #
# prototyping board to create a PineBlaster (see readme.txt and       #
# http://hardware.labscriptsuite.org).                                #
# This file is licensed under the Simplified BSD License.             #
# See the license.txt file for the full license.                      #
#                                                                     #
#######################################################################
*/

#include <plib.h>
//#include <SPI.h>
//#include <Ethernet.h>

//byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
//byte ip[] = { 192,168,1, 177 };
//Server server(8000);

const unsigned int max_instructions = 7450;
int autostart;
//volatile int reset_on_serial = 0;
unsigned int instructions[2*max_instructions + 2];
volatile unsigned int * resume_address = instructions;

char readstring[256] = "";

//void __attribute__((naked, at_vector(24), nomips16)) IntSer0Handler(void){
//  // This interrupt is called whenever serial communication arrives. We
//  // intercept it and decide whether to treat it as ordinary serial communication,
//  // or as an abort signal (for when the sequence is running). In the case of an abort signal,
//  // we can reset the CPU.
//  // Load in the address of reset_on_serial:
//  asm volatile ("la $k0, reset_on_serial\n\t");
//  // load in the value of reset_on_serial:
//  asm volatile ("lw $k0, 0($k0)\n\t");
//  // if it's zero, do the usual serial handler:
//  asm volatile ("beq $k0, $zero, IntSer0Handler\n\t");
//  // Otherwise, do a reset! (jump to the below function)
//  asm volatile ("j reset\n\t");
//}

void __attribute__((naked, nomips16)) Reset(void){
  // does a software reset of the CPU:
  // We have to do some kind of 'unlocking' sequence before we're allowed to reset:
  asm volatile ("reset: di\n\t");
  asm volatile ("la $k0, SYSKEY\n\t");
  asm volatile ("li $v0, 0xAA996655\n\t");
  asm volatile ("li $v1, 0x556699AA\n\t");
  // Have to write these two keys to SYSKEY in two back to back instructions to 'unlock' the system:
  asm volatile ("sw $v0, 0($k0)\n\t");
  asm volatile ("sw $v1, 0($k0)\n\t");
  // ok, now we can reset.
  asm volatile ("la $k0, RSWRST\n\t");
  // 'arm' the reset by writing a 1 to this register:
  asm volatile ("li $v0, 1\n\t");
  asm volatile ("sw $v0, 0($k0)\n\t");
  // execute the reset by reading the register back in (this is a funny bunch of hoops we're having to jump through):
  asm volatile ("lw $v0, 0($k0)");
  // Aight, now we wait for the end to come:
  asm volatile ("seeya: j seeya");
}

void start(){
  Serial.println("ok");
  // Any serial communication will now reset the CPU:
  //reset_on_serial = 1;
  int incomplete = 1;
  while (incomplete==1){
    run();
    autostart = 0;
    incomplete = (uint)resume_address != (uint)instructions;
  }
  // no longer reset on serial communication:
  //reset_on_serial = 0;
  // say that we're done!
  Serial.println("done");
}

void run(){
  // Enable our hardware trigger, if we're doing a hardware triggered start:
  if (autostart==0){
    attachInterrupt(0,0,RISING);
  }

  // 32 bit mode, no prescaler:
  T2CON = 0x0008;
  OC2CON = 0x0000; 
  OC2CON = 0x0023; 
  OC2R = 0;
  PR2 = 0;
  TMR2 = 0;
  TMR3 = 0;
  asm volatile ("nop\n\t");
  T2CONSET = 0x8000; 
  OC2CONSET = 0x8000; 
  
  // don't fill our branch delay slots with nops, thank you very much:
  asm volatile (".set noreorder\n\t":::"t0","t1","t2","t3","t4", "t5", "t6", "t7", "t8", "k0", "k1", "v0", "v1");
  // load the ram address of PR2 into register $t0:
  asm volatile ("la $t0, PR2\n\t");
  // load the ram address of OC2R into register $t1:
  asm volatile ("la $t1, OC2R\n\t");
  // load the address of the instruction array into register $t2:
  asm volatile ("la $t2, resume_address\n\t");
  asm volatile ("lw $t2, 0($t2)\n\t");
  // load the half-period time into register $t3:
  asm volatile ("lw $t3, 0($t2)\n\t"); 
  // load the delay time into register $t4:
  asm volatile ("lw $t4, 4($t2)\n\t"); 
  // load the the autostart flag into register $t5:
  asm volatile ("la $t5, autostart\n\t");
  asm volatile ("lw $t5, 0($t5)\n\t");
  // load the address of IPC0 into register $t6:
  asm volatile ("la $t6, IPC0\n\t");
  // load the address of OC2CON into register $t7:
  asm volatile ("la $t7, OC2CON\n\t");
  // a small constant used for getting to the right part of the waveform:
  asm volatile ("addi $t8, $zero, 2\n\t");
  
  // Prepare registers for hardware triggering (makes the interrupt code faster):
  asm volatile ("li $k0, 0x101001\n\t"); // the status we need to write to acknowledge that we're servicing the interrupt
  asm volatile ("li $k1, 0x100003\n\t"); // The status we need to write to say we've finished the interrupt
  asm volatile ("la $v0, IFS0\n\t"); // load the address of IFS0
  asm volatile ("li $v1, 0x10088880\n\t"); // the value of IFSO we need to indicate we've serviced the interrupt
  
  // if we're set to autostart, jump right in:
  asm volatile ("bne $t5, $zero, start\n\t");
  asm volatile ("nop\n\t");
  
  // otherwise, wait for it...
  asm volatile ("wait\n\t");
  
  // once the wait is complete, detach the interrupt so future triggers do not 
  // slow down the execution
  detachInterrupt(0); 
  // required nop because the asm for the detachInterrupt has a jump, which 
  // seems to execute the following asm instruction before jumping (much like
  // the branch instructions do. This nop ensures nothing critical starts 
  // before the detachment is finished
  asm volatile ("nop\n\t");
  
  // We need to get up to the right part of the waveform, we don't want the initial digital low.
  // We want to start with a digital high. So let's set the period to some small constant, and wait
  // until it is about to go high, switching the period to our first instruction at just the right moment:
  asm volatile ("start: sw $t8, 0($t0)\n\t"); 
  asm volatile ("sw $t8, 0($t1)\n\t");

  // update the period of the output:
  asm volatile ("top: sw $t3, 0($t0)\n\t"); 
  asm volatile ("sw $t3, 0($t1)\n\t");
  // wiat for the delay time:
  asm volatile ("wait_loop: bne $t4, $zero, wait_loop\n\t");
  asm volatile ("addi $t4, -1\n\t");
  // load the next half-period in:
  asm volatile ("lw $t3, 8($t2)\n\t");
  // increment our instruction pointer:
  asm volatile ("addi $t2, 8\n\t");
  // go to the top of the loop if it's not a stop instruction:
  asm volatile ("bne $t3, $zero, top\n\t");
  //load the the next delay time in:
  asm volatile ("lw $t4, 4($t2)\n\t"); 
  
  // We got a stop instruction (indicated by half_period==0). Disable output:
  asm volatile ("sw $zero, 0($t7)\n\t");
  
  // We might be stopping for good, or we might be resuming after a hardware trigger.
  // In case of the latter (indicated by delay_time != 0), 
  // save the next instruction pointer so we can resume from it:
  asm volatile ("la $t8, resume_address");
  asm volatile ("la $t7, instructions");
  asm volatile ("beq $t4, $zero, end\n\t");
  asm volatile ("sw $t7, 0($t8)\n\t");
  // increment our instruction pointer:
  asm volatile ("addi $t2, 8\n\t");
  asm volatile ("sw $t2, 0($t8)\n\t");
  asm volatile ("end:\n\t");
}




void readline(){
  byte i = 0;
  char c;
  byte crfound = 0;
  while (true){
    if (Serial.available() > 0){
      char c = Serial.read();
      if (c == '\r'){
        crfound = 1;
      }
      else if (c == '\n'){
        if (crfound == 1){
          readstring[i] = '\0';
          return;
        }
        else{
          readstring[i] = '\n';
          i++;
        }
      }
      else if (crfound){
        crfound = 0;
        readstring[i] = '\r';
        i++;
        readstring[i] = c;
        i++;
      }
      else{
        readstring[i] = c;
        i++;
      }
    }
  }
}

void setup(){
  // start the Ethernet connection and the server:
  //Ethernet.begin(mac, ip);
  //server.begin();
  Serial.begin(115200);
  int i = 0;
  for (i=0;i<86;i++){
    pinMode(i, OUTPUT);
    digitalWrite(i,LOW);
  }
  // Disable our hardware trigger until it is needed:
  IPC0 = 0;
}

void loop(){
  readline();
  if (strcmp(readstring, "hello") == 0){
    Serial.println("hello");
  }
  else if (strcmp(readstring, "hwstart") == 0){
    autostart = 0;
    start();
  }
  else if ((strcmp(readstring, "start") == 0) || (strcmp(readstring, "") == 0)){
    autostart = 1;
    start();
  }
  else if (strncmp(readstring, "set ", 4) == 0){
    unsigned int addr;
    unsigned int half_period;
    unsigned int reps;
    int parsed = sscanf(readstring,"%*s %u %u %u",&addr, &half_period, &reps);
    if (parsed < 3){
        Serial.println("invalid request");
    }
    else if (addr >= max_instructions){
      Serial.println("invalid address");
    }
    else if (half_period == 0){
      // This indicates either a stop or a wait instruction
      instructions[2*addr] = 0;
      if (reps == 0){
        // It's a stop instruction
        instructions[2*addr+1] = 0;
        Serial.println("ok");
      }
      else if (reps == 1){
        // It's a wait instruction:
        instructions[2*addr+1] = 1;
        Serial.println("ok");
      }
      else{
        Serial.println("invalid request");
      }
    }
    else if (half_period < 4){
      Serial.println("half-period too short");
    }
    else if (reps < 1){
      Serial.println("reps must be at least one");
    }
    else{
      instructions[2*addr] = half_period - 1;
      instructions[2*addr+1] = half_period*reps - 4;
      Serial.println("ok");
    }
  }
  else if (strcmp(readstring, "go high") == 0){
    digitalWrite(5,HIGH);
    Serial.println("ok");
  }
  else if (strcmp(readstring, "go low") == 0){
    digitalWrite(5,LOW);
    Serial.println("ok");
  }
  else if (strcmp(readstring, "reset") == 0){
    Serial.println("ok");
    asm volatile ("j reset\n\t");
  }
  
  else{
    Serial.println("invalid request");
  }
}


