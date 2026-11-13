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

/* Dummy until q_mul is written. */
int32_t q_mul(int32_t a, int32_t b)
{
    (void) a;
    (void) b;
    return 0;
}
