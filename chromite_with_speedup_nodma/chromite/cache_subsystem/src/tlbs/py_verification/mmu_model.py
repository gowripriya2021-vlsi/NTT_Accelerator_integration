from refence_spike import *

# mmu_t = Mmu_t()
# paddr = mmu_t.translate(0x123456a, 8, mmu_t.access, 1)
# log.info(hex(paddr))
def python_ref_model(vir_addr, mode, access, hlvx):
  paddr = mmu_model(vir_addr, mode, access, hlvx)
  return paddr