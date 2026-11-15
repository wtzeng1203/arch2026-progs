#include "bf16.h"

/* BFloat16 routines in C, following the contract in bf16.h. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    /* Rounding an all-ones exponent could carry into the sign bit, so Inf
     * and NaN keep their top half unchanged.
     */
    if (((f32bits >> 23) & 0xFFu) == 0xFFu)
        return (uint16_t) (f32bits >> 16);

    f32bits += 0x7FFFu + ((f32bits >> 16) & 1u);
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (uint32_t) (a ^ b) & 0x8000u;
    uint32_t exp_a = (a >> 7) & 0xFFu, exp_b = (b >> 7) & 0xFFu;
    uint32_t mant_a = a & 0x7Fu, mant_b = b & 0x7Fu;

    /* a is examined before b, so an infinite a swallows a NaN b. */
    if (exp_a == 0xFFu) {
        if (mant_a)
            return a;
        if (!exp_b && !mant_b)
            return 0x7FC0u;
        return (uint16_t) (sign | 0x7F80u);
    }
    if (exp_b == 0xFFu) {
        if (mant_b)
            return b;
        if (!exp_a && !mant_a)
            return 0x7FC0u;
        return (uint16_t) (sign | 0x7F80u);
    }
    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return (uint16_t) sign;

    /* A denormal is shifted up to a leading one; exp_adjust undoes the
     * scaling in the exponent.
     */
    int32_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80u)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else {
        mant_a |= 0x80u;
    }
    if (!exp_b) {
        while (!(mant_b & 0x80u)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else {
        mant_b |= 0x80u;
    }

    uint32_t prod = mant_a * mant_b;
    int32_t result_exp = (int32_t) exp_a + (int32_t) exp_b - 127 + exp_adjust;

    /* The product lies in [2^14, 2^16); the dropped bits are truncated. */
    if (prod & 0x8000u) {
        prod = (prod >> 8) & 0x7Fu;
        result_exp++;
    } else {
        prod = (prod >> 7) & 0x7Fu;
    }

    if (result_exp >= 0xFF)
        return (uint16_t) (sign | 0x7F80u);
    if (result_exp <= 0) {
        if (result_exp < -6)
            return (uint16_t) sign;
        /* The hidden one is not shifted in: only the fraction moves. */
        prod >>= 1 - result_exp;
        result_exp = 0;
    }
    return (uint16_t) (sign | ((uint32_t) result_exp << 7) | prod);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exp = (a >> 7) & 0xFFu, mant = a & 0x7Fu;

    if (exp == 0xFFu) {
        if (mant || !(a & 0x8000u))
            return a;
        return 0x7FC0u;
    }
    /* Zero comes before the sign test, so -0 gives +0. */
    if (!exp && !mant)
        return 0;
    if (a & 0x8000u)
        return 0x7FC0u;
    if (!exp)
        return 0;

    /* The unbiased exponent E - 127 is odd exactly when E is even. Halving
     * it is (E + 127) >> 1 in both cases, which stays in [64, 190].
     */
    uint32_t m = mant | 0x80u;
    if (!(exp & 1u))
        m <<= 1;
    uint32_t new_exp = (exp + 127u) >> 1;

    /* Largest mid with (mid * mid) / 128 <= m. It always lies in [128, 255],
     * so the result needs no renormalization.
     */
    uint32_t low = 90, high = 256, result = 128;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if ((mid * mid) / 128 <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return (uint16_t) ((new_exp << 7) | (result & 0x7Fu));
}
