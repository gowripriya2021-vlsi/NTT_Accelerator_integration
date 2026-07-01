// ntt_kyber_hw.h - Enhanced version with burst geometry tracking
#ifndef NTT_KYBER_HW_H
#define NTT_KYBER_HW_H

#include <stdint.h>

#define NTT_HW_MAX_CALLS 256

/*
 * Burst geometry — single source of truth.
 * BURST_LEN must be <= xactor FIFO depth (16) to avoid stalls.
 * NUM_BURSTS covers all HW_N=256 coefficients exactly.
 * All prints derive from these; nothing is hardcoded in test bench.
 */
#define NTT_HW_N            256
#define NTT_HW_BURST_LEN    16
#define NTT_HW_NUM_BURSTS   (NTT_HW_N / NTT_HW_BURST_LEN)   /* = 16 */

/* Per-NTT call detailed stats */
typedef struct {
    uint32_t call_no;
    uint64_t total_cycles;          /* Full function call                  */
    uint64_t total_instrs;
    uint64_t pack_cycles;           /* pack_data_in only                   */
    uint64_t pack_instrs;
    uint64_t start_write_cycles;    /* Writing START bit                   */
    uint64_t compute_cycles;        /* Polling DONE (hardware compute)     */
    uint64_t compute_instrs;
    uint64_t unpack_cycles;         /* unpack_data_out only                */
    uint64_t unpack_instrs;
    uint64_t axi_write_cycles;      /* AXI write transactions only         */
    uint64_t axi_read_cycles;       /* AXI read transactions only          */
    uint32_t axi_write_count;       /* Total write beats (= NTT_HW_N)     */
    uint32_t axi_read_count;        /* Total read beats  (= NTT_HW_N)     */
    uint32_t axi_write_bursts;      /* Number of write bursts issued       */
    uint32_t axi_read_bursts;       /* Number of read bursts issued        */
    uint32_t axi_beats_per_burst;   /* Beats per burst (= NTT_HW_BURST_LEN) */
} ntt_call_detail_t;

typedef struct {
    uint32_t total_calls;
    uint64_t total_cycles;
    uint64_t total_instrs;
    uint64_t min_cycles;
    uint64_t max_cycles;
    uint64_t total_axi_write_cycles;
    uint64_t total_axi_read_cycles;
    uint64_t total_compute_cycles;
    uint32_t total_axi_writes;          /* Total write beats across all calls  */
    uint32_t total_axi_reads;           /* Total read beats across all calls   */
    uint32_t total_axi_write_bursts;    /* Total write bursts across all calls */
    uint32_t total_axi_read_bursts;     /* Total read bursts across all calls  */
    ntt_call_detail_t log[NTT_HW_MAX_CALLS];
} ntt_hw_stats_t;

/* Global stats */
extern ntt_hw_stats_t g_ntt_hw_stats;

/* Function declarations */
void ntt_hw_stats_reset(void);
void ntt_kyber_hw_drive(int16_t poly[256]);

#endif
