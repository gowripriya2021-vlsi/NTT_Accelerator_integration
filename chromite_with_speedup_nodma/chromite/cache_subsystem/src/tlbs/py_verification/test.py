def rg(value, i):
  return (value *(2**i))

mv= rg(8,60)|rg(0x80_000_000,0) 
print(bin(mv))

for i in range(2, -1, -1):
  print(i)

def uint64(x):
  return (x & ((2**64) -1))

def print_vpn_segment(addr):
  addr = uint64(addr)
  print(bin(addr))
  offset_mask = 0xfff
  vpn0_mask = (((1<<9)-1) << (12))
  print(bin(vpn0_mask))
  vpn1_mask = (((1<<9)-1) << (12+9))
  print(bin(vpn1_mask))
  vpn2_mask = (((1<<9)-1) << (12+9*2))
  print(bin(vpn2_mask))
  print(f"vpn[2]:{hex(addr & vpn2_mask)} vpn[1]:{hex(addr & vpn1_mask)} vpn[0]:{hex(addr & vpn0_mask)} offset:{hex(addr & offset_mask)}")

print_vpn_segment(0x123456a)
valid_bit = 0x01
read_bit = 0x02
write_bit = 0x04
execute_bit = 0x08
u_bit_s = 0x00
u_bit_u = 0x10
global_bit = 0x20
access_bit = 0x40
dirty_bit = 0x8
ma = 1<<10 | dirty_bit | access_bit | \
    global_bit | u_bit_s | 0x00 | write_bit | \
    0x00 | valid_bit
print(hex(ma))
if (1==1):
  raise Exception("yo")