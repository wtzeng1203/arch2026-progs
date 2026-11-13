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
# Registers: a0 = a and the result, a1 = b, t0 = shift, t1 = parity test
# and a | b, t2 = tmp for the swap and the bit search.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    # Zero operands; this also keeps the loops below from spinning on 0.
    beq     a0, x0, .Lret_b
    beq     a1, x0, .Lret

    # Shared twos are rare, so they are counted out of line at .Lshared.
    or      t1, a0, a1
    andi    t0, t1, 1
    beq     t0, x0, .Lshared
    addi    t0, x0, 0

    # Make a odd. An even a means b is odd, so strip all the twos of a
    # with a binary search over the bit position, at most five steps,
    # and go straight to the subtraction.
.Lcheck_a:
    andi    t1, a0, 1
    bne     t1, x0, .Lodd_b
    slli    t2, a0, 16
    bne     t2, x0, .La8
    srli    a0, a0, 16
.La8:
    slli    t2, a0, 24
    bne     t2, x0, .La4
    srli    a0, a0, 8
.La4:
    slli    t2, a0, 28
    bne     t2, x0, .La2
    srli    a0, a0, 4
.La2:
    slli    t2, a0, 30
    bne     t2, x0, .La1
    srli    a0, a0, 2
.La1:
    andi    t2, a0, 1
    bne     t2, x0, .Lorder
    srli    a0, a0, 1
    jal     x0, .Lorder

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
    # no test before its first pass. A difference of two odd numbers has
    # few trailing zeros, so this loop is cheaper than a binary search.
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
.Lret_b:
    addi    a0, a1, 0
    jalr    x0, ra, 0

    # Strip and count the twos that a and b share: shift = ctz(a | b),
    # found by the same binary search on t1 = a | b, which is even and
    # not zero here. t0 is 0 on entry.
.Lshared:
    slli    t2, t1, 16
    bne     t2, x0, .Ls8
    srli    t1, t1, 16
    addi    t0, t0, 16
.Ls8:
    slli    t2, t1, 24
    bne     t2, x0, .Ls4
    srli    t1, t1, 8
    addi    t0, t0, 8
.Ls4:
    slli    t2, t1, 28
    bne     t2, x0, .Ls2
    srli    t1, t1, 4
    addi    t0, t0, 4
.Ls2:
    slli    t2, t1, 30
    bne     t2, x0, .Ls1
    srli    t1, t1, 2
    addi    t0, t0, 2
.Ls1:
    andi    t2, t1, 1
    xori    t2, t2, 1
    add     t0, t0, t2
    srl     a0, a0, t0
    srl     a1, a1, t0
    jal     x0, .Lcheck_a

    .size   gcd_u32_asm, .-gcd_u32_asm
