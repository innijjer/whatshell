# whatshell

A PoC to demonstrate the practicality of using mobile instant messaging application for a meterpreter like shell. This script is made using the Unix shell.

### Getting Started

This script currently only targets WhatsApp for communication. This script can be run from the unix shell on any Android phone with WhatsApp installed. A server phone number must be established in the 'number' variable of a valid WhatsApp user to send commands from.

### Prerequisites

The Android device should be rooted and have the latest version of sqlite3 installed

### Manual Setup

Without the server script, the WhatsApp user acting as the server will receive messages directly to the app. To setup the connection the following steps will take place:

1. Victim sends 'SYN' message
2. Server sends 'ACK' message (Manually type)
3. Victim will confirm and send working directory for shell

### Commands

The following commands can be sent from the user acting as the server to the victim user:
NOTE: The push command will not work manually and the pull command will return the file encoded in base64 segments. 

- shell {command} 
  - Runs shell command and returns stdout
- pull {path}
  - Exfiltrates file from victims device
- push {path}
  - Infiltrates file into victims device
- screenshot
  - Uses shell command to take screenshot and exfiltrates file
- getuid
  - Current user uid
- ifconfig
  - Network information
- ps
  - Displays running processes
- sysinfo
  - Displays system information like device name and build
