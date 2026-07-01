#include <stdio.h>
#include <stdint.h>
#include <string.h>

/* ============================================================
 * Integer-only ratio printer
 * ============================================================ */
static void pf(uint64_t n, uint64_t d) {
    if (!d) { printf("0.00"); return; }
    printf("%llu.%02llu",
           (unsigned long long)(n / d),
           (unsigned long long)((n * 100 / d) % 100));
}

/* ============================================================
 * CLINT mtime calibration
 * ============================================================ */
#define CLINT_MTIME_LO  ((volatile uint32_t *)(uintptr_t)0x0200BFF8UL)
#define CLINT_MTIME_HI  ((volatile uint32_t *)(uintptr_t)0x0200BFFCUL)
#define MTIME_HZ        1000000ULL
#define CAL_TICKS       1000ULL

static uint64_t g_cpu_hz        = 0;
static uint64_t g_target_cpu_hz = 50000000ULL;

static uint64_t read_mtime(void) {
    uint32_t h0, l, h1;
    do {
        h0 = *CLINT_MTIME_HI;
        l  = *CLINT_MTIME_LO;
        h1 = *CLINT_MTIME_HI;
    } while (h0 != h1);
    return ((uint64_t)h1 << 32) | l;
}

static void print_ns(uint64_t ns) {
    if (ns < 1000000ULL)
        printf("%llu.%03llu us",
               (unsigned long long)(ns / 1000ULL),
               (unsigned long long)(ns % 1000ULL));
    else
        printf("%llu.%03llu ms",
               (unsigned long long)(ns / 1000000ULL),
               (unsigned long long)((ns % 1000000ULL) / 1000ULL));
}

static uint64_t cycles_to_ns(uint64_t cyc) {
    if (!g_cpu_hz) return 0ULL;
    uint64_t us  = (cyc * 1000000ULL) / g_cpu_hz;
    uint64_t rem = (cyc * 1000000ULL) % g_cpu_hz;
    return us * 1000ULL + (rem * 1000ULL) / g_cpu_hz;
}

static uint64_t cycles_at_target(uint64_t cyc) {
    if (!g_cpu_hz) return cyc;
    return (cyc * g_target_cpu_hz) / g_cpu_hz;
}

/* ============================================================
 * Hardware performance counters
 * ============================================================ */
static inline uint64_t read_cycles(void) {
    uint64_t c; asm volatile ("rdcycle %0" : "=r"(c)); return c;
}
static inline uint64_t read_instret(void) {
    uint64_t v; asm volatile ("rdinstret %0" : "=r"(v)); return v;
}

/* ============================================================
 * Clock calibration
 * ============================================================ */
static void calibrate_clock(void) {
    uint64_t t0, c0, t1, c1, dt, dc;
    t0 = read_mtime(); while (read_mtime() == t0) ; t0 = read_mtime();
    c0 = read_cycles();
    while ((read_mtime() - t0) < CAL_TICKS) ;
    t1 = read_mtime(); c1 = read_cycles();
    dt = t1 - t0; dc = c1 - c0;
    g_cpu_hz = (dc * MTIME_HZ) / dt;
    printf("Clock calibration: %llu mtime ticks = %llu cycles  ->  CPU ",
           (unsigned long long)dt, (unsigned long long)dc);
    pf(g_cpu_hz, 1000000ULL); printf(" MHz\n\n");
}

/* ============================================================
 * NTT AXI4 Register Map
 * ============================================================ */
#define NTT_BASE        0x00011400U
#define NTT_CONTROL     (NTT_BASE + 0x000)
#define NTT_STATUS      (NTT_BASE + 0x004)
#define NTT_PARAMS      (NTT_BASE + 0x00C)
#define NTT_DATA_IN(i)  (NTT_BASE + 0x400 + (i)*4)
#define NTT_DATA_OUT(i) (NTT_BASE + 0xC00 + (i)*4)

#define NTT_CTRL_START  (1u << 0)
#define NTT_CTRL_BUSY   (1u << 2)
#define NTT_CTRL_DONE   (1u << 3)

#define NTT_N    256
#define NTT_Q    3329
#define NTT_ROOT 17

/* ============================================================
 * AXI4 accessors
 * ============================================================ */
static inline void axi_write32(uint32_t addr, uint32_t data) {
    *(volatile uint32_t *)(uintptr_t)addr = data;
}
static inline uint32_t axi_read32(uint32_t addr) {
    return *(volatile uint32_t *)(uintptr_t)addr;
}

/* ============================================================
 * Hardware NTT driver
 * ============================================================ */
static void ntt_reset_handshake(void) {
    axi_write32(NTT_CONTROL, 0u);
    __asm__ volatile ("fence w,w" ::: "memory");
    uint32_t timeout = 2000000u;
    while ((axi_read32(NTT_CONTROL) & (NTT_CTRL_BUSY | NTT_CTRL_DONE)) && --timeout)
        ;
    if (!timeout)
        printf("WARNING: ntt_reset_handshake timeout! ctrl=0x%08x\n",
               axi_read32(NTT_CONTROL));
}

static void ntt_load(const uint32_t *v) {
    for (int i = 0; i < NTT_N; i++)
        axi_write32(NTT_DATA_IN(i), v[i] & 0xFFFFu);
    __asm__ volatile ("fence w,w" ::: "memory");
}

static void ntt_store(uint32_t *v) {
    __asm__ volatile ("fence r,r" ::: "memory");
    for (int i = 0; i < NTT_N; i++)
        v[i] = axi_read32(NTT_DATA_OUT(i)) & 0xFFFFu;
}

typedef struct { uint64_t cycles; uint64_t instrs; } perf_t;

/* ============================================================
 * Detailed phase timers (new)
 * ============================================================ */
typedef struct {
    uint64_t load_cyc;    /* AXI write: host -> NTT input registers  */
    uint64_t compute_cyc; /* HW compute: START asserted -> DONE seen  */
    uint64_t store_cyc;   /* AXI read:  NTT output registers -> host  */
    uint64_t total_cyc;   /* load + compute + store                   */
    uint64_t instrs;      /* total instructions for entire fwd NTT    */
} fwd_detail_t;

static fwd_detail_t hw_ntt_fwd_detailed(const uint32_t *in, uint32_t *out) {
    fwd_detail_t d;
    uint64_t t0, t1, t2, t3, i0;

    ntt_reset_handshake();

    /* --- LOAD phase --- */
    i0 = read_instret();
    t0 = read_cycles();
    for (int i = 0; i < NTT_N; i++)
        axi_write32(NTT_DATA_IN(i), in[i] & 0xFFFFu);
    __asm__ volatile ("fence w,w" ::: "memory");
    t1 = read_cycles();

    /* --- COMPUTE phase --- */
    axi_write32(NTT_CONTROL, NTT_CTRL_START);
    while (!(axi_read32(NTT_CONTROL) & NTT_CTRL_DONE)) ;
    t2 = read_cycles();
    axi_write32(NTT_CONTROL, 0u);
    __asm__ volatile ("fence w,w" ::: "memory");

    /* --- STORE phase --- */
    __asm__ volatile ("fence r,r" ::: "memory");
    for (int i = 0; i < NTT_N; i++)
        out[i] = axi_read32(NTT_DATA_OUT(i)) & 0xFFFFu;
    t3 = read_cycles();

    d.load_cyc    = t1 - t0;
    d.compute_cyc = t2 - t1;
    d.store_cyc   = t3 - t2;
    d.total_cyc   = t3 - t0;
    d.instrs      = read_instret() - i0;
    return d;
}

/* ============================================================
 * Zeta table
 * ============================================================ */
static const uint16_t zetas[128] = {
       1, 1729, 2580, 3289, 2642,  630, 1897,  848,
    1062, 1919,  193,  797, 2786, 3260,  569, 1746,
     296, 2447, 1339, 1476, 3046,   56, 2240, 1333,
    1426, 2094,  535, 2882, 2393, 2879, 1974,  821,
     289,  331, 3253, 1756, 1197, 2304, 2277, 2055,
     650, 1977, 2513,  632, 2865,   33, 1320, 1915,
    2319, 1435,  807,  452, 1438, 2868, 1534, 2402,
    2647, 2617, 1481,  648, 2474, 3110, 1227,  910,
      17, 2761,  583, 2649, 1637,  723, 2288, 1100,
    1409, 2662, 3281,  233,  756, 2156, 3015, 3050,
    1703, 1651, 2789, 1789, 1847,  952, 1461, 2687,
     939, 2308, 2437, 2388,  733, 2337,  268,  641,
    1584, 2298, 2037, 3220,  375, 2549, 2090, 1645,
    1063,  319, 2773,  757, 2099,  561, 2466, 2594,
    2804, 1092,  403, 1026, 1143, 2150, 2775,  886,
    1722, 1212, 1874, 1029, 2110, 2935,  885, 2154
};

/* ============================================================
 * Software INTT
 * ============================================================ */
typedef struct { uint16_t length; uint16_t start; uint8_t ki; } SchedEntry;
static SchedEntry g_schedule[127];
static int        g_schedule_built = 0;

static void build_schedule(void) {
    if (g_schedule_built) return;
    int k = 1, idx = 0;
    int length = 128;
    while (length >= 2) {
        int start = 0;
        while (start < NTT_N) {
            g_schedule[idx].length = (uint16_t)length;
            g_schedule[idx].start  = (uint16_t)start;
            g_schedule[idx].ki     = (uint8_t)k;
            idx++; k++;
            start += 2 * length;
        }
        length >>= 1;
    }
    g_schedule_built = 1;
}

static uint32_t modinv(uint32_t a) {
    uint32_t r = 1, b = a % NTT_Q;
    uint32_t e = NTT_Q - 2;
    while (e) {
        if (e & 1) r = (uint32_t)(((uint64_t)r * b) % NTT_Q);
        b = (uint32_t)(((uint64_t)b * b) % NTT_Q);
        e >>= 1;
    }
    return r;
}

#define INV2 1665u

/* ============================================================
 * Detailed SW INTT phase timers (new)
 *
 * Three phases measured:
 *   Stage 1..3  : first 3 stages (length=128,64,32) — fewest butterflies
 *   Stage 4..5  : stages 4..5   (length=16,8)
 *   Stage 6..7  : last 2 stages (length=4,2)       — most butterflies
 *   modinv cost : total modular-inverse work across all 127 groups
 * ============================================================ */
typedef struct {
    uint64_t stage_cyc[7];  /* per-stage cycle counts (stages 0..6) */
    uint64_t modinv_cyc;    /* cumulative modinv cost                */
    uint64_t total_cyc;     /* total SW INTT cycles                  */
    uint64_t instrs;        /* total instructions                    */
} intt_detail_t;

static intt_detail_t sw_intt_detailed(uint32_t f[NTT_N]) {
    build_schedule();
    intt_detail_t d;
    for (int s = 0; s < 7; s++) d.stage_cyc[s] = 0;
    d.modinv_cyc = 0;
    d.total_cyc  = 0;
    d.instrs     = 0;

    uint64_t t_total_start = read_cycles();
    uint64_t i0            = read_instret();

    /* Map schedule index (0..126) back to stage number (0..6).
     * Stage k spans groups for length = 128 >> k.
     * Groups per stage: NTT_N / (2*length) = 256/(2*(128>>k)) = 1<<k
     *   stage 0: 1 group   (indices 0)
     *   stage 1: 2 groups  (indices 1-2)
     *   stage 2: 4 groups  (indices 3-6)
     *   stage 3: 8 groups  (indices 7-14)
     *   stage 4: 16 groups (indices 15-30)
     *   stage 5: 32 groups (indices 31-62)
     *   stage 6: 64 groups (indices 63-126)
     * INTT traverses in REVERSE (s=126 down to 0).
     */

    /* Stage boundary lookup: sched_idx -> stage (forward order) */
    static const int stage_boundary[8] = { 0, 1, 3, 7, 15, 31, 63, 127 };

    for (int s = 126; s >= 0; s--) {
        /* Determine which forward stage this schedule entry belongs to */
        int stage = 0;
        for (int st = 0; st < 7; st++) {
            if (s >= stage_boundary[st] && s < stage_boundary[st+1]) {
                stage = st; break;
            }
        }

        int      length   = g_schedule[s].length;
        int      start    = g_schedule[s].start;
        uint32_t zeta     = zetas[g_schedule[s].ki];

        uint64_t t_inv0   = read_cycles();
        uint32_t zeta_inv = modinv(zeta);
        d.modinv_cyc     += read_cycles() - t_inv0;

        uint64_t t_bfly0  = read_cycles();
        for (int j = start; j < start + length; j++) {
            uint32_t A = f[j];
            uint32_t B = f[j + length];
            f[j]          = (uint32_t)(((uint64_t)(A + B)         * INV2) % NTT_Q);
            uint32_t AmB  = (A >= B) ? (A - B) : (A + NTT_Q - B);
            f[j + length] = (uint32_t)(((uint64_t)AmB * INV2 % NTT_Q * zeta_inv) % NTT_Q);
        }
        d.stage_cyc[stage] += read_cycles() - t_bfly0;
    }

    d.total_cyc = read_cycles() - t_total_start;
    d.instrs    = read_instret() - i0;
    return d;
}

/* ============================================================
 * Input generators
 * ============================================================ */
static void gen_impulse(uint32_t *v, int pos) {
    for (int i = 0; i < NTT_N; i++) v[i] = (i == pos) ? 1u : 0u;
}
static void gen_ramp(uint32_t *v) {
    for (int i = 0; i < NTT_N; i++) v[i] = (uint32_t)i % NTT_Q;
}
static void gen_reverse_ramp(uint32_t *v) {
    for (int i = 0; i < NTT_N; i++) v[i] = (uint32_t)(NTT_N-1-i) % NTT_Q;
}
static void gen_constant(uint32_t *v, uint32_t val) {
    for (int i = 0; i < NTT_N; i++) v[i] = val % NTT_Q;
}
static void gen_max_val(uint32_t *v) {
    for (int i = 0; i < NTT_N; i++) v[i] = NTT_Q - 1;
}
static void gen_alternating(uint32_t *v, uint32_t a, uint32_t b) {
    for (int i = 0; i < NTT_N; i++) v[i] = (i & 1) ? b % NTT_Q : a % NTT_Q;
}
static void gen_geometric(uint32_t *v, uint32_t r) {
    uint32_t cur = 1;
    for (int i = 0; i < NTT_N; i++) {
        v[i] = cur;
        cur = (uint32_t)(((uint64_t)cur * r) % NTT_Q);
    }
}
static void gen_sparse(uint32_t *v, int step, uint32_t val) {
    for (int i = 0; i < NTT_N; i++)
        v[i] = ((i % step) == 0) ? val % NTT_Q : 0u;
}
static void gen_step(uint32_t *v, uint32_t lo, uint32_t hi) {
    for (int i = 0; i < NTT_N; i++)
        v[i] = (i < NTT_N/2) ? lo % NTT_Q : hi % NTT_Q;
}

/* ============================================================
 * Print helpers
 * ============================================================ */
static void print_perf(const char *label, uint64_t cyc, uint64_t ins) {
    printf("  %-32s cyc=%7llu  ins=%7llu  CPI=",
           label,
           (unsigned long long)cyc,
           (unsigned long long)ins);
    pf(cyc, ins);
    printf("  t="); print_ns(cycles_to_ns(cyc));
    printf("  @50MHz=%llu\n", (unsigned long long)cycles_at_target(cyc));
}

/* Print a cycle bar: each '#' = bar_unit cycles */
static void print_bar(uint64_t cyc, uint64_t bar_unit) {
    if (!bar_unit) bar_unit = 1;
    uint64_t bars = cyc / bar_unit;
    if (bars > 40) bars = 40;
    for (uint64_t i = 0; i < bars; i++) printf("#");
}

/* Print percent (integer-only) */
static void print_pct(uint64_t part, uint64_t total) {
    if (!total) { printf("  0%%"); return; }
    uint64_t pct = (part * 100) / total;
    printf("%3llu%%", (unsigned long long)pct);
}

/* ============================================================
 * Aggregate accumulators (new) — one entry per test call
 * ============================================================ */
#define MAX_CALLS 15

typedef struct {
    char     label[32];
    uint64_t fwd_load;
    uint64_t fwd_compute;
    uint64_t fwd_store;
    uint64_t fwd_total;
    uint64_t fwd_instrs;
    uint64_t inv_stage[7];
    uint64_t inv_modinv;
    uint64_t inv_total;
    uint64_t inv_instrs;
    uint64_t rt_total;   /* fwd_total + inv_total */
    int      pass;
} CallRecord;

static CallRecord g_records[MAX_CALLS];
static int        g_num_records = 0;

/* ============================================================
 * run_call: one round-trip test with detailed analysis (modified)
 * ============================================================ */
static int run_call(int num, const char *label, const uint32_t *original) {
    static uint32_t ntt_out  [NTT_N];
    static uint32_t recovered[NTT_N];

    printf("===========================================\n");
    printf("CALL %2d — %s\n", num, label);
    printf("===========================================\n");

    /* ---- HW forward NTT (detailed) ---- */
    fwd_detail_t fwd = hw_ntt_fwd_detailed(original, ntt_out);

    printf("  [HW Forward NTT]\n");
    print_perf("  Total (load+compute+store)", fwd.total_cyc, fwd.instrs);

    /* Phase breakdown */
    uint64_t bu = fwd.total_cyc / 32 ? fwd.total_cyc / 32 : 1;
    printf("  %-20s %7llu cyc  ", "  Load (AXI write)",
           (unsigned long long)fwd.load_cyc);
    print_pct(fwd.load_cyc, fwd.total_cyc);
    printf("  |"); print_bar(fwd.load_cyc, bu); printf("|\n");

    printf("  %-20s %7llu cyc  ", "  Compute (HW)",
           (unsigned long long)fwd.compute_cyc);
    print_pct(fwd.compute_cyc, fwd.total_cyc);
    printf("  |"); print_bar(fwd.compute_cyc, bu); printf("|\n");

    printf("  %-20s %7llu cyc  ", "  Store (AXI read)",
           (unsigned long long)fwd.store_cyc);
    print_pct(fwd.store_cyc, fwd.total_cyc);
    printf("  |"); print_bar(fwd.store_cyc, bu); printf("|\n");

    /* ---- SW inverse NTT (detailed) ---- */
    memcpy(recovered, ntt_out, NTT_N * sizeof(uint32_t));
    intt_detail_t inv = sw_intt_detailed(recovered);

    printf("\n  [SW Inverse NTT]\n");
    print_perf("  Total", inv.total_cyc, inv.instrs);

    /* modinv overhead */
    printf("  %-20s %7llu cyc  ", "  modinv overhead",
           (unsigned long long)inv.modinv_cyc);
    print_pct(inv.modinv_cyc, inv.total_cyc);
    printf("  |");
    print_bar(inv.modinv_cyc, inv.total_cyc / 32 ? inv.total_cyc / 32 : 1);
    printf("|\n");

    /* Per-stage butterfly cost */
    static const char *stage_names[7] = {
        "  St0 len=128 (1 grp)",
        "  St1 len= 64 (2 grp)",
        "  St2 len= 32 (4 grp)",
        "  St3 len= 16 (8 grp)",
        "  St4 len=  8(16 grp)",
        "  St5 len=  4(32 grp)",
        "  St6 len=  2(64 grp)"
    };
    uint64_t inv_bu = inv.total_cyc / 32 ? inv.total_cyc / 32 : 1;
    for (int st = 0; st < 7; st++) {
        printf("  %-22s %7llu cyc  ", stage_names[st],
               (unsigned long long)inv.stage_cyc[st]);
        print_pct(inv.stage_cyc[st], inv.total_cyc);
        printf("  |"); print_bar(inv.stage_cyc[st], inv_bu); printf("|\n");
    }

    /* ---- Correctness ---- */
    int pass = 1, errors = 0;
    for (int i = 0; i < NTT_N; i++) {
        if (recovered[i] != original[i]) {
            if (errors < 4)
                printf("  MISMATCH [%3d]: got %4u  expected %4u\n",
                       i, recovered[i], original[i]);
            pass = 0; errors++;
        }
    }
    if (!pass && errors >= 4)
        printf("  ... (%d total mismatches)\n", errors);

    uint64_t rt = fwd.total_cyc + inv.total_cyc;
    printf("\n  Round-trip total: %llu cyc  @50MHz: %llu  t=",
           (unsigned long long)rt,
           (unsigned long long)cycles_at_target(rt));
    print_ns(cycles_to_ns(rt));
    printf("\n  Result: %s\n\n", pass ? "PASS" : "FAIL");

    /* Store record for aggregate table */
    if (g_num_records < MAX_CALLS) {
        CallRecord *r = &g_records[g_num_records++];
        strncpy(r->label, label, 31); r->label[31] = '\0';
        r->fwd_load    = fwd.load_cyc;
        r->fwd_compute = fwd.compute_cyc;
        r->fwd_store   = fwd.store_cyc;
        r->fwd_total   = fwd.total_cyc;
        r->fwd_instrs  = fwd.instrs;
        for (int st = 0; st < 7; st++) r->inv_stage[st] = inv.stage_cyc[st];
        r->inv_modinv  = inv.modinv_cyc;
        r->inv_total   = inv.total_cyc;
        r->inv_instrs  = inv.instrs;
        r->rt_total    = rt;
        r->pass        = pass;
    }
    return pass;
}

/* ============================================================
 * print_summary_table — called once after all test calls (new)
 * ============================================================ */
static void print_summary_table(int total_pass) {
    int N = g_num_records;
    if (!N) return;

    /* Compute column-wise totals and averages */
    uint64_t sum_fwd_load = 0, sum_fwd_cmp = 0, sum_fwd_sto = 0;
    uint64_t sum_fwd_tot  = 0, sum_inv_tot = 0, sum_rt = 0;
    uint64_t sum_inv_mi   = 0;
    uint64_t sum_inv_st[7] = {0};
    uint64_t min_rt = UINT64_MAX, max_rt = 0;
    int      min_idx = 0, max_idx = 0;

    for (int i = 0; i < N; i++) {
        sum_fwd_load += g_records[i].fwd_load;
        sum_fwd_cmp  += g_records[i].fwd_compute;
        sum_fwd_sto  += g_records[i].fwd_store;
        sum_fwd_tot  += g_records[i].fwd_total;
        sum_inv_tot  += g_records[i].inv_total;
        sum_inv_mi   += g_records[i].inv_modinv;
        sum_rt       += g_records[i].rt_total;
        for (int s = 0; s < 7; s++) sum_inv_st[s] += g_records[i].inv_stage[s];
        if (g_records[i].rt_total < min_rt) { min_rt = g_records[i].rt_total; min_idx = i; }
        if (g_records[i].rt_total > max_rt) { max_rt = g_records[i].rt_total; max_idx = i; }
    }

    /* ---- Per-call table ---- */
    printf("===========================================\n");
    printf("CYCLE COUNT ANALYSIS TABLE  (%d calls)\n", N);
    printf("===========================================\n");
    printf("%-4s %-22s %8s %8s %8s %8s %8s %8s %5s\n",
           "#", "Label",
           "FWD_LD", "FWD_CMP", "FWD_STO", "FWD_TOT",
           "INV_TOT", "RT_TOT", "PASS");
    printf("%-4s %-22s %8s %8s %8s %8s %8s %8s %5s\n",
           "----", "----------------------",
           "--------","--------","--------","--------",
           "--------","--------","-----");

    for (int i = 0; i < N; i++) {
        CallRecord *r = &g_records[i];
        printf("%2d   %-22s %8llu %8llu %8llu %8llu %8llu %8llu  %s\n",
               i+1, r->label,
               (unsigned long long)r->fwd_load,
               (unsigned long long)r->fwd_compute,
               (unsigned long long)r->fwd_store,
               (unsigned long long)r->fwd_total,
               (unsigned long long)r->inv_total,
               (unsigned long long)r->rt_total,
               r->pass ? "PASS" : "FAIL");
    }

    printf("%-4s %-22s %8s %8s %8s %8s %8s %8s\n",
           "----", "----------------------",
           "--------","--------","--------","--------",
           "--------","--------");
    printf("%-4s %-22s %8llu %8llu %8llu %8llu %8llu %8llu\n",
           "SUM", "",
           (unsigned long long)sum_fwd_load,
           (unsigned long long)sum_fwd_cmp,
           (unsigned long long)sum_fwd_sto,
           (unsigned long long)sum_fwd_tot,
           (unsigned long long)sum_inv_tot,
           (unsigned long long)sum_rt);
    printf("%-4s %-22s %8llu %8llu %8llu %8llu %8llu %8llu\n",
           "AVG", "",
           (unsigned long long)(sum_fwd_load/N),
           (unsigned long long)(sum_fwd_cmp /N),
           (unsigned long long)(sum_fwd_sto /N),
           (unsigned long long)(sum_fwd_tot /N),
           (unsigned long long)(sum_inv_tot /N),
           (unsigned long long)(sum_rt      /N));

    /* ---- HW NTT phase breakdown (averages) ---- */
    printf("\n--- HW Forward NTT Phase Breakdown (averages over %d calls) ---\n", N);
    uint64_t avg_fwd = sum_fwd_tot / N;
    uint64_t avg_ld  = sum_fwd_load / N;
    uint64_t avg_cmp = sum_fwd_cmp  / N;
    uint64_t avg_sto = sum_fwd_sto  / N;
    uint64_t bu      = avg_fwd / 32 ? avg_fwd / 32 : 1;

    printf("  %-22s %8llu cyc  ", "Load (AXI write)",
           (unsigned long long)avg_ld);
    print_pct(avg_ld, avg_fwd);
    printf("  |"); print_bar(avg_ld, bu); printf("|\n");

    printf("  %-22s %8llu cyc  ", "Compute (HW kernel)",
           (unsigned long long)avg_cmp);
    print_pct(avg_cmp, avg_fwd);
    printf("  |"); print_bar(avg_cmp, bu); printf("|\n");

    printf("  %-22s %8llu cyc  ", "Store (AXI read)",
           (unsigned long long)avg_sto);
    print_pct(avg_sto, avg_fwd);
    printf("  |"); print_bar(avg_sto, bu); printf("|\n");

    printf("  AXI transfer overhead: ");
    print_pct(avg_ld + avg_sto, avg_fwd);
    printf("  (load+store / total_fwd)\n");

    printf("  HW compute @ actual CPU: t=");
    print_ns(cycles_to_ns(avg_cmp));
    printf("  @50MHz: %llu cyc\n",
           (unsigned long long)cycles_at_target(avg_cmp));

    /* ---- SW INTT stage breakdown (averages) ---- */
    printf("\n--- SW Inverse NTT Stage Breakdown (averages over %d calls) ---\n", N);
    uint64_t avg_inv = sum_inv_tot / N;
    uint64_t avg_mi  = sum_inv_mi  / N;
    uint64_t inv_bu  = avg_inv / 32 ? avg_inv / 32 : 1;

    static const char *sn[7] = {
        "St0 len=128 ( 1 grp)",
        "St1 len= 64 ( 2 grp)",
        "St2 len= 32 ( 4 grp)",
        "St3 len= 16 ( 8 grp)",
        "St4 len=  8 (16 grp)",
        "St5 len=  4 (32 grp)",
        "St6 len=  2 (64 grp)"
    };
    for (int st = 0; st < 7; st++) {
        uint64_t avg_st = sum_inv_st[st] / N;
        printf("  %-22s %8llu cyc  ", sn[st],
               (unsigned long long)avg_st);
        print_pct(avg_st, avg_inv);
        printf("  |"); print_bar(avg_st, inv_bu); printf("|\n");
    }
    printf("  %-22s %8llu cyc  ", "modinv (all 127 grps)",
           (unsigned long long)avg_mi);
    print_pct(avg_mi, avg_inv);
    printf("  (%.1f%% of SW INTT)\n",
           avg_inv ? (double)(avg_mi * 100) / avg_inv : 0.0);

    printf("  SW INTT @ actual CPU:  t=");
    print_ns(cycles_to_ns(avg_inv));
    printf("  @50MHz: %llu cyc\n",
           (unsigned long long)cycles_at_target(avg_inv));

    /* ---- HW vs SW ratio ---- */
    printf("\n--- HW NTT vs SW INTT Ratio ---\n");
    printf("  Avg HW fwd  : %llu cyc\n", (unsigned long long)(sum_fwd_tot/N));
    printf("  Avg SW inv  : %llu cyc\n", (unsigned long long)(sum_inv_tot/N));
    printf("  SW/HW ratio : ");
    pf(sum_inv_tot, sum_fwd_tot); printf("x\n");
    printf("  SW INTT is  ");
    pf(sum_inv_tot > sum_fwd_tot ? sum_inv_tot - sum_fwd_tot : sum_fwd_tot - sum_inv_tot,
       sum_fwd_tot > 0 ? sum_fwd_tot : 1);
    printf("x %s than HW NTT\n",
           sum_inv_tot > sum_fwd_tot ? "SLOWER" : "faster");

    /* ---- Round-trip latency ---- */
    printf("\n--- Round-Trip Latency ---\n");
    printf("  Avg RT: %llu cyc  t=",
           (unsigned long long)(sum_rt/N));
    print_ns(cycles_to_ns(sum_rt/N));
    printf("  @50MHz: %llu cyc\n",
           (unsigned long long)cycles_at_target(sum_rt/N));
    printf("  Min RT: %llu cyc  (%s)\n",
           (unsigned long long)min_rt, g_records[min_idx].label);
    printf("  Max RT: %llu cyc  (%s)\n",
           (unsigned long long)max_rt, g_records[max_idx].label);
    printf("  Range : %llu cyc  (max-min)\n",
           (unsigned long long)(max_rt - min_rt));

    /* ---- Correctness summary ---- */
    printf("\n--- Correctness ---\n");
    printf("  Passed: %d / %d\n", total_pass, N);
    for (int i = 0; i < N; i++) {
        printf("  [%2d] %-22s  %s\n",
               i+1, g_records[i].label,
               g_records[i].pass ? "PASS" : "FAIL");
    }
    printf("\n");
}

/* ============================================================
 * main
 * ============================================================ */
int main(void) {
    printf("MAIN STARTED\n");
    printf("\n===========================================\n");
    printf("AXI4 NTT — HW forward + SW inverse round-trip\n");
    printf("    (with detailed cycle-count analysis)\n");
    printf("===========================================\n\n");

    calibrate_clock();
    printf("Target for scaling: "); pf(g_target_cpu_hz, 1000000ULL); printf(" MHz\n\n");

    uint32_t params = axi_read32(NTT_PARAMS);
    printf("HW params: N=%u  ROOT=%u  Q=%u\n\n",
           params & 0xFFFFu, (params >> 16) & 0xFFFFu, NTT_Q);

    build_schedule();
    ntt_reset_handshake();

    static uint32_t buf[NTT_N];
    int pass = 0;

    gen_impulse(buf, 0);   pass += run_call( 1, "impulse[0]",           buf);
    gen_impulse(buf, 1);   pass += run_call( 2, "impulse[1]",           buf);
    gen_impulse(buf, 127); pass += run_call( 3, "impulse[127]",         buf);
    gen_impulse(buf, 255); pass += run_call( 4, "impulse[255]",         buf);
    gen_ramp(buf);         pass += run_call( 5, "ramp 0..255 mod Q",    buf);
    gen_reverse_ramp(buf); pass += run_call( 6, "reverse ramp",         buf);
    gen_constant(buf, 1);  pass += run_call( 7, "constant 1",           buf);
    gen_max_val(buf);      pass += run_call( 8, "constant Q-1",         buf);
    gen_alternating(buf, 0, 1);           pass += run_call( 9, "alternating 0/1",      buf);
    gen_alternating(buf, 1, NTT_Q - 1);  pass += run_call(10, "alternating 1/(Q-1)",  buf);
    gen_geometric(buf, 2);                pass += run_call(11, "geometric r=2",         buf);
    gen_geometric(buf, NTT_ROOT);         pass += run_call(12, "geometric r=ROOT=17",   buf);
    gen_sparse(buf, 4, 1);                pass += run_call(13, "sparse step=4  v=1",    buf);
    gen_sparse(buf, 16, NTT_Q-1);         pass += run_call(14, "sparse step=16 v=Q-1", buf);
    gen_step(buf, 100, 200);              pass += run_call(15, "step 100/200",           buf);

    print_summary_table(pass);

    printf("===========================================\n");
    printf("END OF TEST\n");
    printf("===========================================\n\n");

    extern volatile uint64_t tohost;
    tohost = (pass == 15) ? 1ULL : 3ULL;
    while (1) {}
    return 0;
}
