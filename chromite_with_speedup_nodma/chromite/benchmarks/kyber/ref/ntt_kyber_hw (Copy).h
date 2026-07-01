#ifndef NTT_KYBER_HW_H
#define NTT_KYBER_HW_H

#include <stdint.h>

/*
 * ntt_kyber_hw_drive()
 *
 * Full hardware NTT transaction. Drop-in replacement for ntt() in poly.c.
 *
 * Input:  poly[256] normal order, int16_t, values in [-ETA, Q-1]
 * Output: poly[256] Kyber bit-reversed NTT order, values in [0, Q-1]
 *
 * The output is in the SAME form as ntt.c's output after poly_reduce().
 * No Montgomery conversion is needed — plain mod-Q == Montgomery mod-Q.
 */
void ntt_kyber_hw_drive(int16_t poly[256]);

#endif


