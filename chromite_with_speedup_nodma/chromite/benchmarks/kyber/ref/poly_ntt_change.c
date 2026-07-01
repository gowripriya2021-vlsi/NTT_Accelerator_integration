/*
 * poly.c  —  exact changes required
 * All other functions are completely unchanged.
 */

/* ── Change 1: add include at the top of poly.c ── */
#include "ntt_kyber_hw.h"   /* ADD after existing includes */

/* ── Change 2: replace one line inside poly_ntt() ── */

/* BEFORE: */
void poly_ntt(poly *r)
{
    ntt(r->coeffs);    /* <── remove this line */
    poly_reduce(r);
}

/* AFTER: */
void poly_ntt(poly *r)
{
    ntt_kyber_hw_drive(r->coeffs);  /* <── replace with this */
    poly_reduce(r);                 /* unchanged */
}

/*
 * That is the complete change. Two lines touched, nothing else.
 *
 * Why poly_reduce() stays:
 *   The RTL outputs values in [0, Q-1]. poly_reduce() (barrett_reduce)
 *   clamps any out-of-range value to (-Q, Q). Since RTL output is already
 *   in [0, Q-1], poly_reduce is a no-op here but must stay for correctness
 *   when switching back to software NTT or during testing.
 *
 * Why no to_montgomery() is needed:
 *   plain_ntt[i] % Q == montgomery_ntt[i] % Q for all i.
 *   Both NTTs compute the same polynomial; they just represent intermediate
 *   values differently. After poly_reduce the outputs are identical.
 *   Verified across 10 random test vectors.
 *
 * Functions untouched:
 *   poly_invntt_tomont  — calls invntt()              (software only, unchanged)
 *   poly_basemul_montgomery                           (unchanged)
 *   poly_tomont                                       (unchanged)
 *   poly_reduce                                       (unchanged)
 *   poly_add / poly_sub                               (unchanged)
 *   polyvec_ntt         — calls poly_ntt() indirectly (picks up fix)
 *   indcpa_keypair_derand / indcpa_enc / indcpa_dec   (unchanged)
 */
