[![pipeline status](https://gitlab.com/incoresemi/uncore/devices/badges/master/pipeline.svg)](https://gitlab.com/incoresemi/uncore/devices/commits/master)

# Devices

This repo contains peripheral devices which can be used to build SoCs.
Prelimnary details of each device can be found in the .blocks files in the respective folders

# To compile a device

Setup:

```
cd devices/
./manager.sh update_deps
```

Generic command

```
  make TOP_MODULE=<name of module> TOP_DIR=<dir containing the top file> TOP_FILE=<filename>.bsv generate_verilog
```

Example:

```
make TOP_MODULE=mkdummy TOP_DIR=qspi TOP_FILE=qspi_template.bsv generate_verilog
```

Verilog files will be in : build/hw/verilog

