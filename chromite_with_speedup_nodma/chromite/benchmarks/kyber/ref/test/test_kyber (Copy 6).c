/*
 * test_kyber.c — Kyber-768 testbench with cycle measurement only
 *
 * Output only shows total cycle counts for complete Kyber operations.
 * Uses existing putchar from syscalls.c
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
/* File-scope statics                                                */
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

typedef struct {
    uint64_t cycles;
    uint64_t instructions;
} perf_metrics_t;

static uint64_t read_cycles(void)
{
#if __riscv_xlen == 64
    uint64_t c;
    __asm__ volatile ("rdcycle %0" : "=r"(c));
    return c;
#else
    uint32_t lo, hi, hi2;
    do {
        __asm__ volatile ("rdcycleh %0" : "=r"(hi));
        __asm__ volatile ("rdcycle  %0" : "=r"(lo));
        __asm__ volatile ("rdcycleh %0" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
#endif
}

static inline void read_perf_metrics_start(perf_metrics_t *m)
{
    m->cycles = read_cycles();
}

static void read_perf_metrics_end(perf_metrics_t *m)
{
    m->cycles = read_cycles();
}

/* Use standard putchar from syscalls */
#define emit_char(c) putchar(c)

static void emit_uint64(uint64_t v)
{
    char buf[22]; int i = 0;
    if (v == 0) { emit_char('0'); return; }
    while (v) { buf[i++] = (char)('0' + (int)(v % 10)); v /= 10; }
    while (i--) emit_char(buf[i]);
}

static void emit_string(const char *s)
{
    while (*s) emit_char(*s++);
}

static void emit_newline(void)
{
    emit_char('\r');
    emit_char('\n');
}

/* ------------------------------------------------------------------ */
/* Test: complete Kyber operation (keygen + enc + dec)                */
/* Returns total cycles                                               */
/* ------------------------------------------------------------------ */
static uint64_t test_complete_kyber(unsigned int iter)
{
    perf_metrics_t start, end;
    uint64_t total_cycles = 0;
    
    /* Setup - not measured */
    randombytes(g_seed, KYBER_SEED_BYTES);
    
    /* ---- keygen ---- */
    read_perf_metrics_start(&start);
    crypto_kem_keypair(g_pk, g_sk);
    read_perf_metrics_end(&end);
    total_cycles += (end.cycles - start.cycles);
    
    /* ---- encapsulate ---- */
    read_perf_metrics_start(&start);
    crypto_kem_enc(g_ct, g_key_b, g_pk);
    read_perf_metrics_end(&end);
    total_cycles += (end.cycles - start.cycles);
    
    /* ---- decapsulate ---- */
    read_perf_metrics_start(&start);
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    read_perf_metrics_end(&end);
    total_cycles += (end.cycles - start.cycles);
    
    /* Verify correctness (not measured) */
    if (memcmp(g_key_a, g_key_b, CRYPTO_BYTES)) {
        emit_string("[FAIL] Key mismatch");
        emit_newline();
        return 0;
    }
    
    return total_cycles;
}

/* ------------------------------------------------------------------ */
/* Test: invalid secret key (decapsulate only)                        */
/* Returns cycles for decapsulation with bad key                      */
/* ------------------------------------------------------------------ */
static uint64_t test_invalid_sk(void)
{
    perf_metrics_t start, end;
    uint64_t dec_cycles;
    
    /* Use existing pk/sk/ct from test_complete_kyber */
    /* Corrupt SK (not measured) */
    randombytes(g_sk, CRYPTO_SECRETKEYBYTES);
    
    /* Measure only the dec call */
    read_perf_metrics_start(&start);
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    read_perf_metrics_end(&end);
    dec_cycles = end.cycles - start.cycles;
    
    /* Verify mismatch (not measured) */
    if (!memcmp(g_key_a, g_key_b, CRYPTO_BYTES)) {
        emit_string("[FAIL] Invalid SK test - keys matched");
        emit_newline();
        return 0;
    }
    
    return dec_cycles;
}

/* ------------------------------------------------------------------ */
/* Test: invalid ciphertext (decapsulate only)                        */
/* Returns cycles for decapsulation with bad ciphertext               */
/* ------------------------------------------------------------------ */
static uint64_t test_invalid_ciphertext(void)
{
    uint8_t flip_byte;
    size_t flip_pos;
    perf_metrics_t start, end;
    uint64_t dec_cycles;
    
    /* Regenerate valid keypair (not measured - setup cost) */
    crypto_kem_keypair(g_pk, g_sk);
    crypto_kem_enc(g_ct, g_key_b, g_pk);
    
    /* Flip one byte in ciphertext (not measured) */
    do { randombytes(&flip_byte, 1); } while (!flip_byte);
    randombytes((uint8_t *)&flip_pos, sizeof(size_t));
    flip_pos = flip_pos % CRYPTO_CIPHERTEXTBYTES;
    g_ct[flip_pos] ^= flip_byte;
    
    /* Measure only the dec call */
    read_perf_metrics_start(&start);
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    read_perf_metrics_end(&end);
    dec_cycles = end.cycles - start.cycles;
    
    /* Verify mismatch (not measured) */
    if (!memcmp(g_key_a, g_key_b, CRYPTO_BYTES)) {
        emit_string("[FAIL] Invalid CT test - keys matched");
        emit_newline();
        return 0;
    }
    
    return dec_cycles;
}

/* ------------------------------------------------------------------ */
/* main — minimal output only                                         */
/* ------------------------------------------------------------------ */
int main(void)
{
    unsigned int i;
    uint64_t total_cycles = 0;
    uint64_t invalid_sk_cycles = 0;
    uint64_t invalid_ct_cycles = 0;
    uint64_t keygen_cycles = 0, enc_cycles = 0, dec_cycles = 0;
    
    emit_string("MAIN STARTED");
    emit_newline();
    
    for (i = 0; i < NTESTS; i++) {
        /* Complete Kyber operation (keygen + enc + dec) */
        total_cycles = test_complete_kyber(i);
        if (total_cycles == 0) return 1;
        
        /* Invalid secret key test (decapsulate only) */
        invalid_sk_cycles = test_invalid_sk();
        if (invalid_sk_cycles == 0) return 1;
        
        /* Invalid ciphertext test (decapsulate only) */
        invalid_ct_cycles = test_invalid_ciphertext();
        if (invalid_ct_cycles == 0) return 1;
    }
    
    /* Get individual operation counts */
    perf_metrics_t start, end;
    
    randombytes(g_seed, KYBER_SEED_BYTES);
    
    read_perf_metrics_start(&start);
    crypto_kem_keypair(g_pk, g_sk);
    read_perf_metrics_end(&end);
    keygen_cycles = end.cycles - start.cycles;
    
    read_perf_metrics_start(&start);
    crypto_kem_enc(g_ct, g_key_b, g_pk);
    read_perf_metrics_end(&end);
    enc_cycles = end.cycles - start.cycles;
    
    read_perf_metrics_start(&start);
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    read_perf_metrics_end(&end);
    dec_cycles = end.cycles - start.cycles;
    
    /* Print only the total cycle counts */
    emit_newline();
    emit_string("=== KYBER PERFORMANCE SUMMARY ===");
    emit_newline();
    
    emit_string("Complete Kyber (keygen+enc+dec): ");
    emit_uint64(total_cycles);
    emit_string(" cycles");
    emit_newline();
    
    emit_string("Decapsulate with bad secret key: ");
    emit_uint64(invalid_sk_cycles);
    emit_string(" cycles");
    emit_newline();
    
    emit_string("Decapsulate with bad ciphertext: ");
    emit_uint64(invalid_ct_cycles);
    emit_string(" cycles");
    emit_newline();
    
    emit_newline();
    emit_string("=== CYCLES PER OPERATION ===");
    emit_newline();
    
    emit_string("Key generation: ");
    emit_uint64(keygen_cycles);
    emit_string(" cycles");
    emit_newline();
    
    emit_string("Encapsulation:  ");
    emit_uint64(enc_cycles);
    emit_string(" cycles");
    emit_newline();
    
    emit_string("Decapsulation:  ");
    emit_uint64(dec_cycles);
    emit_string(" cycles");
    emit_newline();
    
    /* Convert to microseconds */
    emit_newline();
    emit_string("=== TIME AT CURRENT FREQUENCY ===");
    emit_newline();
    emit_string("CPU_HZ: ");
    emit_uint64(CPU_HZ);
    emit_string(" Hz");
    emit_newline();
    
    emit_string("Complete Kyber time: ");
    emit_uint64(total_cycles / (CPU_HZ / 1000000ULL));
    emit_string(" us");
    emit_newline();
    
    emit_string("Key generation time: ");
    emit_uint64(keygen_cycles / (CPU_HZ / 1000000ULL));
    emit_string(" us");
    emit_newline();
    
    emit_string("Encapsulation time:  ");
    emit_uint64(enc_cycles / (CPU_HZ / 1000000ULL));
    emit_string(" us");
    emit_newline();
    
    emit_string("Decapsulation time:  ");
    emit_uint64(dec_cycles / (CPU_HZ / 1000000ULL));
    emit_string(" us");
    emit_newline();
    
    emit_newline();
    emit_string("=== END ===");
    emit_newline();
    
    /* Signal simulation to exit */
    extern volatile uint64_t tohost;
    tohost = 1;
    while (1) {}
    
    return 0;
}
