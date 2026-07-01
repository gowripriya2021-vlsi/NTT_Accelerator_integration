/*
 * test_kyber_enhanced.c — Enhanced Kyber test bench with detailed per-NTT,
 * per-AXI transaction, per-burst, and per-function call profiling.
 * No values are hardcoded in prints — all derived from live counters
 * and header-defined geometry constants.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../kem.h"
#include "../randombytes.h"
#include "ntt_kyber_hw.h"

#ifndef CPU_HZ
#  define CPU_HZ 50000000
#endif

#define NTESTS 1

/* ------------------------------------------------------------------ */
/* Global buffers                                                      */
/* ------------------------------------------------------------------ */
static uint8_t g_seed[64];
static uint8_t g_pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t g_sk[CRYPTO_SECRETKEYBYTES];
static uint8_t g_ct[CRYPTO_CIPHERTEXTBYTES];
static uint8_t g_key_a[CRYPTO_BYTES];
static uint8_t g_key_b[CRYPTO_BYTES];

/* ------------------------------------------------------------------ */
/* Per-function call profiling                                         */
/* ------------------------------------------------------------------ */
typedef struct {
    const char* name;
    uint64_t cycles;
    uint64_t instrs;
    uint32_t call_count;
} function_stats_t;

#define MAX_FUNCTIONS 20
static function_stats_t g_func_stats[MAX_FUNCTIONS];
static uint32_t g_num_functions = 0;

static function_stats_t* find_or_add_func(const char* name) {
    for (uint32_t i = 0; i < g_num_functions; i++) {
        if (strcmp(g_func_stats[i].name, name) == 0)
            return &g_func_stats[i];
    }
    if (g_num_functions < MAX_FUNCTIONS) {
        g_func_stats[g_num_functions].name       = name;
        g_func_stats[g_num_functions].cycles     = 0;
        g_func_stats[g_num_functions].instrs     = 0;
        g_func_stats[g_num_functions].call_count = 0;
        return &g_func_stats[g_num_functions++];
    }
    return NULL;
}

#define MEASURE_FUNC(func, ...) do { \
    uint64_t _c0, _c1, _i0, _i1; \
    __asm__ volatile ("rdcycle %0"   : "=r"(_c0)); \
    __asm__ volatile ("rdinstret %0" : "=r"(_i0)); \
    func(__VA_ARGS__); \
    __asm__ volatile ("rdcycle %0"   : "=r"(_c1)); \
    __asm__ volatile ("rdinstret %0" : "=r"(_i1)); \
    function_stats_t* _s = find_or_add_func(#func); \
    _s->cycles += (_c1 - _c0); \
    _s->instrs += (_i1 - _i0); \
    _s->call_count++; \
} while(0)

/* ------------------------------------------------------------------ */
/* Overall Kyber accumulator (keygen + enc + dec)                     */
/* ------------------------------------------------------------------ */
typedef struct {
    uint64_t grand_total_cycles;        /* wall-clock: all 3 ops          */
    uint64_t grand_total_instrs;
    uint64_t total_ntt_cycles;          /* cycles inside ntt_hw_drive     */
    uint64_t total_ntt_instrs;
    uint64_t total_compute_cycles;      /* hardware compute (START→DONE)  */
    uint64_t total_axi_write_cycles;
    uint64_t total_axi_read_cycles;
    uint32_t total_ntt_calls;
    uint32_t total_axi_writes;          /* total write beats              */
    uint32_t total_axi_reads;           /* total read beats               */
    uint32_t total_axi_write_bursts;
    uint32_t total_axi_read_bursts;
} kyber_overall_stats_t;

static kyber_overall_stats_t g_overall;

/* ------------------------------------------------------------------ */
/* Output helpers                                                      */
/* ------------------------------------------------------------------ */
static void emit(const char* s) { while (*s) putchar(*s++); }

static void emit_uint64(uint64_t v) {
    char buf[22]; int i = 0;
    if (!v) { putchar('0'); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    while (i--) putchar(buf[i]);
}

/* ------------------------------------------------------------------ */
/* print_ntt_details — per-op NTT call profile                        */
/* ------------------------------------------------------------------ */
static void print_ntt_details(const char* op_name) {
    ntt_hw_stats_t* s = &g_ntt_hw_stats;

    emit("\r\n╔══════════════════════════════════════════════════════════════════╗\r\n");
    emit("║  NTT CALL PROFILE ["); emit(op_name);
    emit("]                                          ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");

    for (uint32_t k = 0; k < s->total_calls && k < NTT_HW_MAX_CALLS; k++) {
        ntt_call_detail_t* d = &s->log[k];

        emit("║ Call #"); emit_uint64(d->call_no); emit(":\r\n");

        emit("║   ├─ Total:              "); emit_uint64(d->total_cycles);
        emit(" cycles, "); emit_uint64(d->total_instrs); emit(" instr\r\n");

        /* Write phase */
        emit("║   ├─ Pack (AXI writes):  "); emit_uint64(d->pack_cycles);
        emit(" cycles\r\n");
        emit("║   │     bursts:          "); emit_uint64(d->axi_write_bursts);
        emit(" bursts × "); emit_uint64(d->axi_beats_per_burst);
        emit(" beats = "); emit_uint64(d->axi_write_count);
        emit(" total beats\r\n");
        emit("║   │     avg cyc/beat:    ");
        if (d->axi_write_count)
            emit_uint64(d->axi_write_cycles / d->axi_write_count);
        else emit("0");
        emit("\r\n");
        emit("║   │     avg cyc/burst:   ");
        if (d->axi_write_bursts)
            emit_uint64(d->axi_write_cycles / d->axi_write_bursts);
        else emit("0");
        emit("\r\n");

        /* START write */
        emit("║   ├─ START write:        "); emit_uint64(d->start_write_cycles);
        emit(" cycles\r\n");

        /* Hardware compute */
        emit("║   ├─ Hardware NTT:       "); emit_uint64(d->compute_cycles);
        emit(" cycles\r\n");

        /* Read phase */
        emit("║   └─ Unpack (AXI reads): "); emit_uint64(d->unpack_cycles);
        emit(" cycles\r\n");
        emit("║         bursts:          "); emit_uint64(d->axi_read_bursts);
        emit(" bursts × "); emit_uint64(d->axi_beats_per_burst);
        emit(" beats = "); emit_uint64(d->axi_read_count);
        emit(" total beats\r\n");
        emit("║         avg cyc/beat:    ");
        if (d->axi_read_count)
            emit_uint64(d->axi_read_cycles / d->axi_read_count);
        else emit("0");
        emit("\r\n");
        emit("║         avg cyc/burst:   ");
        if (d->axi_read_bursts)
            emit_uint64(d->axi_read_cycles / d->axi_read_bursts);
        else emit("0");
        emit("\r\n");
    }

    /* Per-op summary */
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║ SUMMARY ["); emit(op_name); emit("]:\r\n");

    emit("║   Total NTT calls:       "); emit_uint64(s->total_calls);    emit("\r\n");
    emit("║   Total cycles:          "); emit_uint64(s->total_cycles);   emit("\r\n");
    emit("║   Total compute (HW):    "); emit_uint64(s->total_compute_cycles); emit("\r\n");

    emit("║   Burst geometry:        "); emit_uint64(NTT_HW_BURST_LEN);
    emit(" beats/burst, "); emit_uint64(NTT_HW_NUM_BURSTS); emit(" bursts/NTT\r\n");

    emit("║   Total AXI write beats: "); emit_uint64(s->total_axi_writes);
    emit(" in "); emit_uint64(s->total_axi_write_bursts);
    emit(" bursts (cycles: "); emit_uint64(s->total_axi_write_cycles); emit(")\r\n");

    emit("║   Total AXI read beats:  "); emit_uint64(s->total_axi_reads);
    emit(" in "); emit_uint64(s->total_axi_read_bursts);
    emit(" bursts (cycles: "); emit_uint64(s->total_axi_read_cycles); emit(")\r\n");

    /* +1 START write per NTT call */
    uint64_t total_txn = (uint64_t)s->total_axi_writes
                       + (uint64_t)s->total_axi_reads
                       + (uint64_t)s->total_calls;
    emit("║   Total AXI transactions:"); emit_uint64(total_txn); emit("\r\n");

    if (s->total_calls > 0) {
        emit("║   Avg cycles/NTT:        ");
        emit_uint64(s->total_cycles / s->total_calls); emit("\r\n");
        emit("║   Avg AXI cycles/NTT:    ");
        emit_uint64((s->total_axi_write_cycles + s->total_axi_read_cycles)
                    / s->total_calls);
        emit("\r\n");
        emit("║   Avg write beats/NTT:   ");
        emit_uint64(s->total_axi_writes / s->total_calls); emit("\r\n");
        emit("║   Avg read beats/NTT:    ");
        emit_uint64(s->total_axi_reads  / s->total_calls); emit("\r\n");
    }
    emit("╚══════════════════════════════════════════════════════════════════╝\r\n");
}

/* ------------------------------------------------------------------ */
/* print_function_stats                                                */
/* ------------------------------------------------------------------ */
static void print_function_stats(void) {
    emit("\r\n╔══════════════════════════════════════════════════════════════════╗\r\n");
    emit("║  FUNCTION CALL PROFILES                                           ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");

    uint64_t total_func_cycles = 0;
    for (uint32_t i = 0; i < g_num_functions; i++) {
        function_stats_t* f = &g_func_stats[i];
        emit("║ "); emit(f->name);
        for (int pad = strlen(f->name); pad < 30; pad++) emit(" ");
        emit(": calls="); emit_uint64(f->call_count);
        emit("  cycles="); emit_uint64(f->cycles);
        if (f->call_count > 0 && f->cycles > 0) {
            emit("  avg="); emit_uint64(f->cycles / f->call_count);
        }
        emit("\r\n");
        total_func_cycles += f->cycles;
    }

    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║ Total function cycles: "); emit_uint64(total_func_cycles); emit("\r\n");
    emit("╚══════════════════════════════════════════════════════════════════╝\r\n");
}

/* ------------------------------------------------------------------ */
/* measure_kyber_op — time one Kyber operation and accumulate overall  */
/* ------------------------------------------------------------------ */
static void measure_kyber_op(const char* name, void (*op_func)(void)) {
    uint64_t c0, c1, i0, i1;
    ntt_hw_stats_reset();
    __asm__ volatile ("rdcycle %0"   : "=r"(c0));
    __asm__ volatile ("rdinstret %0" : "=r"(i0));

 
    g_num_functions = 0;

    op_func();

    __asm__ volatile ("rdcycle %0"   : "=r"(c1));
    __asm__ volatile ("rdinstret %0" : "=r"(i1));

    /* Accumulate into overall Kyber stats */
    g_overall.grand_total_cycles     += (c1 - c0);
    g_overall.grand_total_instrs     += (i1 - i0);
    g_overall.total_ntt_calls        += g_ntt_hw_stats.total_calls;
    g_overall.total_ntt_cycles       += g_ntt_hw_stats.total_cycles;
    g_overall.total_ntt_instrs       += g_ntt_hw_stats.total_instrs;
    g_overall.total_compute_cycles   += g_ntt_hw_stats.total_compute_cycles;
    g_overall.total_axi_write_cycles += g_ntt_hw_stats.total_axi_write_cycles;
    g_overall.total_axi_read_cycles  += g_ntt_hw_stats.total_axi_read_cycles;
    g_overall.total_axi_writes       += g_ntt_hw_stats.total_axi_writes;
    g_overall.total_axi_reads        += g_ntt_hw_stats.total_axi_reads;
    g_overall.total_axi_write_bursts += g_ntt_hw_stats.total_axi_write_bursts;
    g_overall.total_axi_read_bursts  += g_ntt_hw_stats.total_axi_read_bursts;

    emit("\r\n═══════════════════════════════════════════════════════════════\r\n");
    emit("  "); emit(name); emit(" Results\r\n");
    emit("═══════════════════════════════════════════════════════════════\r\n");
    emit("[CYCLES]       "); emit(name); emit(" = "); emit_uint64(c1 - c0); emit("\r\n");
    emit("[INSTRUCTIONS] "); emit(name); emit(" = "); emit_uint64(i1 - i0); emit("\r\n");

    print_ntt_details(name);
   // print_function_stats();
}

/* ------------------------------------------------------------------ */
/* Kyber operation wrappers                                            */
/* ------------------------------------------------------------------ */
static void do_keygen(void) { crypto_kem_keypair(g_pk, g_sk); }
static void do_enc(void)    { crypto_kem_enc(g_ct, g_key_b, g_pk); }
static void do_dec(void)    { crypto_kem_dec(g_key_a, g_ct, g_sk); }

/* ------------------------------------------------------------------ */
/* Main                                                                */
/* ------------------------------------------------------------------ */
int main(void) {
    emit("[DBG] main: entered\r\n");
    emit("[KYBER] Enhanced Test Bench Started\r\n");
    emit("═══════════════════════════════════════════════════════════════\r\n");

    /* Clear overall accumulator */
    memset(&g_overall, 0, sizeof(g_overall));

    /* Random seed */
    randombytes(g_seed, 64);

    /* Measure each Kyber operation */
    measure_kyber_op("keygen", do_keygen);
    measure_kyber_op("enc",    do_enc);
    measure_kyber_op("dec",    do_dec);

    /* ---- Correctness check ---- */
    emit("\r\n═══════════════════════════════════════════════════════════════\r\n");
    emit("  VERIFICATION\r\n");
    emit("═══════════════════════════════════════════════════════════════\r\n");
    if (memcmp(g_key_a, g_key_b, CRYPTO_BYTES) == 0)
        emit("[MATCH] KA == KB  PASS\r\n");
    else
        emit("[MATCH] KA != KB  FAIL\r\n");

    /* ---- Overall Kyber summary (keygen + enc + dec) ---- */
    emit("\r\n╔══════════════════════════════════════════════════════════════════╗\r\n");
    emit("║  OVERALL KYBER SUMMARY  (keygen + enc + dec)                     ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║  WALL-CLOCK                                                       ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║ Total cycles (all ops)       : "); emit_uint64(g_overall.grand_total_cycles);  emit("\r\n");
    emit("║ Total instrs (all ops)       : "); emit_uint64(g_overall.grand_total_instrs);  emit("\r\n");

    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║  NTT ACCELERATOR TOTALS                                           ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║ Total NTT calls              : "); emit_uint64(g_overall.total_ntt_calls);      emit("\r\n");
    emit("║ Total NTT cycles             : "); emit_uint64(g_overall.total_ntt_cycles);     emit("\r\n");
    emit("║ Total compute cycles (HW)    : "); emit_uint64(g_overall.total_compute_cycles); emit("\r\n");

    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║  BURST GEOMETRY                                                   ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║ Beats per burst              : "); emit_uint64(NTT_HW_BURST_LEN);              emit("\r\n");
    emit("║ Write bursts per NTT         : "); emit_uint64(NTT_HW_NUM_BURSTS);             emit("\r\n");
    emit("║ Read  bursts per NTT         : "); emit_uint64(NTT_HW_NUM_BURSTS);             emit("\r\n");
    emit("║ Write beats  per NTT         : "); emit_uint64(NTT_HW_N);                      emit("\r\n");
    emit("║ Read  beats  per NTT         : "); emit_uint64(NTT_HW_N);                      emit("\r\n");

    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║  AXI TRANSACTION TOTALS                                           ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║ Total AXI write beats        : "); emit_uint64(g_overall.total_axi_writes);        emit("\r\n");
    emit("║ Total AXI write bursts       : "); emit_uint64(g_overall.total_axi_write_bursts);  emit("\r\n");
    emit("║ Total AXI write cycles       : "); emit_uint64(g_overall.total_axi_write_cycles);  emit("\r\n");
    emit("║ Total AXI read  beats        : "); emit_uint64(g_overall.total_axi_reads);         emit("\r\n");
    emit("║ Total AXI read  bursts       : "); emit_uint64(g_overall.total_axi_read_bursts);   emit("\r\n");
    emit("║ Total AXI read  cycles       : "); emit_uint64(g_overall.total_axi_read_cycles);   emit("\r\n");

    /* Total transactions = write beats + read beats + one START per NTT */
    uint64_t total_txn = (uint64_t)g_overall.total_axi_writes
                       + (uint64_t)g_overall.total_axi_reads
                       + (uint64_t)g_overall.total_ntt_calls;
    emit("║ Total AXI transactions       : "); emit_uint64(total_txn); emit("\r\n");

    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    emit("║  PER-NTT AVERAGES  (across all ops)                               ║\r\n");
    emit("╠══════════════════════════════════════════════════════════════════╣\r\n");
    if (g_overall.total_ntt_calls > 0) {
        emit("║ Avg cycles/NTT               : ");
        emit_uint64(g_overall.total_ntt_cycles / g_overall.total_ntt_calls);       emit("\r\n");
        emit("║ Avg compute cycles/NTT       : ");
        emit_uint64(g_overall.total_compute_cycles / g_overall.total_ntt_calls);   emit("\r\n");
        emit("║ Avg AXI cycles/NTT           : ");
        emit_uint64((g_overall.total_axi_write_cycles + g_overall.total_axi_read_cycles)
                    / g_overall.total_ntt_calls);                                   emit("\r\n");
        emit("║ Avg write beats/NTT          : ");
        emit_uint64(g_overall.total_axi_writes / g_overall.total_ntt_calls);       emit("\r\n");
        emit("║ Avg read  beats/NTT          : ");
        emit_uint64(g_overall.total_axi_reads  / g_overall.total_ntt_calls);       emit("\r\n");
        emit("║ Avg write bursts/NTT         : ");
        emit_uint64(g_overall.total_axi_write_bursts / g_overall.total_ntt_calls); emit("\r\n");
        emit("║ Avg read  bursts/NTT         : ");
        emit_uint64(g_overall.total_axi_read_bursts  / g_overall.total_ntt_calls); emit("\r\n");
        emit("║ Avg transactions/NTT         : ");
        emit_uint64(total_txn / g_overall.total_ntt_calls);                        emit("\r\n");
    }
    emit("╚══════════════════════════════════════════════════════════════════╝\r\n");

    emit("[KYBER] ALL TESTS COMPLETE\r\n");
    return 0;
}
