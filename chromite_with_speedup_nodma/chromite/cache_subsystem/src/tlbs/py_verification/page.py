"""""
  see LICENSE.incore
  see LICENSE.iitm

  Author: Shubham Roy, Neel Gala
  Email id: [shubham.roy, neelgala]@incoresemi.com
  Details: genetrate two list one containg the memory address that will get call and 
          another will contain the response that index will conrresponds

  --------------------------------------------------------------------------------------------------
"""
#TODO: init mem for 4KiB page
import array as arr
import logging as log
import numpy as np
from dataclasses import dataclass
log.basicConfig(level=log.INFO)

# generate the address for translation 
def get_mem_add(vir_add):
  vssatp = 0x80_000_000
  hgatp = 0x90_000_000
  DDR = 0x70_000_000
  sv39= 0x00_000_000
  vir_add = '{:039b}'.format(vir_add)
  log.info((vir_add))
  vpn = [vir_add[i:i+9] for i in range(0, len(vir_add), 9)]
  # for i in range(0, len(vir_add), 9):
  #   vpn[i] = vir_add[i+9:i]
  log.info((vpn)) 


def read_memory(addr):
  """
  return the hex value 
  """
  return addr

def print_pattern (left, right)  :
  """
  helper function to print the values inside a list in a readable manner
  it is used to print the memory request list in conjunction with memory response in
  such a way that helps user
  """
  for i in range(len(left)):
    log.info('i:{} req:{} res:{}"'.format(i+1, hex(left[i]), hex(right[i])))

def mem_list_gen (config_string, vssatp, hgatp, virtual_address):
  """
  Generates all the memory request and their responses 
  Inputs:
    config_string : this string specifies the what depth of translation happen in each stage
    for example "131313130" the first '1' virtual address will have a stage 1 translation 
                            second '3' tell the translated stage 1 will have 3 level stage 2 translation 
                            similarly next 13,13 pair
                            the last '130' marks the end of the translation '3' tells after adding page offset
                            in stage1 it will have 3 level stage2 translation '0' maks the end of all the translation 
    vssatp: value of CSR VSSATP in hex format
    hgatp: value of HGATP in hex format
    virtual_address : the virtual address whoses translation the ptwalk is performing or the GVA
  Outputs:
    two list 'left_list' containing all the memory call 'right_list' containing all the coresponding meme response

  """
  # subvpn = [0x1ff_000_000, 0x_00]                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   000_000]
  left_case = []
  right_case = []
  vssatp_h = read_memory(vssatp)
  hgatp_h = read_memory(hgatp)
  # ddr_h = read_memory(ddr)
  virtual_address_h = read_memory(virtual_address)
  level_vs = 2
  level_g = 2
  add =vssatp_h;
  for pos, i in enumerate(str(config_string)):
    # add =vssatp_h
    if (i == '1') & (pos%2 == 0):
      log.info("yo--------------------1")
      add = ((add >> 12 )<<12) | ((virtual_address_h >> (12+9*level_vs))& ((1 << 9) - 1))<<3
      log.info(hex(add))
      add2 = add
      # if level_vs == 0:
      #   add = ((add >> 12 )<<12) | (virtual_address_h & 0xfff)  
      level_vs = level_vs -1
    elif (i != '0') & (pos%2 != 0):
      log.info("yo--------------------2")
      level_g =2
      mem_r = hgatp_h
      for j in range(int(i)): 
        log.info(j)       
        mem_l= ((mem_r >>12)<<12) | (((add & ((1<<9)-1)<<(12+9*level_g)) >> (12+9*level_g))<<3)
        # log.info(hex(add & ((1<<3)-1)<<21))
        left_case.append(mem_l)
        if level_g ==0:
          mem_r = ((hgatp_h >>12) +j+1+((add & (0xfff<<12))>>12))<<12
        else:
          mem_r = ((hgatp_h >>12) +j+1)<<12
        # log.info(hex((add & (0xfff<<12))>>12))
        if j==(int(i)-1):
          mul = 1 if i ==2 else 2
          mem_r = (mem_r>>12+9*mul)<<12+9*mul
          right_case.append(mem_r>>12)
        else:
          right_case.append(mem_r>>12)
        if(level_g == 0):
          mem_l = (((mem_r >>12))<<12) | (add & 0xfff)
          left_case.append(mem_l)
          t = ((vssatp_h >> 12) +(2-level_vs))<<12
          right_case.append(t>>12)
        elif j==(int(i)-1):
          mem_l = ((mem_r >> (12+9*level_g))<<(12+9*level_g)) | (add & ((1<<(12+9*level_g))-1))
          # log.info('h:{} h2:{} h3:{} l:{}"'.format(hex(mem_r ), hex(mem_r >> (12+9*level_g)), hex((mem_r >> (12+9*level_g))<<(12+9*level_g)), hex((add & (1<<(13+9*level_g)-1)))))
          left_case.append(mem_l)
          t = ((vssatp_h >> 12) +(2-level_vs))<<12
          right_case.append(t>>12)
        level_g = level_g -1
      add = ((vssatp_h >>12) +(2-level_vs))<<12
        
        
    elif i =='0' :
      log.info("yo--------------------3")
      # log.info([hex(x) for x in left_case])
      # log.info([hex(x) for x in right_case])
      return left_case, right_case
      # log.info_pattern(left_case, right_case)
  # add =((vssatp_h >>12) +1+pos)<<12
  log.info(hex(add))
    
    


# #takes in the address and returns the corresponding index in the array
# def mem_add_to_index:
# #takes the address of the memory and returns the data corresponding to it
# def mem_data:
a = []
# a = memory_init(a)
# def ctz(n):
#   for i in range(20):
#       if n % (2<<i) != 0:
#           return i
# a = 10 
# log.info(bin(a))
# log.info(ctz(a))
# for i in range(2-1, -1, -1):
#   log.info(i)
vir_add = 0x123456a
config_str = 121112130
# get_mem_add(vir_add)
# mem_list_gen(131313130, 0x80_000_000, 0x90_000_000, 0x00_000_fff)
# mem_list_gen(131313130, 0x80_000_000, 0x90_000_000, 0x00_000_fff)
# mem_list_gen(131313130, 0x80_000_000, 0x90_000_000, 0x00_000_fff)
left_list, right_list = mem_list_gen(config_str, 0x80_000_000, 0x90_000_000, vir_add)
# mem_list_gen(121113130, 0x80_000_000, 0x90_000_000, 0x00_000_fff)
# for i in range(11):
#     log.info(hex(a[i]))
print_pattern(left_list, right_list)
def adding_permission_bits(config_str, list):
  """
  fuction to add premission to the memory resoponse of so to make them PTE
  Input:
    config_str: same explanation as in mem_list_gen, here it is use to tell page is leaf or not
                or the page size
    list: list of memory responses that only have the ppn values and need the permissions bits 
          to be added as to make them a complete PTE
  Output:
    list containg all the PTEs
  """
  x=0
  config_str = str(config_str)
  for pos, i in enumerate((config_str)):
    # all bits other than U bit will be set by default
    valid_bit = 0x01
    read_bit = 0x02
    write_bit = 0x04
    execute_bit = 0x08
    u_bit_s = 0x00
    u_bit_u = 0x10
    global_bit = 0x20
    access_bit = 0x40
    dirty_bit = 0x80
    if (i == '1') & (pos%2 == 0):
      # 3+1 translation permission bits add here
      t = int(config_str[pos+1])
      for k in range(t-1):
        """list[x] | dirty_bit | access_bit | \
            global_bit | u_bit_u | execute_bit | write_bit | \
            read_bit | valid_bit

        2    
        """
        print(f"[2] non-leaf x:{x}")
        #non leaf in second stage
        list[x] = (list[x] << 10) | 0x00 | 0x00 | \
                  global_bit | u_bit_s | 0x00 | 0x00 | \
                  0x00 | valid_bit
        log.info("addr:{}  hexo:{}".format(hex(list[x]>>10), hex(list[x])))
        x += 1
      #leaf in second stage 
      """1"""
      print(f"[2] leaf x:{x}")
      list[x] = (list[x] << 10) | dirty_bit | access_bit | \
                global_bit | u_bit_u | execute_bit | write_bit | \
                read_bit | valid_bit
      log.info("addr:{}  hexo:{}".format(hex(list[x]>>10), hex(list[x])))          
      x +=1
      if(config_str[pos + 2] == '0'):
        #leaf translation for stage 1
        """1"""
        print(f"[1] dont know what will the permission x:{x}")
        list[x] = (list[x] << 10) | dirty_bit | access_bit | \
                global_bit | u_bit_s | execute_bit | write_bit | \
                read_bit | valid_bit 
        log.info("addr:{}  hex:{}".format(hex(list[x]>>10), hex(list[x])))        
        return list       
      elif (config_str[pos + 2] == '1'):
        #leaf pointer 1st stage
        if(config_str[pos + 4] == '0'):
          print(f"[1] leaf x:{x}")
          list[x] = (list[x] << 10) | dirty_bit | access_bit | \
                    global_bit | u_bit_u | execute_bit | write_bit | \
                    read_bit | valid_bit 
          x += 1
        else:
          #pointer to next level in 1 st stage
          """1""" 
          print(f"[1] non-leaf x:{x}")
          list[x] = (list[x] << 10) | 0x00 | 0x00 | \
                    global_bit | u_bit_s | 0x00 | 0x00 | \
                    0x00 | valid_bit
          log.info("addr:{}  hex:{}".format(hex(list[x]>>10), hex(list[x])))
          x+=1
          
right_list=adding_permission_bits(config_str, right_list)           
print_pattern(left_list, right_list)
# def print_list(list):
#   for i in range(len(list)):
#     list[i] = list[i] >>10 
#     print(hex(list[i]))

# print_list(right_list)     
mem_access_call = 0
def mem_access(addr):
  """
  keep track of the memory access as well as send the response of a memory call
  
  """
  global mem_access_call
  log.info(f"[MEM] mem access call:{mem_access_call +1} ")
  addr_frm_list = left_list[mem_access_call]
  if addr != addr_frm_list:
    log.info("[MEM] addr:{}  addr_frm_list:{}".format(hex(addr), hex(addr_frm_list)))
    log.info("[MEM] failure")
    return -1
  else :
    mem_access_call += 1
    return right_list[mem_access_call-1]
  
  

# def uint64(x):
#   return (x & ((2**64) -1))

# print(bin(uint64(184467440737095516166)))