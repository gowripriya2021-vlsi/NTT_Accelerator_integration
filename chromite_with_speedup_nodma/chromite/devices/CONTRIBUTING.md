# Contribution Guideline


- [Contribution Guideline](#contribution-guideline)
  * [Steps for contributing a new BSV-based device](#steps-for-contributing-a-new-bsv-based-device)
    + [1. Create an issue for your device using the issue tracker](#1-create-an-issue-for-your-device-using-the-issue-tracker)
    + [2. Create a fork/branch in the name of the same module](#2-create-a-fork-branch-in-the-name-of-the-same-module)
    + [3. BSV module creation](#3-bsv-module-creation)
      - [I. File structure: Each device should have atleast the following files:](#i-file-structure--each-device-should-have-atleast-the-following-files-)
      - [II. Interface naming convention:](#ii-interface-naming-convention-)
      - [III. Module naming convention:](#iii-module-naming-convention-)
      - [IV. Exporting interfaces, modules and types](#iv-exporting-interfaces--modules-and-types)
    + [4. Compile BSV](#4-compile-bsv)
    + [5. Create a Pull Request:](#5-create-a-pull-request-)

The devices in repo are used by the [SoC-Gen](https://gitlab.com/incoresemi/tools/soc-gen.git) and thereby follow a unique coding guideline. If you wish contribute a new module/device/peripheral here please follow the below standards.



## Steps for contributing a new BSV-based device
We will use the example of a uart to demonstrate the guideline. Replace 'uart' with your device name wherever applicable.

### 1. Create an issue for your device using the issue tracker

    title: feature/device_uart
    description: This is a simple uart module with Rx/Tx pins. 
                 Module parameters include: 
                 1. depth of FIFO 
                 2. initial reset baud rate
                 3. Choice of clock (internal or external)
    Other features include: .........

### 2. Create a fork/branch in the name of the same module

    branch name: feature/device_uart

### 3. BSV module creation

In general please follow the bsv coding guidelines available: [here](https://drive.google.com/open?id=1an72u0QWZVCHFkRqZmq29mDqcCvZQ4xH4A2qpBx95jg)

#### I. File structure: Each device should have atleast the following files:

* **uart.bsv**: This file contains all the top modules used for instantiating the module
* **uart.defines**:  The top of this file should contain specific expressions which indicate the number of bytes used by the device in the memory-map for its configurable registers. These expressions will be used later to derive automated documentation of the device. Eg:
    ```
        // slave_bound: 12 bytes
        // space-allocation: (R: reserved, U-Used)
        // 0x0: U U R R
        // 0x4: U R R R
        // 0x8: U R R R
    ```    
    The slave_bound variable indicates that the uart device requires about 12 bytes of space for its configurable registers. The space-allocation table describes the accessible regions of the 12 bytes using a 4-byte aligned address scheme in big-endian format. The above example indicates that bytes at offset of 0, 1, 4, 8 are used by the device. Similarly, bytes at 2, 3, 5, 6, 7, 9, 10, 11 are reserved and will generate an access-fault if accessed.
    
* **uart_template.bsv**: This module should contain a module called mkdummy with an empty interface. This module should demonstrate how modules defined in uart.bsv should be instantiated. 
The file should also contain a commented section which includes a schema which defines it properties. This schema is used by soc-gen to validate if the user defined parameters are compatible with this module. The schema should be encapsulated between 'schema-start' and 'schema-end' Eg:
    ```
        /*
        schema-start
        module:
            type: string
            regex: ^uart$
        type:
            type: string
            regex: ^device$
        clusters:
            type: list
            schema:
                type: string
        roles:
            type: dict
            schema:
                master:
                    type: list
                    schema:
                        type: string
                        regex: ^(null$
                        nullable: True
                slave:
                    type: list
        parameters:
            type: dict
            schema:
                depth:
                    type: integer
                baudrate:
                    type: integer
                clock:
                    type: integer
                    max: 1
                memory_bytes:
                    type: integer
        schema-end
        */
    ```
#### II. Interface naming convention:
Currently the devices support AXI-4 and AXI-4Lite bus protocols. The interface name of a module supporting these protocols should be pre-fixed with 'Ifc_' and post-fixed with either '_axi4' or '_axi4lite' as applicable. Eg:

```
    interface Ifc_uart_axi4#(numeric type addr_width, 
                               numeric type data_width, 
                               numeric type user_width, 
                               numeric type depth))
               OR
    interface Ifc_uart_axi4lite#(numeric type addr_width, 
                               numeric type data_width, 
                               numeric type user_width, 
                               numeric type depth))
```
Note that all the characters except the first "I" in the interface name should be lower case. Also note that the first 3 parameters in the interface definition followed by '#' have to be addr_width, data_width and user_width. For compatibility with soc-gen these names should not be changed. User defined parameters can follow after these 3 parameters.
All interfaces of the device which are IOs (rx and tx in case of uart) should be defined as a separate interface and the name should be prefixed with "io_". Eg:

```
    interface RS232;
       // Inputs
       (* prefix = "" *)
       method    Action      rx((* port = "SIN" *)Bit#(1) x);
       // Outputs
       (* prefix = "", result = "SOUT" *)
       method    Bit#(1)     tx();
    endinterface

    interface Ifc_uart_axi4#(...);
         interface RS232 io_output_from_uart;
    endinterface
```

The interface definition of the module should also contain one or more 'axi4' or 'axi4lite' slave interfaces. The name of this interfaces should be prefixed with 'slave' or 'slave_' for compatibility with soc-gen. Eg:

```
    interface Ifc_uart_axi4#(...);
         interface RS232 io_output_from_uart;
         interface AXI4_Slave_IFC#(addr_width, data_width, user_width) slave;
    endinterface
```

#### III. Module naming convention:
Similar to the interface naming convention each module name should be prefixed with 'mk' and post-fixed by either '_axi4' or '_axi4lite' as applicable. The module arguments can include only the following types:
    * Clock
    * Reset
    * parameter
```
	module mkuart_axi4#(Clock uart_clock, Reset uart_reset,  parameter Bit#(16) baudrate)
        (Ifc_uart_axi4#(addr_width,data_width,user_width, depth))
```         

#### IV. Exporting interfaces, modules and types

uart.bsv should include 'export' defnitions of all interfaces, modules and types which need to be exposed to the soc-gen. These are required for valid compilation of the soc-gen. Eg:
```
  export RS232             (..); // type export
  export Ifc_uart_axi4lite (..); // interface export
  export Ifc_uart_axi4     (..); // interface export
  export mkuart_axi4lite;        // module export    
  export mkuart_axi4;            // module export
```

### 4. Compile BSV

A generic Makefile is available in the root folder of this repo which can be used to compile your code and generate verilog.

Before compilation, you need to update the Makefile.inc file. The following parameters need to be updated:
    1. DIR: This variable needs to be appended with the name of the new folder you have created for your device.
    2. TOP_DIR: This variable is set to the name of the new folder you have created for your device.
    3. TOP_FILE: This variable is set to the name of your device_template.bsv file.

Sample for uart is provided below:
```
    DIR:= ./uart
    TOP_DIR:= ./uart                                  
    TOP_FILE:= ./uart_template.bsv
```

 Once the above changes are done simply type **make** to initiate the compilation to generate verilog. One can also compile for bluesim using the target **make compile** and also link in bluesim using **make link**
 
 ### 5. Create a Pull Request:
 
 Once you have successfull compiled your code and meet all the coding requirements mentioned in step-3 you can now create a pull-request for your feature.
