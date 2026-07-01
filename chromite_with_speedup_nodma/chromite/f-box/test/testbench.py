import cocotb
from cocotb.triggers import Timer, RisingEdge, ReadOnly
from cocotb_coverage.coverage import *
from collections import deque
import logging
from logging.handlers import RotatingFileHandler
import random
from bsvstruct_class import *
from modules import *
from ruamel.yaml import YAML
from riscof.utils import shellCommand
import random

yaml = YAML(typ="rt")
yaml.default_flow_style = False
yaml.allow_unicode = True

log = cocotb.logging.getLogger("cocotb")

flen = FLEN().size()
xlen = XLEN().size()

def gen_inst_obj(op1,op2,op3,node,rm=None,sp=0):
    '''
        Generates the instruction objects based on the inputs.
    '''
    x = Test_in()
    x.op1 = op1
    x.op2 = op2
    x.op3 = op3
    if 'incvt' in node:
        x.incvt = node['incvt'].format(sp=sp)
    else:
        x.incvt = 1
    if 'outcvt' in node:
        x.outcvt = node['outcvt'].format(sp=sp)
    else:
        x.outcvt = 1
    if 'outsp' in node:
        x.outsp = node['outsp'].format(sp=sp)
    if 'insp' in node:
        x.issp = node['insp'].format(sp=sp)
    if rm is None:
        if 'rm' in node:
            x.rm = node['rm']
    else:
        x.rm = rm
    if 'opcode' in node:
        x.opcode = node['opcode']
    if 'f7' in node:
        x.f7 = node['f7']
    if 'f3' in node:
        x.f3 = node['f3']
    if 'imm' in node:
        x.imm = node['imm']
    return x

def run_test_float(string,fname):
    '''
        Function to run the test float binary on the host system.
    '''
    rcode = shellCommand("testfloat_gen "+string+" >"+fname).run()
    if rcode != 0:
        log.error("Error executing: "+(string))
        raise SystemExit

def process_tfloat_input(inp):
    '''
        Function to process the lines from test float outputs.
    '''
    l = len(inp)-2
    out = [int(x,base=16) for x in inp]
    if l != 3:
        out = out[:l]+ [0]*(3-l) +out[l:]
    return out

@cocotb.test()
def test_fmadd(dut):
    '''
        Test function to test the output of the FMA instructions.
    '''
    with open("./fields.yaml","r") as f:
        cfg = dict(yaml.load(f))
    tb = Tb(dut,2,300000)
    yield tb.reset()
    nfmadd = cfg['fmadd']
    pref = "s"
    if flen == 64:
        nfdiv = cfg['fdivd']
        pref = 'd'
    else:
        nfdiv = cfg['fdivs']
    inps = [ random.randint(0,2) for x in range(10)]
    run_test_float(nfmadd['tfloat'].format(flen=flen),"fmadd.txt")
    run_test_float(nfdiv['tfloat'].format(flen=flen),"fdiv.txt")
    fmadd = []
    with open("./fmadd.txt","r") as f:
        for i in range(len(inps)):
            fmadd.append(process_tfloat_input((f.readline()).split(" ")))
        nfmadd['inputs'] = fmadd
    fdiv = []
    with open("./fdiv.txt","r") as f:
        for i in range(len(inps)):
            fdiv.append(process_tfloat_input((f.readline()).split(" ")))
        nfdiv['inputs'] = fdiv
    cocotb.fork(tb.instance.verify_responses())

    i = 0
    while i != len(inps):
        node = nfmadd
        rdy = yield tb.instance.ready()
        loop = getattr(rdy,pref+node['wait'])
        while loop != 1:
            rdy = yield tb.instance.ready()
            loop = getattr(rdy,pref+node['wait'])
            yield RisingEdge(dut.CLK)
        log.debug("Sending "+node['wait'])
        inputs = node['inputs'].pop(0)
        out = Test_out()
        out.fbox_result = inputs[3]
        out.fbox_flags = inputs[4]
        yield tb.instance.send_request(gen_inst_obj(inputs[0],
            inputs[1],inputs[2], node),out)
        i+=1
    while len(tb.instance.expected_output) != 0:
        yield RisingEdge(dut.CLK)

@cocotb.test()
def test_single_isntr(dut):
    '''
        Example test function to test a single instruction. All inputs are given in IEEE format.
    '''
    tb = Tb(dut,2,300000)
    yield tb.reset()
    cocotb.fork(tb.instance.verify_responses())
    x = Test_in()
    x.opcode = 0
    x.f7=0x70
    x.issp = True
    x.op1 = 0xffffffffc5453000
    x.op2 = 0xffffffff2749503f
    x.op3 = 0xffffffff96fcbe14
    x.incvt = 1
    x.outcvt = 1
    x.outsp = 1
    out = Test_out()
    out.fbox_result = 0xffffffffad1b1080
    out.fbox_flags = 1
    yield tb.instance.send_request(x,out)
    while len(tb.instance.expected_output) != 0:
        yield RisingEdge(dut.CLK)

@cocotb.test()
def test_fmadd_fsqrt(dut):
    with open("./fields.yaml","r") as f:
        cfg = dict(yaml.load(f))
    # print(cfg)
    tb = Tb(dut,2,300000)
    yield tb.reset()
    nfmadd = cfg['fmadd']
    pref = "s"
    if flen == 64:
        nfdiv = cfg['fdivd']
        pref = 'd'
    else:
        nfdiv = cfg['fdivs']
    inps = [ random.randint(0,2) for x in range(10)]
    run_test_float(nfmadd['tfloat'].format(flen=flen),"fmadd.txt")
    run_test_float(nfdiv['tfloat'].format(flen=flen),"fdiv.txt")
    fmadd = []
    with open("./fmadd.txt","r") as f:
        for i in range(len(inps)):
            fmadd.append(process_tfloat_input((f.readline()).split(" ")))
        nfmadd['inputs'] = fmadd
    fdiv = []
    with open("./fdiv.txt","r") as f:
        for i in range(len(inps)):
            fdiv.append(process_tfloat_input((f.readline()).split(" ")))
        nfdiv['inputs'] = fdiv
    cocotb.fork(tb.instance.verify_responses())

    i = 0
    while i != len(inps):
        if inps[i] == 0:
            node = nfmadd
        else:
            node = nfdiv
        rdy = yield tb.instance.ready()
        loop = getattr(rdy,pref+node['wait'])
        while loop != 1:
            rdy = yield tb.instance.ready()
            loop = getattr(rdy,pref+node['wait'])
            yield RisingEdge(dut.CLK)
        log.debug("Sending "+node['wait'])
        inputs = node['inputs'].pop(0)
        out = Test_out()
        out.fbox_result = inputs[3]
        out.fbox_flags = inputs[4]
        yield tb.instance.send_request(gen_inst_obj(inputs[0],
            inputs[1],inputs[2], node),out)
        i+=1

    while len(tb.instance.expected_output) != 0:
        yield RisingEdge(dut.CLK)

