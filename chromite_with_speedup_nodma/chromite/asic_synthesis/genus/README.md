# GENUS Synthesis Scripts


This folder contains the scripts to perform genus synthesis.

The user needs to provide 2 additional scripts which depend on the user design and pdk:
- `user_tcl` : this tcl should provide necessary information about the design. A sample file
  containing all the parameters is present in samples/example_user_input.tcl
- `pd_tcl` : this tcl should provide necessary information about the PDK being used for synthesis. A
  sample tcl for this input is provided in samples/example_pd_input.tcl

To perform synthesis:
```shell
cd run
make synth user_tcl=<path to your user input tcl> pd_tcl=<path to pd input tcl without the
.tcl extension>
```

To clean the folder:
```shell
cd run
make clean
```


## File structure


```bash

├── constraints       
│   └── constraints.sdc           # contains the generic constraints file for any design
├── README.rst                    # this file
├── run
│   └── Makefile                  # makefile to invoke genus synthesis command
├── samples
│   ├── example_pd.tcl            # sample tcl file for pdk
│   └── example_user_input.tcl    # sample tcl file for user design
└── scripts
    ├── custom.tcl                # set of useful custom tcl functions
    ├── syn_genus_basic.tcl       # the synthesis tcl script
    └── syn_genus_verif.tcl       # the post synthesis sanity check tcl script

```
