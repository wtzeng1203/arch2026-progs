# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# Binary GCD built from the four identities of Quiz 2 Problem A:
#   gcd(0, b) = b
#   gcd(2a, 2b) = 2 * gcd(a, b)
#   gcd(2a, b) = gcd(a, b) when b is odd
#   gcd(a, b) = gcd(a, b - a) when a and b are odd and b >= a
# Only shifts, subtractions and comparisons are used: no multiply, no
# divide, no remainder.
#
# Registers: a0 = a and the result, a1 = b, t0 = shift, t1 = parity test,
# t2 = tmp for the swap.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    # Zero operands; this also keeps the loops below from spinning on 0.
    beq     a0, x0, .Lret_b
    beq     a1, x0, .Lret
    addi    t0, x0, 0

    # Strip and count the twos that a and b share.
.Lboth:
    or      t1, a0, a1
    andi    t1, t1, 1
    bne     t1, x0, .Lodd_a
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    jal     x0, .Lboth

    # Make a odd; it stays odd from here on.
.Lodd_a:
    andi    t1, a0, 1
    bne     t1, x0, .Lodd_b
    srli    a0, a0, 1
    jal     x0, .Lodd_a

    # Make b odd.
.Lodd_b:
    andi    t1, a1, 1
    bne     t1, x0, .Lorder
    srli    a1, a1, 1
    jal     x0, .Lodd_b

    # Keep b >= a so the difference cannot wrap around.
.Lorder:
    bgeu    a1, a0, .Lstep
    addi    t2, a0, 0
    addi    a0, a1, 0
    addi    a1, t2, 0

    # Odd minus odd is even, so b is even or zero after this.
.Lstep:
    sub     a1, a1, a0
    bne     a1, x0, .Lodd_b

    # Put the shared twos back; shift <= 31 because neither input is 0.
    sll     a0, a0, t0
.Lret:
    jalr    x0, ra, 0
.Lret_b:
    addi    a0, a1, 0
    jalr    x0, ra, 0

    .size   gcd_u32_asm, .-gcd_u32_asm
