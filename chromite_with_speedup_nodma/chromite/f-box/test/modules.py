import cocotb
from cocotb.triggers import Timer, RisingEdge, ReadOnly

from cocotb.utils import hexdump, hexdiffs
from cocotb.log import SimLog
from cocotb.result import TestFailure, TestSuccess

from cocotb_bus.scoreboard import Scoreboard

from cocotb_bus.monitors import Monitor

from cocotb_coverage.coverage import *

from collections import deque
import logging
from logging.handlers import RotatingFileHandler

import random

from getput import *
from bsvstruct_class import *

log = cocotb.logging.getLogger("cocotb")

class MyScoreboard(Scoreboard):
    def compare(self,got,exp,log,**_):
        res = got
        # act = Output().set(int(exp[0]+exp[1],16))
        print(res)
        assert res.result == int(exp[0],16) , "Mismatched Result: Exp: {0} Res:{1}".format(
                    exp[0],hex(res.result))
        assert res.flags == int(exp[1],16) , "Mismatched flags: Exp: {0} Res:{1}".format(
                    exp[1],hex(res.flags))


class OMonitor(Monitor):
    def __init__(self,dut,interface,callback=None, event=None):
        self.interface = interface
        self.clock = dut.CLK

        # The following 3 lines are necessary, else cocotb 1.5.2 will complaint.
        # You can change the name though. imon= input monitor, omon = output
        # monitor, smon = internal signal monitor, etc.
        self.name = "fma.omon"
        self.log = logging.getLogger("cocotb")
        # self.enlog = enlog
        Monitor.__init__(self, callback, event)

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            resp = yield self.interface.read()
            self.log.info("Got Response: "+str(resp))
            self._recv(resp)

class FMA:
    def __init__(self,dut):
        self.request = put(dut,"put_req",dataclass=Input)
        self.response = get(dut,"get_res",dataclass=Output)
        # self.omon = OMonitor(dut,self.response)
        self.expected_output = []
        # self.scoreboard = MyScoreboard(dut)
        # self.scoreboard.add_interface(self.omon,self.expected_output)
        self.log = logging.getLogger("cocotb")
        self.clk = dut.CLK

    @cocotb.coroutine
    def send_request(self,req,res):
        self.log.info("Sending request: "+str(req))
        self.expected_output.append(res)
        yield self.request.write(req)

    @cocotb.coroutine
    def verify_responses(self):
        while True:
            if(len(self.expected_output)>0):
                res = yield self.response.read()
                if res is not None:
                    self.log.info("Got Response: "+str(res))
                    got = res
                    # act = Output().set(int(exp[0]+exp[1],16))
                    # print(self.expected_output)
                    exp = self.expected_output.pop(0)
                    if not res.result == int(exp[0],16):
                        self.log.error("Mismatched Result: Exp: {0} Res:{1}".format(
                                exp[0],hex(res.result)))
                    else:
                        self.log.debug("Result Match.")
                    if not res.flags == int(exp[1],16):
                        self.log.error("Mismatched flags: Exp: {0} Res:{1}".format(
                                exp[1],hex(res.flags)))
                    else:
                        self.log.debug("Flag Match.")
            else:
                yield RisingEdge(self.clk)
            # yield True

class CVT:
    def __init__(self,dut):
        self.request = put(dut,"put_req",dataclass=Input_cvt)
        self.log = logging.getLogger("cocotb")
        self.clk = dut.CLK

    @cocotb.coroutine
    def send_request(self,req):
        self.log.info("Sending request: "+str(req))
        yield self.request.write(req)

class FPU:
    def __init__(self,dut):
        self.request = put(dut,"in",dataclass=Test_in)
        self.log = logging.getLogger("cocotb")
        self.clk = dut.CLK
        self.response = get(dut,"out",dataclass=Test_out)
        self.sig_ready = getattr(dut,"rdy")
        self.sig_rdy_ready = getattr(dut,"RDY_rdy")
        self.expected_output = []
        self.request_queue = []
        self.sent = 0
        self.received = 0

    @cocotb.coroutine
    def ready(self):
        if self.sig_rdy_ready != 1 :
            log.debug("Waiting for Ready.")
            yield RisingEdge(self.clk)
        else:
            yield Timer(1,units="ns")
            x = Test_rdy()
            x.set(self.sig_ready.value)
            log.debug("Ready Signal: "+str(x))
            return x

    @cocotb.coroutine
    def send_request(self,req,res):
        self.log.info(f"Sending request {self.sent}: "+str(req))
        self.expected_output.append(res)
        self.request_queue.append(res)
        self.log.info(str(res))
        self.sent+=1
        yield self.request.write(req)

    @cocotb.coroutine
    def verify_responses(self):
        while True:
            if(len(self.expected_output)>0):
                res = yield self.response.read()
                if res is not None:
                    self.sent+=1
                    self.log.info(f"Got Response {self.received}: "+str(res))
                    got = res
                    exp = self.expected_output.pop(0)
                    if not res.fbox_result == exp.fbox_result:
                        self.log.error("Mismatched Result {0}: Exp: {1} Res:{2}".format(
                               self.received, hex(exp.fbox_result),hex(res.fbox_result)))
                    if not res.fbox_flags == exp.fbox_flags:
                        self.log.error("Mismatched flags {2}: Exp: {0} Res:{1}".format(
                                hex(exp.fbox_flags),hex(res.fbox_flags),self.received))
                    self.received += 1
            else:
                yield RisingEdge(self.clk)



class Tb:
    def __init__(self,dut,mod = 2,max_cycles=300):
        self.max_cycles = max_cycles
        self.dut = dut
        self.logger = log
        if mod == 1:
            self.instance = CVT(dut)
        elif mod == 0:
            self.instance = FMA(dut)
        else:
            self.instance = FPU(dut)
        # self.instance = CVT(dut) if mod == 1 else FMA(dut)

        self.run_sim = True

    @cocotb.coroutine
    def monitor(self):
        while True:
            yield(RisingEdge(self.dut.CLK))

    @cocotb.coroutine
    def run(self,period):
        signal = self.dut.CLK
        while self.run_sim:
            signal <= 0
            yield Timer(period/2)
            signal <= 1
            yield Timer(period/2)

    @cocotb.coroutine
    def force_end_sim(self):
        yield Timer(1000*self.max_cycles)
        self.run_sim = False

    @cocotb.coroutine
    def reset(self):
        cocotb.fork(self.run(period=10000))
        cocotb.fork(self.force_end_sim())
        self.dut.RST_N <= 0
        yield RisingEdge(self.dut.CLK)
        self.dut.RST_N <= 1
        i = 0
        while i<200:
            i += 1
            yield RisingEdge(self.dut.CLK)

    def end_sim(self):
        self.run_sim = False

@cocotb.coroutine
def clock_gen(signal, period=10000):
    while True:
        signal <= 0
        yield Timer(period/2)
        signal <= 1
        yield Timer(period/2)
