/*
 * test_kyber.c — Kyber-768 testbench
 *
 * Output goes exclusively through putchar() -> UART TX poll at 0x1130C.
 * No printf, no fflush, no newlib stdio buffering — those route through
 * tohost/fromhost which is not needed here.
 *
 * Cycle timing uses the RISC-V mcycle / mcycleh CSRs (read via rdcycle /
 * rdcycleh).  CPU_HZ MUST be defined at compile time to match your core
 * frequency so that cycle counts are converted to microseconds:
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

/* cycles_to_us: integer µs, no floating point */
#define CYCLES_TO_US(c)  ((uint64_t)(c) / ((uint64_t)CPU_HZ / 1000000ULL))

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
/* Cycle counter — RISC-V mcycle CSR (64-bit, read as two 32-bit      */
/* halves on RV32 to avoid mid-read carry glitch)                      */
/* ------------------------------------------------------------------ */
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

/* print "[TIME] <tag> = <us> us" */
static void emit_time_us(const char *tag, uint64_t cycles)
{
    emit("[TIME] ");
    emit(tag);
    emit(" = ");
    emit_uint64(CYCLES_TO_US(cycles));
    emit(" us\r\n");
}

/* ------------------------------------------------------------------ */
/* Test 1: keygen + enc + dec                                          */
/* ------------------------------------------------------------------ */
static int test_keys(unsigned int iter)
{
    uint64_t t0, t1;
    uint64_t cyc_keygen, cyc_enc, cyc_dec;

    emit("[KYBER] TEST "); emit_uint(iter + 1); emit(" START\r\n");

    randombytes(g_seed, KYBER_SEED_BYTES);
    print_hex("[SEED] ", g_seed, KYBER_SEED_BYTES);

    /* --- keygen --- */
    t0 = read_cycles();
    crypto_kem_keypair(g_pk, g_sk);
    t1 = read_cycles();
    cyc_keygen = t1 - t0;
    print_hex("[PK]   ", g_pk, CRYPTO_PUBLICKEYBYTES);
    print_hex("[SK]   ", g_sk, CRYPTO_SECRETKEYBYTES);
    emit_time_us("keygen ", cyc_keygen);

    /* --- encapsulate --- */
    t0 = read_cycles();
    crypto_kem_enc(g_ct, g_key_b, g_pk);
    t1 = read_cycles();
    cyc_enc = t1 - t0;
    print_hex("[CT]   ", g_ct,    CRYPTO_CIPHERTEXTBYTES);
    print_hex("[KB]   ", g_key_b, CRYPTO_BYTES);
    emit_time_us("enc    ", cyc_enc);

    /* --- decapsulate --- */
    t0 = read_cycles();
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    t1 = read_cycles();
    cyc_dec = t1 - t0;
    print_hex("[KA]   ", g_key_a, CRYPTO_BYTES);
    emit_time_us("dec    ", cyc_dec);

    emit_time_us("total  ", cyc_keygen + cyc_enc + cyc_dec);

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
    uint64_t t0, t1;

    crypto_kem_keypair(g_pk, g_sk);
    crypto_kem_enc(g_ct, g_key_b, g_pk);

    print_hex("[SK_ORIG_0_31] ", g_sk, 32);
    randombytes(g_sk, CRYPTO_SECRETKEYBYTES);
    print_hex("[BAD_SK]       ", g_sk, 32);

    t0 = read_cycles();
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    t1 = read_cycles();
    print_hex("[KA_BAD_SK]    ", g_key_a, CRYPTO_BYTES);
    emit_time_us("dec(bad_sk)", t1 - t0);

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
    uint64_t t0, t1;

    do { randombytes(&flip_byte, 1); } while (!flip_byte);
    randombytes((uint8_t *)&flip_pos, sizeof(size_t));
    flip_pos = flip_pos % CRYPTO_CIPHERTEXTBYTES;

    crypto_kem_keypair(g_pk, g_sk);
    crypto_kem_enc(g_ct, g_key_b, g_pk);

    emit("[FLIP] pos="); emit_uint((unsigned)flip_pos);
    emit(" byte=0x"); emit_hex_byte(flip_byte); emit("\r\n");

    g_ct[flip_pos] ^= flip_byte;
    print_hex("[CT_BAD]    ", g_ct, CRYPTO_CIPHERTEXTBYTES);

    t0 = read_cycles();
    crypto_kem_dec(g_key_a, g_ct, g_sk);
    t1 = read_cycles();
    print_hex("[KA_BAD_CT] ", g_key_a, CRYPTO_BYTES);
    emit_time_us("dec(bad_ct)", t1 - t0);

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
    uint64_t t_main_start, t_iter_start, t_now;

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

    t_main_start = read_cycles();

    for (i = 0; i < NTESTS; i++) {

        t_iter_start = read_cycles();

        r = test_keys(i);
        if (r) { emit("[KYBER] FAILED test_keys\r\n"); return 1; }

        r = test_invalid_sk();
        if (r) { emit("[KYBER] FAILED test_invalid_sk\r\n"); return 1; }

        r = test_invalid_ciphertext();
        if (r) { emit("[KYBER] FAILED test_invalid_ciphertext\r\n"); return 1; }

        t_now = read_cycles();
        emit("[KYBER] TEST "); emit_uint(i + 1); emit(" END\r\n");
        emit_time_us("iter total ", t_now - t_iter_start);
    }

    t_now = read_cycles();
    emit_time_us("all iters  ", t_now - t_main_start);
    emit("[KYBER] ALL TESTS PASSED\r\n");
    return 0;
}
