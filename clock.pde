#include <plib.h>
//#include <SPI.h>
//#include <Ethernet.h>

//byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
//byte ip[] = { 192,168,1, 177 };
//Server server(8000);

const unsigned int max_instructions = 200;
int autostart;
volatile int reset_on_serial = 0;
unsigned int instructions[max_instructions];

void __attribute__((naked, at_vector(3), nomips16)) ExtInt0Handler(void){
  // This interrupt is called when a hardware trigger goes high to start the run.
  // set Status to acknowledge that we're starting the interrupt handler:
  asm volatile ("mtc0 $k0, $12\n\t");
  // set IPC0 so as to disable this interrupt from occuring again:
  asm volatile ("sw $zero, 0($t6)\n\t");
  // Write to IFSO to indicate that the interrupt has been handled:
  asm volatile ("sw $v1, 0($v0)\n\t");
  // set Status to indicate the end of the interrupt handler:
  asm volatile ("mtc0 $k1, $12\n\t");
  // return:
  asm volatile ("eret\n\t");
}

void __attribute__((naked, at_vector(24), nomips16)) IntSer0Handler(void){
  // This interrupt is called whenever serial communication arrives. We
  // intercept it and decide whether to treat it as ordinary serial communication,
  // or as an abort signal (for when the sequence is running). In the case of an abort signal,
  // we can reset the CPU.
  // Load in the address of reset_on_serial:
  asm volatile ("la $k0, reset_on_serial\n\t");
  // load in the value of reset_on_serial:
  asm volatile ("lw $k0, 0($k0)\n\t");
  // if it's zero, do the usual serial handler:
  asm volatile ("beq $k0, $zero, IntSer0Handler\n\t");
  // Otherwise, do a reset! (jump to the below function)
  asm volatile ("j reset\n\t");
}

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
  // set the values required by the first iteration of the loop in run():
  Serial.println("ok");
  
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
  
  // Any serial communication will now reset the CPU:
  reset_on_serial = 1;
  
  // don't fill our branch delay slots with nops, thank you very much:
  asm volatile (".set noreorder\n\t":::"t0","t1","t2","t3","t4", "t5", "t6", "t7", "t8", "k0", "k1", "v0", "v1");
  // load the ram address of PR2 into register $t0:
  asm volatile ("la $t0, PR2\n\t");
  // load the ram address of OC2R into register $t1:
  asm volatile ("la $t1, OC2R\n\t");
  // load the address of the instruction array into register $t2:
  asm volatile ("la $t2, instructions\n\t");
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
  
  // if we're set to autostart, jump right in:
  asm volatile ("bne $t5, $zero, top\n\t");
  asm volatile ("nop\n\t");
  
  // otherwise, prepare for a hardware triggered interrupt:
  asm volatile ("li $k0, 0x101001\n\t"); // the status we need to write to acknowledge that we're servicing the interrupt
  asm volatile ("li $k1, 0x100003\n\t"); // The status we need to write to say we've finished the interrupt
  asm volatile ("la $v0, IFS0\n\t"); // load the address of IFS0
  asm volatile ("li $v1, 0x10088880\n\t"); // the value of IFSO we need to indicate we've serviced the interrupt
  // wait for it...
  asm volatile ("wait\n\t");
  
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
  
  // turn everything off:
  OC2CON = 0;
   
  // no longer reset on serial communication:
  reset_on_serial = 0;
  
  // say that we're done!
  Serial.println("done");
}




String readline(){
  String readstring = "";
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
          return readstring;
        }
        else{
          readstring += '\n';
        }
      }
      else if (crfound){
        crfound = 0;
        readstring += '\r';
        readstring += c;
      }
      else{
        readstring += c;
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
  String readstring = readline();
  if (readstring == "hello"){
    Serial.println("hello");
  }
  else if (readstring == "hwstart"){
    autostart = 0;
    start();
  }
  else if ((readstring == "start") || (readstring == "")){
    autostart = 1;
    start();
  }
  else if (readstring.startsWith("set ")){
    int firstspace = readstring.indexOf(' ');;
    int secondspace = readstring.indexOf(' ', firstspace+1);
    int thirdspace = readstring.indexOf(' ', secondspace+1);
    if (secondspace == -1 || thirdspace == -1){
      Serial.println("invalid request");
      return;
    }
    unsigned int addr = readstring.substring(firstspace+1, secondspace).toInt();
    unsigned int delay_time = readstring.substring(secondspace+1, thirdspace).toInt();
    unsigned int reps = readstring.substring(thirdspace+1).toInt();
    if (addr >= max_instructions){
      Serial.println("invalid address");
    }
    else if (delay_time < 4){
      Serial.println("period too short");
    }
    else{
      instructions[2*addr] = delay_time - 1;
      instructions[2*addr+1] = delay_time*reps - 4;
      Serial.println("ok");
    }
  }
  else if (readstring == "go high"){
    digitalWrite(5,HIGH);
    Serial.println("ok");
  }
  else if (readstring == "go low"){
    digitalWrite(5,LOW);
    Serial.println("ok");
  }
  else if (readstring == "reset"){
    Serial.println("ok");
    asm volatile ("j reset\n\t");
  }
  
  else{
    Serial.println("invalid request");
  }
}

