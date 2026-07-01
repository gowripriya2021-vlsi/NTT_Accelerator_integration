
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc SVNAPOT=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc SVNAPOT=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc SVNAPOT=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc SVNAPOT=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc SVNAPOT=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc SVNAPOT=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi 
    # if make clean;make generate_verilog CONFIG=Makefile_fasv32.inc; then
    #     echo "*****************PASSED*****************************************************"
    # else
    #     echo "FALILED";
    #     exit
    # fi 
    # if make clean;make generate_verilog CONFIG=Makefile_sasv32.inc DUMMY=enable; then
    #     echo "*****************PASSED*****************************************************"
    # else
    #     echo "FALILED";
    #     exit
    # fi
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc SVNAPOT=enable DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc SVNAPOT=enable DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc SVNAPOT=enable DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc SVNAPOT=enable DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc SVNAPOT=enable DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc SVNAPOT=enable DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc DUMMY=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi    
#- 
    # if make clean;make generate_verilog CONFIG=Makefile_fasv32.inc DUMMY=enable; then
    #     echo "*****************PASSED*****************************************************"
    # else
    #     echo "FALILED";
    #     exit
    # fi 
    # if make clean;make generate_verilog CONFIG=Makefile_sasv32.inc DUMMY=enable; then
    #     echo "*****************PASSED*****************************************************"
    # else
    #     echo "FALILED";
    #     exit
    # fi
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc SVNAPOT=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc SVNAPOT=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc SVNAPOT=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc SVNAPOT=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc SVNAPOT=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc SVNAPOT=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
# # 
# if make clean;make generate_verilog CONFIG=Makefile_fasv32.inc HYPERVISOR=enable ; then
#     echo "*****************PASSED*****************************************************"
# else
#     echo "FALILED";
#     exit
# fi
# # 
# if make clean;make generate_verilog CONFIG=Makefile_sasv32.inc HYPERVISOR=enable; then
#     echo "*****************PASSED*****************************************************"
# else
#     echo "FALILED";
#     exit
# fi
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc SVNAPOT=enable DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv39.inc DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc SVNAPOT=enable DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv39.inc DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc SVNAPOT=enable DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv48.inc DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc SVNAPOT=enable DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv48.inc DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc SVNAPOT=enable DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_fasv57.inc DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc SVNAPOT=enable DUMMY=enable HYPERVISOR=enable; then
    echo "*****************PASSED*****************************************************"
else
    echo "FALILED";
    exit
fi
if make clean;make generate_verilog CONFIG=Makefile_sasv57.inc DUMMY=enable HYPERVISOR=enableelse; then
    echo "*****************PASSED*****************************************************"
else    echo "FALILED";
    exit
fi