# f-box

## Directory Structure
- ``bluespec_src``: Contains the bluespec source files for different modules.
- ``docs``: Contains justification for the various design decisions.
- ``stats``: Contains synthesis numbers for different configurations for the individual FMA moudules.
- ``tcl``: Contains tcl scripts for synthesis.
- ``test``: Contains the unit testing infrastructure.
    - ``fields.yaml``: Contains the field values for individual instructions. To add support for a
      missing instruction, add an entry describing all necessary fields in this file. Node
      structure:
      ```
        <instruction_name>:
            opcode: <value of the opcode field for the instruction>
            f7: <value of the f7 filed for the instruction>
            wait: <Name of the field in the FBoxRdy which indicates that the module is 
                ready to accept inputs>.
            tfloat: <Command which should be used to run the testfloat binaries. The flen variable
                can be used to signify the flen value at run-time>
            incvt: <Boolean value which specifies whether the input should be recoded before giving
                it to the FPU module.>
            outcvt: <Boolean value which specifies whether the value from the module needs to be run
                through the recFNToFN module before returning the value to the testbench.>
            insp: <Boolean value which specifies whether the operation is a SP operation.>
            outsp: <Boolean value which specifies whether the output of the operation is a SP
                value.>
      ```
    - ``testbench.bsv``: The bluespec testbench for FPU.
    - ``testbench.py``: The cocotb testbench for the FPU module. Additional functions should be
      added to this file to run the required tests.
- ``verilog_src``: Contains the verilog files form berkeley hardfloat.

## Test

### Pre-requisite
- Testfloat binaries (available on ``$PATH``)
- Python(with cocotb)

### Setup
All the necessary repos will be cloned with the following command.
```
./manager.sh update_deps
```

To generate the data structures in the bluespec modules for use in the python testbench the
following command can be used. The bit widths of the fields is automatically picked up from the data
structures.
```
make genstructs
```
