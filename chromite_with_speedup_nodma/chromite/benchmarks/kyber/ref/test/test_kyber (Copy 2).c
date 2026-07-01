/*
 * test_kyber.c — Kyber-768 testbench with cycle, instruction, and time measurement
 *
 * Output goes exclusively through putchar() -> UART TX poll at 0x1130C.
 * No printf, no fflush, no newlib stdio buffering — those route through
 * tohost/fromhost which is not needed here.
 *
 * Cycle and instruction counting uses RISC-V mcycle / minstret CSRs.
 * CPU_HZ MUST be defined at compile time to match your core frequency
 * so that cycle counts are converted to microseconds:
 *
 *   e.g.  -DCPU_HZ=50000000   (50 MHz)
 *         -DCPU_HZ=100000000  (100 MHz)
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../kem.h"
#include "../randombytes.h"

#ifndef CPU_HZ
#  error "CPU_HZ must be defined (-DCPU_HZ=<core_frequency_hz>)"
#endif

#define NTESTS           1
#define KYBER_SEED_BYTES 64

/* ------------------------------------------------------------------ */
/* File-scope statics — ~4.7 KB in BSS, zero-initialised by crt.S    */
/* ------------------------------------------------------------------ */
static uint8_t g_seed [KYBER_SEED_BYTES];
static uint8_t g_pk   [CRYPTO_PUBLICKEYBYTES];
static uint8_t g_sk   [CRYPTO_SECRETKEYBYTES];
static uint8_t g_ct   [CRYPTO_CIPHERTEXTBYTES];
static uint8_t g_key_a[CRYPTO_BYTES];
static uint8_t g_key_b[CRYPTO_BYTES];

/* ------------------------------------------------------------------ */
/* Performance counters — RISC-V mcycle and minstret CSRs             */
/* ------------------------------------------------------------------ */

/* Structure to hold performance metrics */
typedef struct {
    uint64_t cycles;
    uint64_t instructions;
} perf_metrics_t;

/* Read 64-bit cycle counter (mcycle) */
static uint64_t read_cycles(void)
{
#if __riscv_xlen == 64
    uint64_t c;
    __asm__ volatile ("rdcycle %0" : "=r"(c));
    return c;
#else
    /* RV32: carry-safe double-read of mcycleh / mcycle */
    uint32_t lo, hi, hi2;
    do {
        __asm__ volatile ("rdcycleh %0" : "=r"(hi));
        __asm__ volatile ("rdcycle  %0" : "=r"(lo));
        __asm__ volatile ("rdcycleh %0" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
#endif
}

/* Read 64-bit instruction counter (minstret) */
static uint64_t read_instructions(void)
{
#if __riscv_xlen == 64
    uint64_t i;
    __asm__ volatile ("rdinstret %0" : "=r"(i));
    return i;
#else
    /* RV32: carry-safe double-read of minstreth / minstret */
    uint32_t lo, hi, hi2;
    do {
        __asm__ volatile ("rdinstreth %0" : "=r"(hi));
        __asm__ volatile ("rdinstret  %0" : "=r"(lo));
        __asm__ volatile ("rdinstreth %0" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
#endif
}

/* Read both cycle and instruction counters atomically */
static void read_perf_metrics(perf_metrics_t *m)
{
    m->cycles = read_cycles();
    m->instructions = read_instructions();
}

/* cycles_to_us: integer µs, no floating point */
#define CYCLES_TO_US(c)  ((uint64_t)(c) / ((uint64_t)CPU_HZ / 1000000ULL))

/* ------------------------------------------------------------------ */
/* Output helpers — putchar() only, no printf/fflush/newlib stdio      */
/* ------------------------------------------------------------------ */

static void emit(const char *s)
{
    while (*s) putchar((unsigned char)*s++);
}

static void emit_hex_byte(uint8_t b)
{
    static const char h[] = "0123456789abcdef";
    putchar(h[b >> 4]);
    putchar(h[b & 0xf]);
}

static void emit_uint(unsigned int v)
{
    char buf[12]; int i = 0;
    if (v == 0) { putchar('0'); return; }
    while (v) { buf[i++] = (char)('0' + v % 10); v /= 10; }
    while (i--) putchar((unsigned char)buf[i]);
}

static void emit_uint64(uint64_t v)
{
    char buf[22]; int i = 0;
    if (v == 0) { putchar('0'); return; }
    while (v) { buf[i++] = (char)('0' + (int)(v % 10)); v /= 10; }
    while (i--) putchar((unsigned char)buf[i]);
}

static void print_hex(const char *tag, const uint8_t *buf, size_t len)
{
    size_t i;
    emit(tag); putchar(' ');
    for (i = 0; i < len; i++) {
        emit_hex_byte(buf[i]);
        if ((i + 1) % 32 == 0 && (i + 1) < len) putchar(' ');
    }
    putchar('\r'); putchar('\n');
}

/* Emit cycles only */
static void emit_cycles(const char *tag, uint64_t cycles)
{
    emit("[CYCLES] ");
    emit(tag);
    emit(" = ");
    emit_uint64(cycles);
    emit(" cycles\r\n");
}

/* Emit instructions only */
static void emit_instructions(const char *tag, uint64_t instructions)
{
    emit("[INSTRUCTIONS] ");
    emit(tag);
    emit(" = ");
    emit_uint64(instructions);
    emit(" instr\r\n");
}

/* Emit time in microseconds */
static void emit_time_us(const char *tag, uint64_t cycles)
{
    emit("[TIME_US] ");
    emit(tag);
    emit(" = ");
    emit_uint64(CYCLES_TO_US(cycles));
    emit(" us\r\n");
}

/* Emit all three metrics together */
static void emit_all_metrics(const char *op_name, uint64_t cycles, uint64_t instructions)
{
    emit("\r\n=== ");
    emit(op_name);
    emit(" ===\r\n");
    
    emit_cycles(op_name, cycles);
    emit_instructions(op_name, instructions);
    emit_time_us(op_name, cycles);
    
    /* Calculate CPI (Cycles Per Instruction) if instructions > 0 */
    if (instructions > 0) {
        uint64_t cpi_num = cycles * 1000 / instructions;  /* Fixed-point with 3 decimal places */
        emit("[CPI] ");
        emit(op_name);
        emit(" = ");
        emit_uint64(cpi_num / 1000);
        emit(".");
        emit_uint64(cpi_num % 1000);
        emit(" cycles/instr\r\n");
    }
    emit("\r\n");
}

/* ------------------------------------------------------------------ */
/* Test 1: keygen + enc + dec                                          */
/* ------------------------------------------------------------------ */
static int test_keys(unsigned int iter)
{
    perf_metrics_t start, end;
    uint64_t cyc_keygen, cyc_enc, cyc_dec;
    uint64_t instr_keygen, instr_enc, instr_dec;

    emit("[KYBER] TEST "); emit_uint(iter + 1); emit(" START\r\n");

    randombytes(g_seed, KYBER_SEED_BYTES);
    print_hex("[SEED] ", g_seed, KYBER_SEED_BYTES);

    /* --- keygen --- */
    read_perf_metrics(&start);
    crypto_kem_keypair(g_pk, g_sk);
    read_perf_metrics(&end);
    cyc_keygen = end.cycles - start.cycles;
    instr_keygen = end.instructions - start.instructions;
    print_hex("[PK]   ", g_pk, CRYPTO_PUBLICKEYBYTES);
    print_hex("[SK]   ", g_sk, CRYPTO_SECRETKEYBYTES);
    emit_all_metrics("keygen", cyc_keygen, instr_keygen);

    /* --- encapsulate --- */
    read_perf_metrics(&start);
    crypto_kem_enc(g_ct, g_key_b, g_pk);
    read_perf_metrics(&end);
    cyc_enc = end.cycles - start.cycles;
    instr_enc = end.instructions - start.instructions;
    print_hex("[CT]   ", g_ct,    CRYPTO_CIPHERTEXTBYTES);
    print_hex("[KB]   ", g_key_b, CRYPTO_BYTES);
    emit_all_metrics("enc", cyc_enc, instr_enc);

    /* --- decapsulate --- */
    read_perf_metrics(&start);
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    read_perf_metrics(&end);
    cyc_dec = end.cycles - start.cycles;
    instr_dec = end.instructions - start.instructions;
    print_hex("[KA]   ", g_key_a, CRYPTO_BYTES);
    emit_all_metrics("dec", cyc_dec, instr_dec);

    emit_all_metrics("total", cyc_keygen + cyc_enc + cyc_dec, 
                     instr_keygen + instr_enc + instr_dec);

    if (memcmp(g_key_a, g_key_b, CRYPTO_BYTES)) {
        emit("[MATCH] KA != KB  FAIL\r\n");
        return 1;
    }
    emit("[MATCH] KA == KB  PASS\r\n");
    return 0;
}

/* ------------------------------------------------------------------ */
/* Test 2: corrupted secret key must produce mismatch                  */
/* ------------------------------------------------------------------ */
static int test_invalid_sk(void)
{
    perf_metrics_t start, end;
    uint64_t cyc_dec;
    uint64_t instr_dec;

    crypto_kem_keypair(g_pk, g_sk);
    crypto_kem_enc(g_ct, g_key_b, g_pk);

    print_hex("[SK_ORIG_0_31] ", g_sk, 32);
    randombytes(g_sk, CRYPTO_SECRETKEYBYTES);
    print_hex("[BAD_SK]       ", g_sk, 32);

    read_perf_metrics(&start);
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    read_perf_metrics(&end);
    cyc_dec = end.cycles - start.cycles;
    instr_dec = end.instructions - start.instructions;
    
    print_hex("[KA_BAD_SK]    ", g_key_a, CRYPTO_BYTES);
    emit_all_metrics("dec(bad_sk)", cyc_dec, instr_dec);

    if (!memcmp(g_key_a, g_key_b, CRYPTO_BYTES)) {
        emit("[INVALID_SK] keys matched with bad sk  FAIL\r\n");
        return 1;
    }
    emit("[INVALID_SK] key mismatch as expected  PASS\r\n");
    return 0;
}

/* ------------------------------------------------------------------ */
/* Test 3: corrupted ciphertext must produce mismatch                  */
/* ------------------------------------------------------------------ */
static int test_invalid_ciphertext(void)
{
    uint8_t  flip_byte;
    size_t   flip_pos;
    perf_metrics_t start, end;
    uint64_t cyc_dec;
    uint64_t instr_dec;

    do { randombytes(&flip_byte, 1); } while (!flip_byte);
    randombytes((uint8_t *)&flip_pos, sizeof(size_t));
    flip_pos = flip_pos % CRYPTO_CIPHERTEXTBYTES;

    crypto_kem_keypair(g_pk, g_sk);
    crypto_kem_enc(g_ct, g_key_b, g_pk);

    emit("[FLIP] pos="); emit_uint((unsigned)flip_pos);
    emit(" byte=0x"); emit_hex_byte(flip_byte); emit("\r\n");

    g_ct[flip_pos] ^= flip_byte;
    print_hex("[CT_BAD]    ", g_ct, CRYPTO_CIPHERTEXTBYTES);

    read_perf_metrics(&start);
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    read_perf_metrics(&end);
    cyc_dec = end.cycles - start.cycles;
    instr_dec = end.instructions - start.instructions;
    
    print_hex("[KA_BAD_CT] ", g_key_a, CRYPTO_BYTES);
    emit_all_metrics("dec(bad_ct)", cyc_dec, instr_dec);

    if (!memcmp(g_key_a, g_key_b, CRYPTO_BYTES)) {
        emit("[INVALID_CT] keys matched with bad ct  FAIL\r\n");
        return 1;
    }
    emit("[INVALID_CT] key mismatch as expected  PASS\r\n");
    return 0;
}

/* ------------------------------------------------------------------ */
/* main                                                                 */
/* ------------------------------------------------------------------ */
int main(void)
{
    unsigned int i;
    int r;
    perf_metrics_t start, end;
    uint64_t total_cycles, total_instructions;

    emit("[DBG] main: entered\r\n");

#ifdef CUSTOM
    emit("[KYBER] NTT path: HARDWARE\r\n");
#else
    emit("[KYBER] NTT path: SOFTWARE\r\n");
#endif
    emit("[KYBER] CPU_HZ                 = "); emit_uint(CPU_HZ);                 emit("\r\n");
    emit("[KYBER] NTESTS                 = "); emit_uint(NTESTS);                 emit("\r\n");
    emit("[KYBER] KYBER_SEED_BYTES       = "); emit_uint(KYBER_SEED_BYTES);       emit("\r\n");
    emit("[KYBER] CRYPTO_PUBLICKEYBYTES  = "); emit_uint(CRYPTO_PUBLICKEYBYTES);  emit("\r\n");
    emit("[KYBER] CRYPTO_SECRETKEYBYTES  = "); emit_uint(CRYPTO_SECRETKEYBYTES);  emit("\r\n");
    emit("[KYBER] CRYPTO_CIPHERTEXTBYTES = "); emit_uint(CRYPTO_CIPHERTEXTBYTES); emit("\r\n");
    emit("[KYBER] CRYPTO_BYTES           = "); emit_uint(CRYPTO_BYTES);           emit("\r\n");
    emit("\r\n");

    read_perf_metrics(&start);

    for (i = 0; i < NTESTS; i++) {

        r = test_keys(i);
        if (r) { emit("[KYBER] FAILED test_keys\r\n"); return 1; }

        r = test_invalid_sk();
        if (r) { emit("[KYBER] FAILED test_invalid_sk\r\n"); return 1; }

        r = test_invalid_ciphertext();
        if (r) { emit("[KYBER] FAILED test_invalid_ciphertext\r\n"); return 1; }

        emit("[KYBER] TEST "); emit_uint(i + 1); emit(" END\r\n");
        emit("----------------------------------------\r\n");
    }

    read_perf_metrics(&end);
    total_cycles = end.cycles - start.cycles;
    total_instructions = end.instructions - start.instructions;
    
    emit("\r\n=== FINAL SUMMARY ===\r\n");
    emit_all_metrics("all_tests", total_cycles, total_instructions);
    
    emit("[KYBER] ALL TESTS PASSED\r\n");
    return 0;
}
