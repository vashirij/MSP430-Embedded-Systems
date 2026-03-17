/* CLI.c: Implement a command line interface */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#define MAX_COMMAND_LEN     (18)
#define MAX_PARAMETER_LEN   (7)
#define COMMAND_TABLE_SIZE  (37)
#define STRING_BUFFER_SIZE  (64)

//Takes input character and outputs uppercase version 
#define TO_UPPER(x) ( ((x >= 'a') && (x <= 'z')) ? ((x) - ('a' - 'A')) : (x) )

extern void     SendString2RS232 (void*);

// extern int SampleData;

extern volatile char PrintSemaphore;  /* from UART.asm */
extern volatile char PrintSensor;  /* a flag to indicate whether to print the sensor values*/

//unsigned int MEASURE_RATE = 25; // 25 ms for sampling rate of 40 Hz
volatile char StringBuffer[STRING_BUFFER_SIZE]={0x00};

/* declare function prototypes */
void commandHelp (void);
void commandTare(void);
void commandCheckSensor (void);
void commandStreamSensor (void);
void commandStopStreamSensor (void);

void SerialPrintHeaderInfo(void);
void ProcessCommand(void);
int BuildCommand(char nextChar);

/*These variables are used in the functions that construct and process
   commands received through the serial port */
char CommandBuffer[MAX_COMMAND_LEN + 1];
char Param1Buffer[MAX_PARAMETER_LEN + 1];
char Param2Buffer[MAX_PARAMETER_LEN + 1];
float Param1Value;
float Param2Value;


int StreamDataFlag;
int DoTareFlag;
int tareVal = 0;

float measuredForceGrams = 0;



/*******************************************************************
/=  Define the form of functions, then declare our table of commands.
******************************************************************/

typedef struct {
  char const  *name;
  void        (*function)(void);
} slave_command;

slave_command CommandTable[COMMAND_TABLE_SIZE] = {

  {"H",             commandHelp, },
  {"Help",          commandHelp, },

  {"C",             commandCheckSensor, },
  {"CheckSensor",   commandCheckSensor, },

  {"T",             commandTare, },
  {"Tare",          commandTare, },
    
  {"S",             commandStreamSensor, },
  {"StreamSensor",  commandStreamSensor, },

  {"X",             commandStopStreamSensor, },
  {"StopStream",    commandStopStreamSensor, },

  {NULL,        NULL }
};



/*******************************************************************
   Function:    BuildCommand
   Description: Put received characters into the command buffer or
                the parameter buffer.  Once a complete command is
                received return true.
   Notes:
   Returns:     True if the command is complete, otherwise false.
 ******************************************************************/
int BuildCommand(char nextChar) {
  static uint8_t CmdIndx = 0; //index for command buffer
  static uint8_t Parm1Indx = 0; //index for parameter buffer
  static uint8_t Parm2Indx = 0; //index for parameter buffer
  enum { COMMAND, PARAM1, PARAM2 };
  static uint8_t state = COMMAND;
  
  if ((nextChar == '\n') || (nextChar == ' ') || (nextChar == '\t')
      || (nextChar == '\r') || (nextChar <= 32))
    /*Don't store any new line characters or spaces */
  {
    return false;
  }

  if (nextChar == ',') {
    if (state == COMMAND) {
      state = PARAM1;
      return false;
    }
    else if (state == PARAM1) {
      state = PARAM2;
      return false;
    }
  }

  if (nextChar == ';') { //Completed command received
    CommandBuffer[CmdIndx] = '\0';
    /*Replace final 'return' character with a NULL character to
      help with processing the command */
    Param1Buffer[Parm1Indx] = '\0';
    Param2Buffer[Parm2Indx] = '\0';
    CmdIndx = 0; Parm1Indx = 0; Parm2Indx = 0; //Reset indices
    state = COMMAND;
    return true;
  }

  if (state == COMMAND) {
    CommandBuffer[CmdIndx] = TO_UPPER(nextChar);
    /*Convert the incoming character to upper case, matches
      commands in the command table.  Then store in buffer. */
    CmdIndx++;
    if (CmdIndx > MAX_COMMAND_LEN) {
      CmdIndx = 0;
      return true;
      /* If command is too long reset the index and process the
        current command buffer.  Most likely will return
        'Command not found', but cleans the slate nevertheless. */
    }
  }

  if (state == PARAM1) {
    Param1Buffer[Parm1Indx] = nextChar;
    Parm1Indx++;
    if (Parm1Indx > MAX_PARAMETER_LEN) {
      Parm1Indx = 0;
      return false;
    }
  }

  if (state == PARAM2) {
    Param2Buffer[Parm2Indx] = nextChar;
    Parm2Indx++;
    if (Parm2Indx > MAX_PARAMETER_LEN) {
      Parm2Indx = 0;
      return false;
    }
  }

  return false;
}



/*******************************************************************
   Function:    ProcessCommand
   Description: Look up the command in the command table. If the
                command is found, call the command's function. If
                the command is not found, output an error message.
   Notes:
   Returns:     None
 ******************************************************************/
void ProcessCommand(void) {
  int CommandFound = false;
  int idx;

  /* Convert the parameter to an integer value.  If the parameter is
    empty, ParamValue becomes 0. */
  Param1Value = atof(Param1Buffer);
  Param2Value = atof(Param2Buffer);
//  Param1Value = strtol(Param1Buffer, NULL, 0);
//  Param2Value = strtol(Param2Buffer, NULL, 0);

  for (idx = 0; CommandTable[idx].name != NULL; idx++) {
    /* Search for the command in the command table until it is found
        or the end of the table is reached. If command is found
        then break the loop
    */
    if (strcmp(CommandTable[idx].name, CommandBuffer) == 0) {
      CommandFound = true;
      break;
    }

  }

  if (CommandFound == true) {
    /*if the command was found call the command function. Otherwise
       output an error message. */
    (*CommandTable[idx].function)();
  }
  else {
    while(PrintSemaphore) {;}
    sprintf(StringBuffer, "\nCommand not found.\r\n");
    SendString2RS232(&StringBuffer);
    while(PrintSemaphore) {;}
  }
}

/******************************************************************
   Function:     commandHelp
   Description:  Help command function.
   Notes:
   Returns:      None
 *****************************************************************/

void commandHelp(void) {
  unsigned int idx;
  while(PrintSemaphore) {;}
  sprintf(StringBuffer, "\n\r---------------------\r\n");
  SendString2RS232(&StringBuffer);
  while(PrintSemaphore) {;}
  sprintf(StringBuffer, "Available commands:\r\n");
  SendString2RS232(&StringBuffer);
  for (idx = 0; CommandTable[idx].name != NULL; idx++) {
    /*Loop through each command in the table and print the command
       name to the serial port. */
    while(PrintSemaphore) {;}
    sprintf(StringBuffer, "  %s: %s\r\n",CommandTable[idx].name,CommandTable[idx+1].name);
    SendString2RS232(&StringBuffer);
    idx++;
  }
  while(PrintSemaphore) {;}
  sprintf(StringBuffer, "---------------------\r\n");
  SendString2RS232(&StringBuffer);  
  while(PrintSemaphore) {;}
}


/******************************************************************
   Function:     SerialPrintHeaderInfo
   Description:  Prints a useful table of commands to the serial port
   Notes:
   Returns:      None
 *****************************************************************/

void SerialPrintHeaderInfo() {
  int LoopCounter;
  for (LoopCounter = 0; LoopCounter < 3; LoopCounter++)
  {
    while(PrintSemaphore) {;}
    sprintf(StringBuffer, "\r\n");
    SendString2RS232(&StringBuffer);
  }
  
    while(PrintSemaphore) {;}
    sprintf(StringBuffer, "BIEN4220 CLI\r\n");
    SendString2RS232(&StringBuffer);
    while(PrintSemaphore) {;}
    sprintf(StringBuffer, "Marquette University\r\n");
    SendString2RS232(&StringBuffer);
    while(PrintSemaphore) {;} 
    sprintf(StringBuffer, "2026.03.19\r\n");
    SendString2RS232(&StringBuffer);
    while(PrintSemaphore) {;}
    sprintf(StringBuffer, "---------------------\r\n");
    SendString2RS232(&StringBuffer);
    while(PrintSemaphore) {;}   
  }


/******************************************************************
   Function:     commandCheckSensor
   Description:  Prints a single sensor reading to the serial port
   Notes:
   Returns:      None
 *****************************************************************/
void commandCheckSensor (void) {

  while(PrintSemaphore) {;}
  sprintf(StringBuffer, "Force: %d\r\n", SampleData);
  SendString2RS232(&StringBuffer);
  while(PrintSemaphore) {;}
}




// tare the scale when the "t;" is input to the CLI
void commandTare(void)
{
  return;
}

// enable the "PrintSensor" functionality
void commandStreamSensor (void)
{
  return;
}

// disable the "PrintSensor" functionality
void commandStopStreamSensor (void)
{
  return;
}

