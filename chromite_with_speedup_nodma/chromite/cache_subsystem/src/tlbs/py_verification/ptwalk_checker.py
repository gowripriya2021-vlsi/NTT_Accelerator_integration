import cocotb
from cocotb.clock import Clock
from cocotb.decorators import coroutine
from cocotb.triggers import Timer, RisingEdge, FallingEdge
from cocotb_bus.monitors import Monitor
from cocotb.binary import BinaryValue
from cocotb.result import TestFailure
from cocotb.log import SimLog
from cocotb_bus.scoreboard import Scoreboard
from datetime import datetime
from pathlib import Path
from collections import abc
from mmu_model import python_ref_model
import logging
from utils import *
import random
import sys
# from instr_encodings import *

ref_model_results = []
current_clock = 0
# instruction = Instruction()

class Checker:

    def __init__(self, dut, enlog=False):

        self.name = "ptwalk"
        self.log = logging.getLogger("cocotb")
        self.hardware = {}
        self.max_cycles = 0

        if enlog:
            self.log.info(' Setting up Output Monitor')
        self.output_mon = OMonitor(dut, enlog=enlog)

        if enlog:
            self.log.info(' Setting up Input Monitor')
        self.input_mon = IMonitor(dut, callback=self.model, enlog=enlog)

        self.log.info(' Setting up Score-board')
        self.expected_output = []
        self.scoreboard = MyScoreboard(dut)
        self.scoreboard.add_interface(self.output_mon, self.expected_output)
        self.xlen = dut.ma_request_src1.value.n_bits

    def simulate_file(self, file_name, instr ):
        cwd = os.getcwd() + str('/../')
        compile_cmd = f'riscv{self.xlen}-unknown-elf-gcc -march=rv{self.xlen}i -static \
         -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -T ../link.ld \
         ./ref_model.S -o {cwd}/dut.elf'
        cmd = shellCommand(compile_cmd).run(cwd=cwd)
        if (cmd == 0) and (os.path.isfile(f"{cwd}/dut.elf")):
            spike_cmd = f'spike --isa=rv{self.xlen}i_zba_zbb_zbc_zbs_Xbitmanip +signature={cwd}/ref.signature \
             +signature-granularity={self.xlen//8} {cwd}/dut.elf'
            cmd = shellCommand(spike_cmd).run(cwd=cwd)
            if (cmd == 0) and (os.path.isfile(f"{cwd}/ref.signature")):
                return int('0x'+Path(f"{cwd}/ref.signature").read_text().rstrip(),0)
            else:
                self.log.error(__name__+f' Failed to simulate {hex(instr)} on spike')
                raise TestFailure('Spike Simulation of Reference model failed')
        else:
            self.log.error(__name__+f' Failed to compile {hex(instr)} in GCC ')
            raise TestFailure('Compilation of Reference model failed')

    def run_ref_model(self, opc, op1, f3, f7, op2, imm ):
        instr = 0x00030293 | f3 << 12 | opc | f7 << 25
        if((opc == 27) or (opc == 19)): #imm
            instr |= imm << 20 #set immediate value
        elif(opc == 51) or (opc == 59): #reg
            instr |= 0x00700000 #set rs2
        else:
            self.log.error(__name__+f' Unidentified Opcode {hex(opc)}')
            raise TestFailure('Invalid Bitmanip Opcode provided')

        cwd = os.getcwd() + str('/../')
        now = datetime.datetime.now()
        with open(os.path.join(cwd, 'ref_model.S'),'w') as df:
            df.write('// See LICENSE.incore for license details\n')
            df.write(f'// File Generated {now.strftime("on %A, %B %dth, %Y at %H:%M:%S ")}\n\n')
            df.write(f'#if __riscv_xlen==64\n\t#define SREG sd\n#else\n\t#define SREG sw\n#endif\n')
            df.write(f'\n.section .text.init;\n.globl _start;\n_start: \n')
            df.write(f'\tla t0, trap_vector;\n\tcsrw mtvec, t0;\n\tla a0, begin_signature;\n')
            df.write(f'\tli t1, {hex(op1)} ;\n')
            df.write(f'\tli t2, {hex(op2)} ;\n')
            df.write(f'\t.word {hex(instr)} \n')
            df.write(f'\tSREG t0,0(a0);\n')
            df.write(f'\tli gp, 1\n1:\n\tsw gp, tohost, t5;\nrept:\n\tj rept;\n')
            df.write(f'\n.align 2;\ntrap_vector:\n\tori gp, gp, 1337;\n\tj 1b;\n')
            df.write(f'\n.section .tohost,"aw",@progbits;')
            df.write(f'\n.align 8; .global tohost; tohost: .dword 0;')
            df.write(f'\n.align 8; .global fromhost; fromhost: .dword 0;')
            df.write(f'\n.align 8; .global begin_signature; begin_signature:\n')
            df.write(f'\n#if __riscv_xlen==64\n\t.fill 1,8,0xDEADBEEFDEADBEEF')
            df.write(f'\n#else\n\t.fill 1,4, 0xDEADBEEF\n#endif\n')
            df.write(f'\n.global end_signature; end_signature:')
        return self.simulate_file(os.path.join(cwd, 'ref_model.S'), instr)

    def __extract_bits (self, num, leng, pos):
        start = 32 - (pos + leng)
        end   = start + (leng - 1)
        return f'{num:0>32b}'[start : end+1]
    
    def model(self, transaction, flag=False):
        """Model """
        # This function acts as the model for the dut under test
        global ref_model_results
        global current_clock
        global instruction
        result = None
        instr, op1, op2 = transaction
        XLEN = self.xlen
        opcode = self.__extract_bits(instr, 7, 0 )
        funct3 = self.__extract_bits(instr, 3, 12 )
        funct7 = self.__extract_bits(instr, 7, 25 )
        imm_value = self.__extract_bits(instr, 7, 20 )
        instr_name,ext = instruction.instr_map(bin(instr)[2:], XLEN)
        cur_cycle = 0
        self.hardware = {i:self.hardware[i] for i in self.hardware if self.hardware[i]>=current_clock }
        exp_clk = self.calc_exp_max_cycles(cur_cycle, instr_name, ext)
        controls = dict(xl=XLEN, op=opcode, f3=funct3, f7=funct7, imm=imm_value )
        result = python_ref_model(controls,op1,op2)
        ref_model_results.append([hex(result), exp_clk])
        
        spike_result = self.run_ref_model(int(opcode,2), op1, int(funct3,2), int(funct7,2), op2, int(imm_value,2))
        # self.log.debug(f'Ref. Model got input f7: {funct7} f3: {funct3} opcode: {opcode}')

        self.log.info(f' Ref Model\t instr: {instr:#08X} op1:{op1:#016X} op2:{op2:#016X} result: {hex(result)} exp. at: {exp_clk}')
        assert spike_result == result, ": Error in Reference Model - Expected: {0!s}. Received: {1!s}.".format( hex(spike_result), hex(result))

        # self.log.debug(f' Waiting for outputs {ref_model_results} from DUT..')
        if not flag:
           self.expected_output.append( result )
        else:
           return result
    
    def calc_exp_max_cycles(self, cur_cycle, instr_name, ext):
        global instruction
        global current_clock
        exp_cycles = instruction.inst_dict[ext][instr_name]['stages']
        for inst_type in instruction.inst_dict:
            if instr_name in instruction.inst_dict[inst_type]:
                cur_cycle = instruction.inst_dict[inst_type][instr_name]['cycles']
                break
        if not cur_cycle == 0:
            if instruction.inst_type_map[instr_name] in self.hardware:
                self.hardware[instruction.inst_type_map[instr_name]] = self.hardware[instruction.inst_type_map[instr_name]] + instruction.inst_dict[ext][instr_name]['cycles']
                exp_clk = self.hardware[instruction.inst_type_map[instr_name]] + instruction.inst_dict[ext][instr_name]['cycles']
                self.max_cycles = self.max_cycles + instruction.inst_dict[ext][instr_name]['cycles']
            else:
                self.hardware[instruction.inst_type_map[instr_name]] = instruction.inst_dict[ext][instr_name]['cycles'] + current_clock
                exp_clk = current_clock + instruction.inst_dict[ext][instr_name]['cycles']
                self.max_cycles = self.max_cycles + instruction.inst_dict[ext][instr_name]['cycles']
        else:
            self.max_cycles = exp_cycles if exp_cycles>self.max_cycles else self.max_cycles
            # the above check is required since the latency has to be increased if 
            # the new latency is greater than all the previous latencies
            exp_clk = current_clock + self.max_cycles
        return(exp_clk)


class MyScoreboard(Scoreboard):
    # This is the scoreboard class. You need to define how the comparison needs
    # to be happen between data received from dut and that received from the
    # model
    def compare(self, got, exp, log, **_):
        self.log = logging.getLogger("cocotb")
        global ref_model_results
        got_output=got
        exp_output=exp
        # self.log.info(f'compare\t dut out:{got_output:#016X} ref out:{exp_output:#016X}')
        assert got_output == exp_output, ": Output differs Expected: {0!s}. differ Received: {1!s}.".format( hex(exp_output), hex(got_output))
        if not ref_model_results[0][0] == hex(got_output):
            raise TestFailure('Recieved output not in-order with the reference model')
        ref_model_results.remove(ref_model_results[0])
        self.log.debug(__name__+f' Popped entry {hex(got_output)} from list of awaiting outputs..')


class IMonitor(Monitor):
    """Observes inputs of DUT."""
    # utils has loaded the alias_signal.yaml. Use the below function to populate
    # the _signals as a dictionary of all alias-signal mapping. First argument
    # is the sub-module name (without hierarchy) and the next argument is the
    # category : inputs, outputs, registers.
    _signals = get_signals('mkbitmanip','inputs')

    def __init__(self, dut, callback=None, event=None, enlog=False):
        # the following will populate the alias as methods of the self object so
        # that you can access the methods as self.op1, etc.
        for alias, signal in self._signals.items():
            setattr(self, alias, getattr(dut, signal))

        # set the clock that may or maynot be required
        self.clock = dut.CLK

        # The following 3 lines are necessary, else cocotb 1.5.2 will complaint.
        # You can change the name though. imon= input monitor, omon = output
        # monitor, smon = internal signal monitor, etc.
        self.name = "bitmanip.imon"
        self.log = logging.getLogger("cocotb")
        self.enlog = enlog
        Monitor.__init__(self, callback, event)

    @coroutine
    def _monitor_recv(self):
        # This is going to a forked coroutine which will sample the signals of
        # choice
        while True:
            # wait for posedge of clock
            yield RisingEdge(self.clock)

            # increment by 1 more second
            yield Timer(1,units="ns")

            # we only trigger sample inputs when the dut is ready and inputs are enabled
            if self.rdy.value.integer == 1 :

                # sample the inputs and send to _recv method. All samples must
                # be sent to _recv. This is what is available to the model. IT
                # could be a tuple, dictionary, list, etc. The same must be
                # assumed in the model as well
                vec = (self.instr.value.integer,
                       self.op1.value.integer,
                       self.op2.value.integer)
                self._recv(vec)
                if self.enlog :
                    for x in vec: 
                        self.log.debug(__name__+f' input: {hex(x)}')

class OMonitor(Monitor):
    """Observes outputs of DUT."""
    # utils has loaded the alias_signal.yaml. Use the below function to populate
    # the _signals as a dictionary of all alias-signal mapping. First argument
    # is the sub-module name (without hierarchy) and the next argument is the
    # category : inputs, outputs, registers.
    _signals = get_signals('mkbitmanip','outputs')

    def __init__(self, dut, callback=None, event=None, enlog=False):
        """tb must be an instance of the Testbench class."""
        # the following will populate the alias as methods of the self object so
        # that you can access the methods as self.op1, etc.
        for alias, signal in self._signals.items():
            setattr(self, alias, getattr(dut, signal))
        # set the clock that may or maynot be required
        self.clock = dut.CLK

        # The following 3 lines are necessary, else cocotb 1.5.2 will complaint.
        # You can change the name though. imon= input monitor, omon = output
        # monitor, smon = internal signal monitor, etc.
        self.name = "bitmanip.omon"
        self.log = logging.getLogger("cocotb")
        self.enlog = enlog
        Monitor.__init__(self, callback, event)

    @coroutine
    def _monitor_recv(self):
        # This is going to a forked coroutine which will sample the signals of
        # choice

        while True:
            # wait for posedge of clock signal
            yield RisingEdge(self.clock)

            # increment by 10 more pico-second, so that the output from the
            # combo is available. Doing it at "moment" (same as inputs) might not
            # work.
            yield Timer(10,units="ps")

            # Check if the outputs are ready and valid before passing it into scoreboard
            if (self.valid.value.integer == 1) and (self.resp_rdy.value.integer == 1):

                # Send the value to _recv method.
                # This _recv will act as the actual output for
                # comparison in scoreboard.
                self._recv(self.resp.value.integer)
                if self.enlog:
                    self.log.debug('bitmanip.omon: ' + str(hex(self.resp.value.integer)))



