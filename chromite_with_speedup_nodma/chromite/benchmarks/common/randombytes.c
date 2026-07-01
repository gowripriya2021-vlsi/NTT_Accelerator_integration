#include <stdint.h>
#include <stddef.h>

// Simple LFSR-based PRNG for bare-metal testing (not cryptographically secure)
static uint64_t rng_state = 0xDEADBEEFCAFEBABEULL;

static uint64_t xorshift64(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}

void randombytes(uint8_t *out, size_t outlen) {
    size_t i = 0;
    uint64_t val;
    for (; i + 8 <= outlen; i += 8) {
        val = xorshift64();
        out[i+0] = (val >>  0) & 0xFF;
        out[i+1] = (val >>  8) & 0xFF;
        out[i+2] = (val >> 16) & 0xFF;
        out[i+3] = (val >> 24) & 0xFF;
        out[i+4] = (val >> 32) & 0xFF;
        out[i+5] = (val >> 40) & 0xFF;
        out[i+6] = (val >> 48) & 0xFF;
        out[i+7] = (val >> 56) & 0xFF;
    }
    if (i < outlen) {
        val = xorshift64();
        for (; i < outlen; i++) {
            out[i] = val & 0xFF;
            val >>= 8;
        }
    }
}
