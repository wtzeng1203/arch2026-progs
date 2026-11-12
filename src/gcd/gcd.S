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

    # Strip and count the twos that a and b share. Each loop below tests
    # its condition at the bottom, so one branch both tests and repeats.
    or      t0, a0, a1
    andi    t0, t0, 1
    bne     t0, x0, .Lno_shared
.Lboth:
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    or      t1, a0, a1
    andi    t1, t1, 1
    beq     t1, x0, .Lboth

    # Make a odd; it stays odd from here on.
    andi    t1, a0, 1
    bne     t1, x0, .Lodd_b
.Lodd_a:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, x0, .Lodd_a
    jal     x0, .Lodd_b

    # Make b odd: an even b goes to the halving loop, an odd b goes
    # straight to the subtraction.
.Lodd_b:
    andi    t1, a1, 1
    beq     t1, x0, .Lhalve_b
    jal     x0, .Lorder

    # b < a: replace (a, b) with (b, a - b) in one step. a - b is even and
    # not zero, so this falls straight into halving b.
.Lswap:
    sub     t2, a0, a1
    addi    a0, a1, 0
    addi    a1, t2, 0

    # Halve b until it is odd. b is always even here, so the loop needs
    # no test before its first pass.
.Lhalve_b:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, x0, .Lhalve_b

    # Odd minus odd is even, so a nonzero b goes straight back to halving.
.Lorder:
    bltu    a1, a0, .Lswap
    sub     a1, a1, a0
    bne     a1, x0, .Lhalve_b

    # Put the shared twos back; shift <= 31 because neither input is 0.
    sll     a0, a0, t0
.Lret:
    jalr    x0, ra, 0

    # No shared twos. If a is even, t0 is 0 already and doubles as shift.
.Lno_shared:
    andi    t0, a0, 1
    beq     t0, x0, .Lodd_a
    addi    t0, x0, 0
    jal     x0, .Lodd_b
.Lret_b:
    addi    a0, a1, 0
    jalr    x0, ra, 0

    .size   gcd_u32_asm, .-gcd_u32_asm
