"""""
  see LICENSE.incore
  see LICENSE.iitm

  Author: Shubham Roy, Neel Gala
  Email id: [shubham.roy, neelgala]@incoresemi.com
  Details: create a spike refernce model in python the refernce model used variables
  used here are named close to what are used in mmu.cc
  https://github.com/riscv-software-src/riscv-isa-sim/blob/master/riscv/mmu.cc#L261-L437

  ----
  ----------------------------------------------------------------------------------------------
"""
import logging as log
import numpy as np
from dataclasses import dataclass
from encoding import *
from page import *
import enum
from typing import Type, TypeVar
log.basicConfig(level=log.INFO)

class Access_Type(enum.Enum):
  """
  enum for access types
  """
  LOAD = 1
  STORE = 2
  FETCH = 3

@dataclass
class Vm_Info:
  """
  data class for Vm_info 
  """
  levels: int =0 
  idxbits: int =0 #subvpn
  widenbits: int =0
  ptesize: int =0
  ptbase: int = 0 

  def __str__(self) -> str:
      return f"level ={self.levels} idxbits ={self.idxbits} widenbits ={self.widenbits} ptesize ={self.ptesize} ptbase ={hex(self.ptbase)}"

  # def print_info(self):
  #   print

def uint64(x):
  """
  function to create a given input into 64 bit unsigned value
  """
  return (x & ((2**64) -1))

def uint32(x):
  """
  function to create a given input into 32 bit unsigned value
  """
  return (x & ((2**32) -1))

def decode_vm_info(xlen:int, stage2:bool, prv:int, satp) -> Vm_Info:
  """
  same as mmu.c
  """
  log.info("inside decode vm info")
  xlen = int(xlen)
  satp = uint64(satp)
  # vm_info = Vm_Info()
  if(prv == PRV_M): #3
    return Vm_Info(0, 0, 0, 0, 0)
  elif (not stage2) and prv <= PRV_S and xlen == 32:
    if (get_field(satp, SATP32_MODE) == SATP_MODE_OFF):
      return Vm_Info(0, 0, 0, 0, 0)
    elif get_field(satp, SATP32_MODE) == SATP_MODE_SV32:
      return Vm_Info(2, 10, 0, 4, (satp & SATP32_PPN) << 12)
    else :
      log.info("inside decode vm info") 
      exit() 
  elif (not stage2) and prv <= PRV_S and xlen == 64:
    if (get_field(satp, SATP64_MODE) == SATP_MODE_OFF):
      return Vm_Info(0, 0, 0, 0, 0)
    elif get_field(satp, SATP64_MODE) == SATP_MODE_SV32:
      return Vm_Info(2, 9, 0, 8, (satp & SATP64_PPN) << 12)
    elif get_field(satp, SATP64_MODE) == SATP_MODE_SV39:
      return Vm_Info(3, 9, 0, 8, (satp & SATP64_PPN) << 12)  
    else :
      log.info("inside decode vm info") 
      exit()
  elif (stage2) and xlen == 32:
    if (get_field(satp, HGATP32_MODE) == HGATP_MODE_OFF):
      return Vm_Info(0, 0, 0, 0, 0)
    elif get_field(satp, HGATP32_MODE) == HGATP_MODE_SV32X4:
      return Vm_Info(2, 10, 2, 4, (satp & SATP32_PPN) << 12)
    else : 
      log.info("inside decode vm info stage 32")
      exit() 
  elif (stage2) and xlen == 64:
    if (get_field(satp, HGATP64_MODE) == HGATP_MODE_OFF):
      return Vm_Info(0, 0, 0, 0, 0)
    elif get_field(satp, HGATP64_MODE) == HGATP_MODE_SV32X4:
      return Vm_Info(2, 9, 2, 8, (satp & SATP64_PPN) << 12)
    elif get_field(satp, HGATP64_MODE) == HGATP_MODE_SV39X4:
      return Vm_Info(3, 9, 2, 8, (satp & SATP64_PPN) << 12)  
    else :
      log.info("inside decode vm info satge 2 64") 
      exit() 
  else:
    log.info("inside decode vm info final else")
    exit()    


class Mmu_t:
  """
  same as mmu.h
  not all of the data method and members are created 
  """
  
  def __init__(self):
    self.v = 1
    self.xlen= 64
    self.satp = rg(8,60)|rg(0x80_000,0)    
    self.vssatp = self.satp 
    self.hgatp = rg(8,60)| rg(0x90_000,0)
    self.mstatus = MSTATUS#set accordingly 
    # self.vstatus =0x80_000_000
    self.hstatus = MSTATUS
    self.mxr = True
    self.sum = True
    self.access = 1
    self.prv = 3
    # self.debug_mode
    
    self.svnapot = True

  def throw_access_exception(virt:bool, addr:np.uint64, type:Access_Type):
    if type == Access_Type.FETCH :
      raise Exception("Instruction access fault")
    elif type == Access_Type.LOAD:
      raise Exception("Load access fault")
    elif type == Access_Type.STORE:
      raise Exception("Store access fault")
    else:
      exit()
  
  def ctz(n):
    """
    count traling zeroes
    """
    for i in range(20):
        if n % (2<<i) != 0:
            return i

  def pmp_ok():
    return True
    # # if (!proc || proc->n_pmp == 0)
    # #   return true;
    # for i in range(proc->n_pmp):
    #   # Check each 4-byte sector of the access
    #   any_match = False
    #   all_match = True
    #   for offset in range(len, -1, (1<<PMP_SHIFT) ):#doubt
    #     curr_addr = addr + offset
    #     match = proc->state.pmpaddr[i]->match4(curr_addr);
    #     any_match |= match;
    #     all_match &= match; 
      
    #   if (any_match):
    #     #If the PMP matches only a strict subset of the access, fail it
    #     if not all_match:
    #       return False
    #     return proc->state.pmpaddr[i]->access_ok(type, mode)
    
    # return mode == PRV_M
    

  """stage 2 translation or g stage translation"""
  def s2xlate(self, gva, gpa, type:Access_Type, trap_type:Access_Type, virt:bool, hlvx:bool) :
    gva = uint64(gva)
    gpa = uint64(gpa)
    virt = bool(virt)
    hlvx = bool(hlvx)
    log.info("[2] stage 2 translation callled------------------------")
    
    if (not virt):
      return gpa
    log.info("[2] gva: {}".format(hex(gva)))
    log.info("[2] gpa: {}".format(hex(gpa)))
    log.info("[2] virt: {}".format(hex(virt)))
    log.info("[2] hlvx: {}".format(hex(hlvx)))
    log.info("[2] hgatp: {}".format(hex(self.hgatp)))
    vm = decode_vm_info(self.xlen, True, 0, self.hgatp)
    log.info("[2] vm:{}".format(vm))
    if vm.levels == 0 :
      log.info("[2] inside vm.level = 0 ")
      log.info("[2] gpa:{}".format(hex(gpa)))
      return gpa
    maxgpabits = vm.levels * vm.idxbits + vm.widenbits + PGSHIFT
    maxgpa = (1 << maxgpabits) - 1 # maxgpa is uint64
    # mxr = bool(self.mstatus & MSTATUS_MXR)
    mxr = self.mxr

    base = vm.ptbase
    log.info("[2] base: {} ".format(hex(base)))
    if((gpa & (not maxgpa) == 0)):
      log.info("[2] gpa & !maxgpa")
      for i in range((vm.levels -1) , -1, -1):
        log.info("[2] loop i: {}".format(i))
        ptshift = i*vm.idxbits
        idxbits = (vm.idxbits + vm.widenbits) if (i == (vm.levels -1)) else vm.idxbits
        idx = (gpa >> (PGSHIFT + ptshift)) & (((1) << idxbits) - 1)
        log.info("[2] idx: {}".format(hex(idx)))
        
        # checking the physical address of PTE is legal
        pte_paddr = base + idx * vm.ptesize
        log.info("[2] pte_paddr: {}".format(hex(pte_paddr)))
        pte = mem_access(pte_paddr)
        if pte == -1 :
          log.info("[2] wrong")
          break
        # pte_paddr = base + idx * vm.ptesize
        # ppte = mem_request(pte_paddr)#TODO: check for the address to legal
        # if (not ppte) or (not self.pmp_ok(pte_paddr, vm.pteseize, Access_Type.LOAD, PRV_S)):
        #   self.throw_access_exception(virt, gva, trap_type)
        
        # #here is the mem access probably
        # pte = vm.ptesize == 4 ? from_target(*(target_endian<uint32_t>*)ppte) : from_target(*(target_endian<uint64_t>*)ppte)
        ppn = (pte & ~(PTE_ATTR)) >> PTE_PPN_SHIFT
        log.info("[2] pte: {}".format(hex(pte)))
        log.info("[2] ppn: {}".format(hex(ppn)))
        log.info("[2] doing permission checks")
        log.info(f"[2] permission bits D:{pte & PTE_D} A:{pte & PTE_A} G:{pte & PTE_G} U:{pte & PTE_U} X:{pte & PTE_X} W:{pte & PTE_W} R:{pte & PTE_R} V:{pte & PTE_V}")
        #permission check 
        if pte & PTE_RSVD :
          log.warning("[2] falied permission due to reserved check")
          break
        elif ((not self.svnapot) and (pte & PTE_N)) :
          log.warning("[2] falied permission due to !svnapot and N check")
          break
        elif ((not self.svnapot) and (pte & PTE_PBMT)):
          log.warning("[2] falied permission due to !svnapot and pbmt check")
          break
        elif (PTE_TABLE(pte)):# next level of page table
          if (pte & (PTE_D | PTE_A | PTE_U | PTE_N | PTE_PBMT)):
            log.warning("[2] falied permission due to next level page but D|A|U|N|PBMT set check")
            break
          log.info("[2] pointer to next page found")
          base = ppn << PGSHIFT
        elif ((not (pte & PTE_V)) or ((not (pte & PTE_R)) and (pte & PTE_W))) :
          log.warning("[2] falied permission due to !v | !r & w check")
          break
        # elif (pte & PTE_U):
        #   if (s_mode and (type == FETCH or (not sum))):
        #     break
        # elif (not s_mode):
        #   break
        # elif (not (pte & PTE_V) or (not (pte & PTE_R) and (pte & PTE_W))):
        #   break
        elif ((not (pte & PTE_U))) :
          log.warning("[2] falied permission due to !U check")
          break
        elif ((type == Access_Type.FETCH) or (hlvx)) and (not (pte & PTE_X)):
          log.warning("[2] falied permission due to fetch and !X check")
          break
        elif ((type == Access_Type.LOAD) and ((not (pte & PTE_R)) and (not (mxr and (pte & PTE_X))))):
          log.warning("[2] falied permission due to load and !r and !mxr and X  check")
          break
        elif (type == Access_Type.STORE)and (not (pte & PTE_R)) and (pte & PTE_W):
          log.warning("[2] falied permission due to !R and W check")
          break
        elif ((ppn & (((1) << ptshift) - 1)) != 0) :
          log.warning("[2] falied permission due to mis-alligned check")
          log.info(hex((ppn & (((1) << ptshift) - 1)) != 0))
          break
        else :
          log.info("[2] leaf node found")
          ad = PTE_A | ((type == Access_Type.STORE) * PTE_D)
          if RISCV_ENABLE_DIRTY: #ifdef RISCV_ENABLE_DIRTY all yhe macro are set ot false
            # set accessed and possibly dirty bits.
            # if ((pte & ad) != ad):
            #   if not (self.pmp_ok(pte_paddr, vm.ptesize, Access_Type.STORE, PRV_S)):
            #     self.throw_access_exception(virt, gva, trap_type)
            #   *(target_endian<uint32_t>*)ppte |= to_target((uint32_t)ad)
            pass
          else:#else of ifdef
            # take exception if access or possibly dirty bit is not set.
            if ((pte & ad) != ad):
              log.warning("[2] falied due to a & d bits")
              break
          #endif
          
          vpn = gpa >> PGSHIFT;
          page_mask = ((1) << PGSHIFT) - 1;

          napot_bits = (self.ctz(ppn) + 1) if (pte & PTE_N) else 0
          if (((pte & PTE_N) and (ppn == 0 or i != 0)) or (napot_bits != 0 and napot_bits != 4)):
            break

          page_base = ((ppn & ~(((1) << napot_bits) - 1)) | (vpn & (((1) << napot_bits) - 1)) | (vpn & (((1) << ptshift) - 1))) << PGSHIFT
          log.info(f"[2] return the leaf page translation :{hex(page_base | (gpa & page_mask))} offset:{(gpa & page_mask)}")
          return (page_base | (gpa & page_mask))
    
    if trap_type == Access_Type.FETCH:
      raise Exception("Instruction guest page fault")
    elif trap_type == Access_Type.LOAD:
      raise Exception("Load guest page fault")
    elif trap_type == Access_Type.STORE:
      raise Exception("Store guest page fault")
    
    

  def walk (self, addr, type:Access_Type, mode, virt:bool, hlvx:bool):
    log.info("[1] inside walk")
    addr = uint64(addr)
    # mode = uint64(mode)
    virt = bool(virt)
    hlvx = bool(hlvx)
    type = Access_Type(type)
    log.info("[1] stage 1 translation callled------------------------")
    log.info("[1] addr: {}".format(hex(addr)))
    log.info("[1] type: {}".format(type))
    log.info("[1] mode: {}".format((mode)))
    log.info("[1] hlvx: {}".format(hex(hlvx)))
    log.info("[1] virt: {}".format(hex(virt)))
    page_mask = ((1)<< PGSHIFT) -1
    satp = self.vssatp if virt else self.satp  #DOUBT read here mostly vssatp for our purpose
    log.info("[1] satp: {}".format(hex(satp)))
    vm = decode_vm_info(self.xlen, False, mode, satp)
    log.info("[1] vm:{}".format(vm))
    
    if vm.levels == 0:
      log.info("[1] inside vm.level = 0 ")
      trans = (self.s2xlate(addr, addr & (((2) << (self.xlen-1))-1), type, type, virt, hlvx)) & (not page_mask)
      log.info("[1] no translation: {}".format(hex(trans)))
      return (trans)
    s_mode = True if mode==PRV_S else False
    #sum = bool(self.mstatus & MSTATUS_SUM) #sum value is taken based on wheather virtulization is true or not
    #mxr = bool(self.mstatus & MSTATUS_MXR) #doubt status should be read according to virtulization mode and or together
    sum = self.sum
    mxr = self.mxr

    # verify bits xlen-1:va_bits-1 are all equal
    va_bits = PGSHIFT + vm.levels * vm.idxbits
    mask = ((1) << (self.xlen - (va_bits -1))) - 1
    masked_msbs = (addr >> (va_bits -1)) & mask
    if (masked_msbs != 0 and masked_msbs != mask):
      vm.levels = 0
    
    base = vm.ptbase# mostly here the vssatp
    log.info("[1] base: {} ".format(hex(base)))
    for i in range((vm.levels-1), -1, -1):
      log.info("[1] loop i: {}".format(i))
      ptshift = i*vm.idxbits
      idx = (addr >> (PGSHIFT + ptshift)) & ((1 << vm.idxbits) - 1)
      log.info("[1] idx: {}".format(hex(idx)))      
      # checking the physical address of PTE is legal
      pte_paddr = self.s2xlate(addr, base + idx * vm.ptesize, type, type, virt, False)
      log.info("[1] pte_paddr: {}".format(hex(pte_paddr)))
      pte = mem_access(pte_paddr)
      if pte == -1 :
        log.info("[1] wrong")
        break
      # ppte = mem_request(pte_paddr)#TODO: check for the address to legal
      # if (not ppte) or (not pmp_ok(pte_paddr, vm.pteseize, Access_Type.LOAD, PRV_S)):
      #   self.throw_access_exception(virt, addr, type)

      # pte = vm.ptesize == 4 ? from_target(*(target_endian<uint32_t>*)ppte) : from_target(*(target_endian<uint64_t>*)ppte)
      ppn = (pte & ~(PTE_ATTR)) >> PTE_PPN_SHIFT
      log.info("[1] pte: {}".format(hex(pte)))
      log.info("[1] ppn: {}".format(hex(ppn)))
      log.info("[1] doing permission checks")
      log.info(f"[1] permission bits D:{pte & PTE_D} A:{pte & PTE_A} G:{pte & PTE_G} U:{pte & PTE_U} X:{pte & PTE_X} W:{pte & PTE_W} R:{pte & PTE_R} V:{pte & PTE_V}")
      #permission check 
      if pte & PTE_RSVD :
        log.warning("[1] falied permission due to reserved check")
        break
      elif ((not self.svnapot) and (pte & PTE_N)) :
        log.warning("[1] falied permission due to !svnapot and N check")
        break
      elif ((not self.svnapot) and (pte & PTE_PBMT)):
        log.warning("[1] falied permission due to !svnapot and pbmt check")
        break
      elif (PTE_TABLE(pte)):# next level of page table
        if (pte & (PTE_D | PTE_A | PTE_U | PTE_N | PTE_PBMT)):
          log.warning("[1] falied permission due to next level page but D|A|U|N|PBMT set check")
          break
        log.info("[1] pointer to next page found")  
        base = ppn << PGSHIFT
        log.info(f"[1] base inside permission checks {hex(base)}")
      elif ((not (pte & PTE_V)) or ((not (pte & PTE_R)) and (pte & PTE_W))) :
        log.warning("[1] falied permission due to !v | !r & w check")
        break
      elif (pte & PTE_U) and (s_mode and (type == Access_Type.FETCH or (not sum))) :
        log.warning("[1] falied permission due to U and sum bit check")
        break
      elif not (pte & PTE_U) and (not s_mode):
        log.warning("[1] falied permission due to !U and not s mode bit check")
        break
      elif (not (pte & PTE_V) or (not (pte & PTE_R) and (pte & PTE_W))):
        log.warning("[1] falied permission due to !V | !r and !W check")
        break
      # elif ((not (pte & PTE_U))) :
      #   break
      elif ((type == Access_Type.FETCH) or (hlvx)) and (not (pte & PTE_X)):
        log.warning("[1] falied permission due to fetch and !X check")
        break
      elif ((type == Access_Type.LOAD) and ((not (pte & PTE_R)) and (not (mxr and (pte & PTE_X))))):
        log.warning("[1] falied permission due to load and !r and !mxr and X  check")
        break
      elif (type == Access_Type.STORE)and (not (pte & PTE_R)) and (pte & PTE_W):
        log.warning("[1] falied permission due to !R and W check")
        break
      elif ((ppn & (((1) << ptshift) - 1)) != 0) :
        log.warning("[1] falied permission due to mis-alligned check")
        log.info(hex((ppn & (((1) << ptshift) - 1)) != 0))
        break
      else:
        log.info("[1] leaf node found")
        ad = PTE_A | ((type == Access_Type.STORE) * PTE_D)
        if RISCV_ENABLE_DIRTY: #ifdef RISCV_ENABLE_DIRTY all yhe macro are set ot false
          # set accessed and possibly dirty bits.
          pass
          # if ((pte & ad) != ad):
          #   if not (pmp_ok(pte_paddr, vm.ptesize, Access_Type.STORE, PRV_S)):
          #     self.throw_access_exception(virt, gva, trap_type)
          #   *(target_endian<uint32_t>*)ppte |= to_target((uint32_t)ad)
        
        else:#else of ifdef
          # take exception if access or possibly dirty bit is not set.
          if ((pte & ad) != ad):
            log.warning("[1] falied due to a & d bits")
            break
        #endif
        vpn = addr >> PGSHIFT
        page_mask = ((1) << PGSHIFT) - 1;

        napot_bits = (self.ctz(ppn) + 1) if (pte & PTE_N) else 0
        if (((pte & PTE_N) and (ppn == 0 or i != 0)) or (napot_bits != 0 and napot_bits != 4)):
          break

        page_base = ((ppn & ~(((1) << napot_bits) - 1)) | (vpn & (((1) << napot_bits) - 1)) | (vpn & (((1) << ptshift) - 1))) << PGSHIFT
        phys = page_base | (addr & page_mask)
        log.info("[1] return the leaf page translation :")
        return self.s2xlate(addr, phys, type, type, virt, hlvx) & ~page_mask
    
    if type == Access_Type.FETCH:
      raise Exception("Instruction page fault")
    elif type == Access_Type.LOAD:
      raise Exception("Load page fault")
    elif type == Access_Type.STORE:
      raise Exception("Store page fault")
    
        
  
  def translate(self, addr, len, type:Access_Type, xlate_flags) -> np.uint64:
    # if (!proc)
    #   return addr;
    addr = uint64(addr)
    len = uint64(len)
    xlate_flags = uint32(xlate_flags)
    
    virt = bool(self.v) #this is where the doubt arise how will i control the state v
    hlvx = bool(xlate_flags & RISCV_XLATE_VIRT_HLVX)
    mode = uint64(self.prv) #reg_t mode = proc->state.prv;
    if type != Access_Type.FETCH:
      if((True) and get_field(self.mstatus, MSTATUS_MPRV)):
        mode = get_field(self.mstatus, MSTATUS_MPP)
        if (get_field(self.mstatus, MSTATUS_MPV) and mode != PRV_M):
          virt = True
      if (xlate_flags & RISCV_XLATE_VIRT):
        virt = True
        mode = get_field(self.hstatus, HSTATUS_SPVP)
    
    paddr = uint64(self.walk(addr, self.access, mode, True, False)) | uint64(addr & (PGSIZE-1))
    if ((not self.pmp_ok)):
      self.throw_access_exception(virt, addr, type)
    return paddr
    
# class vm_info: 
#   #init method or constructor 
#   def __init__(self):
#     self.levels = 0 
#     self.idxbits = 0
#     self.widebits = 0
#     self.ptesize = 0
#     self.ptbase = 0 
  
#   def decode_vm_info(self, xlen, stage2, priv, satp):
#     pass
#1 INFO:root:req:0x90000010 res:0x90001"
#2 INFO:root:req:0x90001000 res:0x90002"
#3 INFO:root:req:0x90002000 res:0x90003"
  #4 INFO:root:req:0x90003000 res:0x80001"
#5 INFO:root:req:0x90000010 res:0x90001"
#6 INFO:root:req:0x90001000 res:0x90002"
#7 INFO:root:req:0x90002008 res:0x90004"
  #8 INFO:root:req:0x90004000 res:0x80002"
#9 INFO:root:req:0x90000010 res:0x90001"
#10 INFO:root:req:0x90001000 res:0x90002"
#11 INFO:root:req:0x90002010 res:0x90005"
  #12 INFO:root:req:0x90005000 res:0x80003"
#13 INFO:root:req:0x90000010 res:0x90001"
#14 INFO:root:req:0x90001000 res:0x90002"
#15 INFO:root:req:0x90002018 res:0x90006"
  #16 INFO:root:req:0x90006ff8 res:0x80004

# def mmu_model(vir_addr, mode, access, hlvx):
#   # access error i think currently using the default access which is 
#   # machine access hence it should throw a fault access in stage 2 which it is not 
#   # doing
#   mmu_t = Mmu_t()
#   paddr = mmu_t.translate(vir_addr, mode, access, hlvx)
#   return paddr
  

mmu_t = Mmu_t()
paddr = mmu_t.translate(0x123456a, 8, mmu_t.access, 1)
log.info(hex(paddr))
decode_vm_info(mmu_t.xlen, True, 0, mmu_t.hgatp)