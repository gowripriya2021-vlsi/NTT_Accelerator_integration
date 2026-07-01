from riscof import utils

import sys
def extstats():
    area = 0
    wns = 0
    with open("./build/fbox/syn_area.txt","r") as f:
        line = f.readlines()[23]
        words = [x.strip() for x in line.split(" ") if x.strip()]
        area = words[5]
    with open("./build/fbox/syn_timing.txt","r") as f:
        line = f.readlines()[130]
        words = [x.strip() for x in line.split(" ") if x.strip()]
        wns = words[0]
    return area,wns
mods = [
        # 'mk_inst_post',
        # 'mk_inst_round',
        # 'mk_inst_pre',
        'mk_inst_mac',
        # 'mk_inst_pre_mac',
        # 'mk_inst_post_round',
        # 'mk_inst_mac_post'
        ]

params = {
        1: "",2: "`define CLZ_HF",3:"`define CLZ_PE\n `define FAST_1",4:"`define CLZ_PE\n `define FAST_2"
        }


def wparams(a):
    with open("./verilog_src/params.vi","w") as f:
        f.write(params[a])

def execute(mod,lin,out,sig,exp,suff=""):
    if suff:
        suff = "_"+suff
    ext = 'D' if exp == 11 else 'F'
    try:
        command = "make IN={0} OUT={1} SIG={3} EXP={4} TOP_MODULE={2} fpga_build".format(
                    lin,out,mod,sig,exp)
        utils.shellCommand(command).run(timeout=900)
        stats = extstats()
        cp_command = "cp ./build/fbox/syn_area.txt ./stats/{4}_{0}_{1}_{2}{3}_area.txt".format(
            mod,lin,out,suff,ext)
        utils.shellCommand(cp_command).run(timeout=900)
        cp_command = "cp ./build/fbox/syn_timing.txt ./stats/{4}_{0}_{1}_{2}{3}_timing.txt".format(
            mod,lin,out,suff,ext)
        utils.shellCommand(cp_command).run(timeout=900)
        return stats
    except Exception as e:
        return ["Error",str(e)]



def generate_reports(j):
    stats = []
    sig = 53 if j==1 else 24
    exp = 11 if j==1 else 8
    ext = 'D' if j==1 else 'F'
    for lin in range(1,4):
        for out in range(1,4):
            command = "make IN={0} OUT={1} SIG={2} EXP={3} TOP_MODULE=mk_inst clean generate_verilog".format(
                    lin,out,sig,exp)
            utils.shellCommand(command).run(timeout=900)
            for entry in mods:
                stat = [entry,ext,lin,out,"-"]
                if "post" in entry:
                    for i in range(1,5):
                        temp = stat + [str(i)]
                        wparams(i)
                        temp+=execute(entry,lin,out,sig,exp,str(i))
                        print(temp)
                        with open("./stats.txt","a") as f:
                            f.write(",".join([str(x) for x in temp]))
                            f.write("\n")
                        stats += temp
                else:
                    stat += " "
                    stat += execute(entry,lin,out,sig,exp)
                    print(stat)
                    with open("./stats.txt","a") as f:
                        f.write(",".join([str(x) for x in stat]))
                        f.write("\n")
                    stats += stat
    return stats

f_mods = [
        "mk_ftod_inst",
        "mk_dtof_inst",
        ]
rec_mods = [
        "mk_inst_rectof",
        "mk_inst_ftorec"
        ]
i_mods = [
        "mk_inst_itorec",
        "mk_inst_rectoi"
        ]

def generate_cvt_reports(j,xlen,imax,omax,imods):
    stats = []
    sig = 53 if j==1 else 24
    exp = 11 if j==1 else 8
    ext = 'D' if j==1 else 'F'
    lst = []
    for lin in range(2,imax+1):
        for out in range(2,omax+1):
            if lin == 0 or out == 0:
                if lin == out:
                    lst.append((lin,out))
            else:
                lst.append((lin,out))

    for lin,out in lst:
        command = "make IN={0} OUT={1} SIG={2} EXP={3} XLEN={4} TOP_MODULE=mk_inst clean generate_verilog".format(
                lin,out,sig,exp,xlen)
        utils.shellCommand(command).run(timeout=900)
        for entry in imods:
            stat = [entry,ext,lin,out,xlen]
            stat += " "
            stat += execute(entry,lin,out,sig,exp)
            print(stat)
            with open("./stats.txt","a") as f:
                f.write(",".join([str(x) for x in stat]))
                f.write("\n")
            stats += stat
    return stats

if __name__ == "__main__":
    args = sys.argv
    n = len(args)
    isa = "FD"
    with open("./stats.txt","a") as f:
        f.write("Mod Name,Ext,IN Buff Size,Out Buff Size,XLEN,Variant(if applicable),LUT,WNS\n")
    if n == 2:
        isa = args[1]
    # if 'F' in isa or 'f' in isa:
        # generate_reports(0)
        # generate_cvt_reports(0,64,1,2,rec_mods)
        # generate_cvt_reports(0,32,2,2,i_mods)
    if 'D' in isa or 'D' in isa:
        # generate_cvt_reports(0,32,1,2,f_mods)
        # generate_cvt_reports(1,64,1,2,rec_mods)
        generate_cvt_reports(1,32,2,2,i_mods)
        # generate_cvt_reports(1,64,2,2,i_mods)
        # generate_reports(1)

