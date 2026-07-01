/*
 * PQCgenKAT_kem_baremetal.c
 *
 * Bare-metal port of the NIST KAT generator for Kyber-768.
 * Runs 1 iteration (count=0) and prints output over UART via putchar().
 *
 * No filesystem, no printf, no OpenSSL — pure bare-metal.
 *
 * Output format matches the official NIST .rsp file so it can be
 * diffed directly against PQCkemKAT_2400.rsp (count=0 entry only).
 *
 * NIST seed: entropy_input = {0x00, 0x01, ..., 0x2F} (48 bytes)
 */

#include <stddef.h>
#include <string.h>
#include "../kem.h"
#include "rng.h"

/* ------------------------------------------------------------------ */
/* UART output helpers — putchar() only                                */
/* ------------------------------------------------------------------ */
static void emit(const char *s)
{
    while (*s) putchar((unsigned char)*s++);
}

static void emit_uint(unsigned int v)
{
    char buf[12]; int i = 0;
    if (v == 0) { putchar('0'); return; }
    while (v) { buf[i++] = (char)('0' + v % 10); v /= 10; }
    while (i--) putchar((unsigned char)buf[i]);
}

/* print a byte array in UPPERCASE hex — matches NIST .rsp format */
static void emit_hex_upper(const unsigned char *buf, unsigned long long len)
{
    static const char h[] = "0123456789ABCDEF";
    unsigned long long i;
    for (i = 0; i < len; i++) {
        putchar(h[buf[i] >> 4]);
        putchar(h[buf[i] & 0xf]);
    }
    if (len == 0) { putchar('0'); putchar('0'); }
}

/* print "LABEL = HEXDATA\n" — matches .rsp format exactly */
static void emit_field(const char *label, const unsigned char *buf,
                       unsigned long long len)
{
    emit(label);
    emit(" = ");
    emit_hex_upper(buf, len);
    emit("\n");
}

/* Busy-wait for UART TX FIFO to drain before $finish */
static void uart_drain(void)
{
    volatile int d = 500000;
    while (d--);
}

/* ------------------------------------------------------------------ */
/* main                                                                 */
/* ------------------------------------------------------------------ */
int main(void)
{
    unsigned char entropy_input[48];
    unsigned char seed[48];
    unsigned char pk[CRYPTO_PUBLICKEYBYTES];
    unsigned char sk[CRYPTO_SECRETKEYBYTES];
    unsigned char ct[CRYPTO_CIPHERTEXTBYTES];
    unsigned char ss[CRYPTO_BYTES];
    unsigned char ss1[CRYPTO_BYTES];
    int i, ret;

    emit("[KAT] Starting NIST KAT (1 iteration)\n");
    emit("[KAT] CRYPTO_PUBLICKEYBYTES  = "); emit_uint(CRYPTO_PUBLICKEYBYTES);  emit("\n");
    emit("[KAT] CRYPTO_SECRETKEYBYTES  = "); emit_uint(CRYPTO_SECRETKEYBYTES);  emit("\n");
    emit("[KAT] CRYPTO_CIPHERTEXTBYTES = "); emit_uint(CRYPTO_CIPHERTEXTBYTES); emit("\n");
    emit("[KAT] CRYPTO_BYTES           = "); emit_uint(CRYPTO_BYTES);            emit("\n\n");

    /* NIST standard entropy input: 0x00 0x01 ... 0x2F */
    for (i = 0; i < 48; i++)
        entropy_input[i] = (unsigned char)i;

    randombytes_init(entropy_input, NULL, 256);

    /* Get the seed for count=0 */
    randombytes(seed, 48);

    /* Print .rsp header */
    emit("# Kyber-768\n\n");
    emit("count = 0\n");
    emit_field("seed", seed, 48);

    /* Re-initialise DRBG with this seed (as NIST KAT requires) */
    randombytes_init(seed, NULL, 256);

    /* keygen */
    ret = crypto_kem_keypair(pk, sk);
    if (ret != 0) {
        emit("[KAT] ERROR: crypto_kem_keypair failed\n");
        uart_drain();
        return 1;
    }
    emit_field("pk", pk, CRYPTO_PUBLICKEYBYTES);
    emit_field("sk", sk, CRYPTO_SECRETKEYBYTES);

    /* encap */
    ret = crypto_kem_enc(ct, ss, pk);
    if (ret != 0) {
        emit("[KAT] ERROR: crypto_kem_enc failed\n");
        uart_drain();
        return 1;
    }
    emit_field("ct", ct, CRYPTO_CIPHERTEXTBYTES);
    emit_field("ss", ss, CRYPTO_BYTES);
    emit("\n");

    /* decap and verify */
    ret = crypto_kem_dec(ss1, ct, sk);
    if (ret != 0) {
        emit("[KAT] ERROR: crypto_kem_dec failed\n");
        uart_drain();
        return 1;
    }
    if (memcmp(ss, ss1, CRYPTO_BYTES)) {
        emit("[KAT] ERROR: ss mismatch after decap\n");
        uart_drain();
        return 1;
    }

    emit("[KAT] count=0 PASSED — ss matches after decap\n");
    emit("[KAT] Compare pk/sk/ct/ss above against PQCkemKAT_2400.rsp count=0\n");

    uart_drain();
    return 0;
}
