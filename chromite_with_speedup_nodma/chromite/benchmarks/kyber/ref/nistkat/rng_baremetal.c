/*
 * rng_baremetal.c
 *
 * Drop-in replacement for the NIST rng.c that uses OpenSSL.
 * This version implements AES-256-ECB in pure C with no external dependencies,
 * suitable for bare-metal RISC-V simulation.
 *
 * AES implementation is a compact, public-domain implementation.
 * DRBG logic is identical to the original NIST rng.c.
 */

#include <string.h>
#include "rng.h"

/* ------------------------------------------------------------------ */
/* Compact AES-256 implementation (public domain)                      */
/* ------------------------------------------------------------------ */

static const uint8_t sbox[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

static const uint8_t rcon[11] = {
    0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36
};

static uint8_t xtime(uint8_t x) {
    return (x & 0x80) ? ((x << 1) ^ 0x1b) : (x << 1);
}

static uint8_t gmul(uint8_t a, uint8_t b) {
    uint8_t p = 0;
    int i;
    for (i = 0; i < 8; i++) {
        if (b & 1) p ^= a;
        a = xtime(a);
        b >>= 1;
    }
    return p;
}

/* AES-256 key schedule + encrypt one 16-byte block (ECB) */
static void aes256_ecb_encrypt(const uint8_t *key, const uint8_t *in, uint8_t *out)
{
    uint8_t rk[15][4][4];  /* 15 round keys for AES-256 */
    uint8_t state[4][4];
    int r, c, i;

    /* Key expansion */
    for (r = 0; r < 8; r++)
        for (c = 0; c < 4; c++)
            rk[0][r < 4 ? r : r][c < 4 ? c : c] = 0; /* silence warning */

    /* Load first 8 words directly */
    uint8_t w[60][4];
    for (i = 0; i < 8; i++)
        for (c = 0; c < 4; c++)
            w[i][c] = key[i*4+c];

    for (i = 8; i < 60; i++) {
        uint8_t temp[4];
        for (c = 0; c < 4; c++) temp[c] = w[i-1][c];
        if (i % 8 == 0) {
            /* RotWord + SubWord + Rcon */
            uint8_t t = temp[0];
            temp[0] = sbox[temp[1]] ^ rcon[i/8];
            temp[1] = sbox[temp[2]];
            temp[2] = sbox[temp[3]];
            temp[3] = sbox[t];
        } else if (i % 8 == 4) {
            for (c = 0; c < 4; c++) temp[c] = sbox[temp[c]];
        }
        for (c = 0; c < 4; c++) w[i][c] = w[i-8][c] ^ temp[c];
    }

    /* Load state (column-major) */
    for (r = 0; r < 4; r++)
        for (c = 0; c < 4; c++)
            state[r][c] = in[r + 4*c];

    /* Initial AddRoundKey */
    for (r = 0; r < 4; r++)
        for (c = 0; c < 4; c++)
            state[r][c] ^= w[c][r];

    /* 13 full rounds + 1 final */
    int round;
    for (round = 1; round <= 14; round++) {
        /* SubBytes */
        for (r = 0; r < 4; r++)
            for (c = 0; c < 4; c++)
                state[r][c] = sbox[state[r][c]];

        /* ShiftRows */
        uint8_t tmp;
        tmp=state[1][0]; state[1][0]=state[1][1]; state[1][1]=state[1][2]; state[1][2]=state[1][3]; state[1][3]=tmp;
        tmp=state[2][0]; state[2][0]=state[2][2]; state[2][2]=tmp; tmp=state[2][1]; state[2][1]=state[2][3]; state[2][3]=tmp;
        tmp=state[3][3]; state[3][3]=state[3][2]; state[3][2]=state[3][1]; state[3][1]=state[3][0]; state[3][0]=tmp;

        /* MixColumns (skip on last round) */
        if (round < 14) {
            for (c = 0; c < 4; c++) {
                uint8_t s0=state[0][c],s1=state[1][c],s2=state[2][c],s3=state[3][c];
                state[0][c] = gmul(0x02,s0)^gmul(0x03,s1)^s2^s3;
                state[1][c] = s0^gmul(0x02,s1)^gmul(0x03,s2)^s3;
                state[2][c] = s0^s1^gmul(0x02,s2)^gmul(0x03,s3);
                state[3][c] = gmul(0x03,s0)^s1^s2^gmul(0x02,s3);
            }
        }

        /* AddRoundKey */
        int woff = round * 4;
        for (r = 0; r < 4; r++)
            for (c = 0; c < 4; c++)
                state[r][c] ^= w[woff+c][r];
    }

    /* Store state */
    for (r = 0; r < 4; r++)
        for (c = 0; c < 4; c++)
            out[r + 4*c] = state[r][c];
}

/* ------------------------------------------------------------------ */
/* NIST AES256_ECB wrapper (matches original rng.c signature)          */
/* ------------------------------------------------------------------ */
void AES256_ECB(unsigned char *key, unsigned char *ctr, unsigned char *buffer)
{
    aes256_ecb_encrypt(key, ctr, buffer);
}

/* ------------------------------------------------------------------ */
/* The rest is identical to the original NIST rng.c                    */
/* ------------------------------------------------------------------ */

AES256_CTR_DRBG_struct  DRBG_ctx;

void
AES256_CTR_DRBG_Update(unsigned char *provided_data,
                       unsigned char *Key,
                       unsigned char *V)
{
    unsigned char   temp[48];
    int             i, j;

    for (i = 0; i < 3; i++) {
        /* increment V */
        for (j = 15; j >= 0; j--) {
            if (V[j] == 0xff)
                V[j] = 0x00;
            else {
                V[j]++;
                break;
            }
        }
        AES256_ECB(Key, V, temp+16*i);
    }
    if (provided_data != NULL)
        for (i = 0; i < 48; i++)
            temp[i] ^= provided_data[i];
    memcpy(Key, temp, 32);
    memcpy(V, temp+32, 16);
}

void
randombytes_init(unsigned char *entropy_input,
                 unsigned char *personalization_string,
                 int security_strength)
{
    unsigned char   seed_material[48];
    int             i;

    (void)security_strength;
    memcpy(seed_material, entropy_input, 48);
    if (personalization_string)
        for (i = 0; i < 48; i++)
            seed_material[i] ^= personalization_string[i];
    memset(DRBG_ctx.Key, 0x00, 32);
    memset(DRBG_ctx.V,   0x00, 16);
    AES256_CTR_DRBG_Update(seed_material, DRBG_ctx.Key, DRBG_ctx.V);
    DRBG_ctx.reseed_counter = 1;
}

int
randombytes(unsigned char *x, unsigned long long xlen)
{
    unsigned char   block[16];
    int             i, j;

    while (xlen > 0) {
        /* increment V */
        for (j = 15; j >= 0; j--) {
            if (DRBG_ctx.V[j] == 0xff)
                DRBG_ctx.V[j] = 0x00;
            else {
                DRBG_ctx.V[j]++;
                break;
            }
        }
        AES256_ECB(DRBG_ctx.Key, DRBG_ctx.V, block);
        if (xlen > 15) {
            memcpy(x, block, 16);
            x    += 16;
            xlen -= 16;
        } else {
            memcpy(x, block, xlen);
            xlen = 0;
        }
    }
    AES256_CTR_DRBG_Update(NULL, DRBG_ctx.Key, DRBG_ctx.V);
    DRBG_ctx.reseed_counter++;
    return 0;  /* RNG_SUCCESS */
}

int
seedexpander_init(AES_XOF_struct *ctx,
                  unsigned char *seed,
                  unsigned char *diversifier,
                  unsigned long maxlen)
{
    (void)maxlen;
    ctx->length_remaining = maxlen;
    memcpy(ctx->key, seed, 32);
    memcpy(ctx->ctr, diversifier, 8);
    memset(ctx->ctr+8, 0x00, 4);
    ctx->ctr[12] = (maxlen >> 24) & 0xff;
    ctx->ctr[13] = (maxlen >> 16) & 0xff;
    ctx->ctr[14] = (maxlen >>  8) & 0xff;
    ctx->ctr[15] =  maxlen        & 0xff;
    ctx->buffer_pos = 16;
    memset(ctx->buffer, 0x00, 16);
    return 0;  /* RNG_SUCCESS */
}

int
seedexpander(AES_XOF_struct *ctx, unsigned char *x, unsigned long xlen)
{
    unsigned long   offset;

    if (!x || xlen > ctx->length_remaining)
        return -2;  /* RNG_BAD_OUTBUF / RNG_BAD_REQ_LEN */

    ctx->length_remaining -= xlen;
    offset = 0;
    while (xlen > 0) {
        if (xlen <= (unsigned long)(16 - ctx->buffer_pos)) {
            memcpy(x+offset, ctx->buffer+ctx->buffer_pos, xlen);
            ctx->buffer_pos += xlen;
            return 0;
        }
        memcpy(x+offset, ctx->buffer+ctx->buffer_pos, 16-ctx->buffer_pos);
        xlen   -= 16 - ctx->buffer_pos;
        offset += 16 - ctx->buffer_pos;

        /* generate next block */
        int j;
        for (j = 15; j >= 12; j--) {
            if (ctx->ctr[j] == 0xff)
                ctx->ctr[j] = 0x00;
            else {
                ctx->ctr[j]++;
                break;
            }
        }
        AES256_ECB(ctx->key, ctx->ctr, ctx->buffer);
        ctx->buffer_pos = 0;
    }
    return 0;
}
