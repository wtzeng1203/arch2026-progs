#include "gcd.h"

/*
 * Binary GCD built from the four identities of Quiz 2 Problem A:
 *   gcd(0, b) = b
 *   gcd(2a, 2b) = 2 * gcd(a, b)
 *   gcd(2a, b) = gcd(a, b) when b is odd
 *   gcd(a, b) = gcd(a, b - a) when a and b are odd and b >= a
 * Only shifts, subtractions and comparisons are used: no multiply, no
 * divide, no remainder.
 */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    uint32_t shift = 0;

    /* Zero operands; this also keeps the loops below from spinning on 0. */
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    /* Strip and count the twos that a and b share. */
    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        shift++;
    }

    /* Make a odd; it stays odd from here on. */
    while ((a & 1u) == 0)
        a >>= 1;

    while (b != 0) {
        /* Make b odd. */
        while ((b & 1u) == 0)
            b >>= 1;
        /* Keep b >= a so the difference cannot wrap around. */
        if (b < a) {
            uint32_t tmp = a;
            a = b;
            b = tmp;
        }
        /* Odd minus odd is even, so b is even or zero after this. */
        b -= a;
    }

    /* Put the shared twos back; shift <= 31 because neither input is 0. */
    return a << shift;
}