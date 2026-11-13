#include "fixed.h"

/* XOR adds without carries; AND << 1 gives the carries. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        ++*n;
    }
    return a;
}

/* The budget asks for a plain subtraction, not the op1 model. */
uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/* a + b = (a ^ b) + 2(a & b), so halve only the XOR part. */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

/* Unsigned 16-bit partial products, then a sign fix in the high word.
 * Only bits 20..51 of the sum are kept, so unsigned shifts are enough.
 */
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFF, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFF, bh = ub >> 16;

    /* the two cross terms can reach 2^33, so add them in 64 bits */
    uint64_t mid = (uint64_t) (al * bh) + ah * bl;
    uint64_t p = ((uint64_t) (ah * bh) << 32) + (mid << 16) + al * bl;

    /* A * B = ua * ub - 2^32 (ub if a < 0, ua if b < 0), mod 2^64 */
    if (a < 0)
        p -= (uint64_t) ub << 32;
    if (b < 0)
        p -= (uint64_t) ua << 32;

    uint32_t r = (uint32_t) ((p + (1u << (Q - 1))) >> Q);
    return (int32_t) r;
}
