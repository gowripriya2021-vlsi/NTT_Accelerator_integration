/*
 * ntt_kyber_hw.c  —  Rev 7
 *
 * Address map (NTTAXI4.bsv):
 *   BASE + 0x000  CONTROL   bit[0]=START bit[1]=INVERSE bit[2]=BUSY bit[3]=DONE
 *   BASE + 0x004  STATUS    op count (read-only)
 *   BASE + 0x400  DATA_IN   element i at BASE+0x400+4*i
 *   BASE + 0xC00  DATA_OUT  element i at BASE+0xC00+4*i
 *
 * Bus: 64-bit AXI fabric, but IO path issues single-beat 32-bit transactions.
 * isIO() fix in io_func.bsv ensures CPU uses IO path (no cache bursts).
 * Simple 32-bit volatile accesses are correct for IO path.
 */

#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "params.h"
#include "ntt_kyber_hw.h"

#define HW_N            256
#define HW_Q            3329

#define HW_BASE_ADDR    0x00011400UL
#define HW_REG_CTRL     (HW_BASE_ADDR + 0x000)
#define HW_REG_STATUS   (HW_BASE_ADDR + 0x004)
#define HW_REG_DATA_IN  (HW_BASE_ADDR + 0x400)
#define HW_REG_DATA_OUT (HW_BASE_ADDR + 0xC00)

/* Control register bit layout — must match NTTAXI4.bsv exactly:
 *   bit 0 = START   (write 1 to begin; write 0 to return DONE->IDLE)
 *   bit 1 = INVERSE (unused — forward-only core)
 *   bit 2 = BUSY    (LOADING or RUNNING state)
 *   bit 3 = DONE    (NTT complete, output valid)
 *
 * Original code had CTRL_DONE=(1<<2) which is BUSY, not DONE.
 * That caused the poll loop to exit as soon as LOADING began —
 * reading stale output before the NTT had even started.
 */
#define CTRL_START      (1u << 0)
#define CTRL_BUSY       (1u << 2)
#define CTRL_DONE       (1u << 3)

/* Simple 32-bit IO accessors — IO path is single-beat, no burst issues */
static inline void hw_write32(uint32_t addr, uint32_t val)
{
    *((volatile uint32_t *)addr) = val;
 //   __asm__ volatile ("fence rw,rw" ::: "memory");
}

static inline uint32_t hw_read32(uint32_t addr)
{
    uint32_t v = *((volatile uint32_t *)addr);
   // __asm__ volatile ("fence" ::: "memory");
    return v;
}

static void pack_data_in(const int16_t poly[HW_N])
{
    for (int i = 0; i < HW_N; i++) {
        uint16_t c = (uint16_t)(((int32_t)poly[i] % HW_Q + HW_Q) % HW_Q);
        hw_write32(HW_REG_DATA_IN + i * 4, (uint32_t)c);
    }
}

static void unpack_data_out(int16_t poly[HW_N])
{
    for (int i = 0; i < HW_N; i++) {
        uint32_t word = hw_read32(HW_REG_DATA_OUT + i * 4);
        poly[i] = (int16_t)(word & 0xFFFF);
    }
}

void ntt_kyber_hw_drive(int16_t poly[HW_N])
{
    static int call_count = 0;
    call_count++;
    uintptr_t sp_val;
    __asm__ volatile ("mv %0, sp" : "=r"(sp_val));
    //printf("[HW] sp=0x%lx\r\n", sp_val);
   // fflush(stdout);
    //printf("[HW#%d] in[0]=%d in[1]=%d\r\n", call_count, poly[0], poly[1]);
  //  fflush(stdout);

    /* Step 1: write all coefficients */
    pack_data_in(poly);
    //printf("[HW#%d] pack done\r\n", call_count);
   // fflush(stdout);

    /* Step 2: assert START */
    hw_write32(HW_REG_CTRL, CTRL_START);
    //printf("[HW#%d] START asserted CTRL=0x%x\r\n",
          // call_count, hw_read32(HW_REG_CTRL));
   // fflush(stdout);

    /* Step 3: poll DONE bit in CONTROL register */
    int timeout = 0;
    uint32_t ctrl_val;
    while (1) {
        ctrl_val = hw_read32(HW_REG_CTRL);
        if (ctrl_val & CTRL_DONE) break;
        timeout++;
        if (timeout == 10000) {
      //      printf("[HW#%d] waiting... CTRL=0x%x STATUS=0x%x\r\n",
        //           call_count, ctrl_val, hw_read32(HW_REG_STATUS));
           // fflush(stdout);
        }
        if (timeout >= 1000000) {
            //printf("[HW#%d] TIMEOUT CTRL=0x%x STATUS=0x%x\r\n",
              //     call_count, ctrl_val, hw_read32(HW_REG_STATUS));
           // fflush(stdout);
            return;
        }
    }
  //  printf("[HW#%d] DONE iter=%d CTRL=0x%x\r\n", call_count, timeout, ctrl_val);
   // fflush(stdout);

    /* Step 4: de-assert START immediately (DONE->IDLE transition in BSV FSM).
     * Must happen before unpack_data_out so the FSM is idle before next call.
     * Without this, the next call's START=1 write may race with DONE state. */
    hw_write32(HW_REG_CTRL, 0u);
    __asm__ volatile ("fence w,w" ::: "memory");

    /* Step 5: read results */
    unpack_data_out(poly);
    //printf("[HW#%d] out[0]=%d out[1]=%d\r\n", call_count, poly[0], poly[1]);
    //fflush(stdout);
}
