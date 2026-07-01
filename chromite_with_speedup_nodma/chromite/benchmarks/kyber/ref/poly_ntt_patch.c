/*
 * poly.c  —  only poly_ntt() needs to change.
 * Everything else (poly_invntt_tomont, poly_basemul_montgomery, …) is untouched.
 *
 * BEFORE (uses reference software NTT from ntt.c):
 * ─────────────────────────────────────────────────
 *   #include "ntt.h"
 *   ...
 *   void poly_ntt(poly *r) {
 *       ntt(r->coeffs);       // reference CT NTT, Montgomery arithmetic
 *       poly_reduce(r);
 *   }
 *
 *
 * AFTER (routes through the hardware accelerator model):
 * ───────────────────────────────────────────────────────
 *   #include "ntt.h"
 *   #include "ntt_kyber_hw.h"    // <── add this include
 *   ...
 *   void poly_ntt(poly *r) {
 *       ntt_kyber_hw_drive(r->coeffs);   // <── replaces ntt()
 *       poly_reduce(r);                  //     poly_reduce() stays
 *   }
 *
 *
 * Why poly_reduce() stays
 * ───────────────────────
 *   ntt_kyber_hw_drive() outputs coefficients in Montgomery form, same as
 *   the reference ntt().  poly_reduce() (Barrett reduction) is a safety
 *   step that clamps values to [0, Q-1] and must remain.
 *
 *
 * No other files need to change
 * ──────────────────────────────
 *   poly_invntt_tomont()       — calls invntt()          unchanged
 *   poly_basemul_montgomery()  — calls basemul()         unchanged
 *   poly_tomont()              — calls montgomery_reduce unchanged
 *   polyvec_ntt()              — calls poly_ntt()        unchanged (picks up fix automatically)
 *   indcpa_keypair_derand()    — calls polyvec_ntt()     unchanged
 *   indcpa_enc()               — calls polyvec_ntt()     unchanged
 *   indcpa_dec()               — calls polyvec_ntt()     unchanged
 *
 *
 * Build change
 * ─────────────
 *   Add ntt_kyber_hw.c to your Makefile / CMakeLists alongside the other
 *   Kyber source files.  The file has no new external dependencies beyond
 *   what Kyber already uses (params.h, reduce.h).
 *
 *
 * Swapping in the real RTL later
 * ───────────────────────────────
 *   1. Keep ntt_kyber_hw.h (the header / contract never changes).
 *   2. Replace ntt_kyber_hw.c with a new implementation that:
 *        a. Packs poly[256] onto the 14-bit-wide data_in bus
 *           (field i at bits [(255-i)*14 +: 14]).
 *        b. Asserts the start pin for one clock cycle.
 *        c. Waits for the done pulse (interrupt or poll).
 *        d. Unpacks the data_out bus back into poly[256].
 *        e. Runs the Montgomery re-encoding loop
 *               for i in 0..255: poly[i] = montgomery_reduce(poly[i] * f)
 *           (same as poly_tomont) unless the RTL is extended to output
 *           Montgomery form natively, in which case drop this loop.
 *   3. poly.c is untouched.
 */
