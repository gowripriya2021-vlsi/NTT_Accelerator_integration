
# Generated on 2022-05-03 17:35:14.208506
from dataclasses import dataclass
@dataclass(init=False)
class FLEN:
    FLEN: int = 0
    fields_FLEN = {
        'FLEN' : 64}


    def set(self, val):

        self.FLEN = (val.integer >> 0) & 0xffffffffffffffff

    def __bin__(self) -> str:
        val = ''
        val += '{0:064b}'.format(self.FLEN & 0xffffffffffffffff)
        return val

    def get(self) -> int:
        return int(self.__bin__(),base=2)

    def __int__(self) -> int:
        return int(self.__bin__(),base=2)

    def size(self) -> int:
        return 64



@dataclass(init=False)
class Test_in:
    incvt: int = 0
    outcvt: int = 0
    outsp: int = 0
    op1: int = 0
    op2: int = 0
    op3: int = 0
    opcode: int = 0
    f7: int = 0
    f3: int = 0
    imm: int = 0
    rm: int = 0
    issp: int = 0
    fields_Test_in = {
        'incvt' : 1,
        'outcvt' : 1,
        'outsp' : 1,
        'op1' : 64,
        'op2' : 64,
        'op3' : 64,
        'opcode' : 4,
        'f7' : 7,
        'f3' : 3,
        'imm' : 2,
        'rm' : 3,
        'issp' : 1}


    def set(self, val):

        self.incvt = (val.integer >> 214) & 0x1
        self.outcvt = (val.integer >> 213) & 0x1
        self.outsp = (val.integer >> 212) & 0x1
        self.op1 = (val.integer >> 148) & 0xffffffffffffffff
        self.op2 = (val.integer >> 84) & 0xffffffffffffffff
        self.op3 = (val.integer >> 20) & 0xffffffffffffffff
        self.opcode = (val.integer >> 16) & 0xf
        self.f7 = (val.integer >> 9) & 0x7f
        self.f3 = (val.integer >> 6) & 0x7
        self.imm = (val.integer >> 4) & 0x3
        self.rm = (val.integer >> 1) & 0x7
        self.issp = (val.integer >> 0) & 0x1

    def __bin__(self) -> str:
        val = ''
        val += '{0:01b}'.format(self.incvt & 0x1)
        val += '{0:01b}'.format(self.outcvt & 0x1)
        val += '{0:01b}'.format(self.outsp & 0x1)
        val += '{0:064b}'.format(self.op1 & 0xffffffffffffffff)
        val += '{0:064b}'.format(self.op2 & 0xffffffffffffffff)
        val += '{0:064b}'.format(self.op3 & 0xffffffffffffffff)
        val += '{0:04b}'.format(self.opcode & 0xf)
        val += '{0:07b}'.format(self.f7 & 0x7f)
        val += '{0:03b}'.format(self.f3 & 0x7)
        val += '{0:02b}'.format(self.imm & 0x3)
        val += '{0:03b}'.format(self.rm & 0x7)
        val += '{0:01b}'.format(self.issp & 0x1)
        return val

    def get(self) -> int:
        return int(self.__bin__(),base=2)

    def __int__(self) -> int:
        return int(self.__bin__(),base=2)

    def size(self) -> int:
        return 215



@dataclass(init=False)
class Test_out:
    fbox_result: int = 0
    fbox_flags: int = 0
    fields_Test_out = {
        'fbox_result' : 64,
        'fbox_flags' : 5}


    def set(self, val):

        self.fbox_result = (val.integer >> 5) & 0xffffffffffffffff
        self.fbox_flags = (val.integer >> 0) & 0x1f

    def __bin__(self) -> str:
        val = ''
        val += '{0:064b}'.format(self.fbox_result & 0xffffffffffffffff)
        val += '{0:05b}'.format(self.fbox_flags & 0x1f)
        return val

    def get(self) -> int:
        return int(self.__bin__(),base=2)

    def __int__(self) -> int:
        return int(self.__bin__(),base=2)

    def size(self) -> int:
        return 69



@dataclass(init=False)
class Test_rdy:
    dfma: int = 0
    ddivsqrt: int = 0
    dcvt: int = 0
    sfma: int = 0
    sdivsqrt: int = 0
    singlecycle: int = 0
    scvt: int = 0
    fields_Test_rdy = {
        'dfma' : 1,
        'ddivsqrt' : 1,
        'dcvt' : 1,
        'sfma' : 1,
        'sdivsqrt' : 1,
        'singlecycle' : 1,
        'scvt' : 1}


    def set(self, val):

        self.dfma = (val.integer >> 6) & 0x1
        self.ddivsqrt = (val.integer >> 5) & 0x1
        self.dcvt = (val.integer >> 4) & 0x1
        self.sfma = (val.integer >> 3) & 0x1
        self.sdivsqrt = (val.integer >> 2) & 0x1
        self.singlecycle = (val.integer >> 1) & 0x1
        self.scvt = (val.integer >> 0) & 0x1

    def __bin__(self) -> str:
        val = ''
        val += '{0:01b}'.format(self.dfma & 0x1)
        val += '{0:01b}'.format(self.ddivsqrt & 0x1)
        val += '{0:01b}'.format(self.dcvt & 0x1)
        val += '{0:01b}'.format(self.sfma & 0x1)
        val += '{0:01b}'.format(self.sdivsqrt & 0x1)
        val += '{0:01b}'.format(self.singlecycle & 0x1)
        val += '{0:01b}'.format(self.scvt & 0x1)
        return val

    def get(self) -> int:
        return int(self.__bin__(),base=2)

    def __int__(self) -> int:
        return int(self.__bin__(),base=2)

    def size(self) -> int:
        return 7



@dataclass(init=False)
class XLEN:
    XLEN: int = 0
    fields_XLEN = {
        'XLEN' : 64}


    def set(self, val):

        self.XLEN = (val.integer >> 0) & 0xffffffffffffffff

    def __bin__(self) -> str:
        val = ''
        val += '{0:064b}'.format(self.XLEN & 0xffffffffffffffff)
        return val

    def get(self) -> int:
        return int(self.__bin__(),base=2)

    def __int__(self) -> int:
        return int(self.__bin__(),base=2)

    def size(self) -> int:
        return 64


