# Project Title

Uóli Software System

### Brief description

This project contains all the layers (control logic, control library and operating system) to run on an ARM processor and control the robot "Uóli".

### Control Logic (LoCo)

The LoCo sublayer was implemented in C language and makes use of the available routines in the Control API (BiCo) to send commands to the robot.

### Control library (BiCo)

The BiCo sublayer implements the Control API routines in ARM assembly language. To control the hardware, the code performs system calls.

### Operating system (SOUL)

The SOUL sublayer manages system hardware and provides services for the BiCo sublayer through system calls.

## Authors

* **Heitor Boschirolli** - [HeitorBoschirolli](https://github.com/HeitorBoschirolli)
* **Daniel Helu Prestes de Oliveira**

