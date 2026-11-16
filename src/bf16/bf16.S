# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.
#
# bf16_from_f32_asm (leaf): a0 = input, then result
#   t0 = exponent field, t1 = 255 and then bit 16, t2 = 0x7FFF
#
# bf16_mul_asm (leaf): a0 = a, a1 = b, a0 = result
#   t0 = sign at bit 15, t1/t2 = exponents (t1 becomes the result exponent),
#   t3/t4 = significands, t2 = product once the exponents are summed,
#   t5 = 255, t6 = scratch
#
# bf16_sqrt_asm (leaf): a0 = a, a0 = result
#   t0 = exponent field, then the halved exponent
#   t1 = fraction, then the significand m
#   t2 = scratch, then low; t3 = high; t4 = result; t5 = mid
#   t6/a1 = multiplicand/multiplier, a2 = mid * mid, a3 = scratch

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    # Inf and NaN (exponent field 0xFF) keep their top half unchanged.
    srli    t0, a0, 23
    andi    t0, t0, 255
    addi    t1, x0, 255
    beq     t0, t1, .Lbf16_from_f32_asm_special

    # Round to nearest, ties to even: add 0x7FFF plus bit 16.
    srli    t1, a0, 16
    andi    t1, t1, 1
    lui     t2, 0x8
    addi    t2, t2, -1
    add     a0, a0, t2
    add     a0, a0, t1
    srli    a0, a0, 16
    jalr    x0, ra, 0

.Lbf16_from_f32_asm_special:
    srli    a0, a0, 16
    jalr    x0, ra, 0
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    # Split both operands. The sign is the XOR of the signs, kept at bit 15.
    xor     t0, a0, a1
    lui     t6, 0x8
    and     t0, t0, t6
    srli    t1, a0, 7
    andi    t1, t1, 255
    srli    t2, a1, 7
    andi    t2, t2, 255
    andi    t3, a0, 127
    andi    t4, a1, 127
    addi    t5, x0, 255

    # a is examined before b, so an infinite a swallows a NaN b.
    beq     t1, t5, .Lbf16_mul_asm_a_special
    beq     t2, t5, .Lbf16_mul_asm_b_special

    # Zero times a finite value is zero with the product sign.
    or      t6, t1, t3
    beq     t6, x0, .Lbf16_mul_asm_zero
    or      t6, t2, t4
    beq     t6, x0, .Lbf16_mul_asm_zero

    # Normalize a: a denormal shifts up to a leading one while its exponent
    # drops from 1; a normal gets its hidden one.
    bne     t1, x0, .Lbf16_mul_asm_a_normal
    addi    t1, x0, 1
.Lbf16_mul_asm_a_shift:
    andi    t6, t3, 128
    bne     t6, x0, .Lbf16_mul_asm_a_done
    slli    t3, t3, 1
    addi    t1, t1, -1
    jal     x0, .Lbf16_mul_asm_a_shift
.Lbf16_mul_asm_a_normal:
    ori     t3, t3, 128
.Lbf16_mul_asm_a_done:

    # Normalize b the same way.
    bne     t2, x0, .Lbf16_mul_asm_b_normal
    addi    t2, x0, 1
.Lbf16_mul_asm_b_shift:
    andi    t6, t4, 128
    bne     t6, x0, .Lbf16_mul_asm_b_done
    slli    t4, t4, 1
    addi    t2, t2, -1
    jal     x0, .Lbf16_mul_asm_b_shift
.Lbf16_mul_asm_b_normal:
    ori     t4, t4, 128
.Lbf16_mul_asm_b_done:

    # Exponent: the sum counts the bias twice, so remove one.
    add     t1, t1, t2
    addi    t1, t1, -127

    # Significand product by shift-and-add over the bits of t4.
    addi    t2, x0, 0
.Lbf16_mul_asm_mul_loop:
    andi    t6, t4, 1
    beq     t6, x0, .Lbf16_mul_asm_mul_skip
    add     t2, t2, t3
.Lbf16_mul_asm_mul_skip:
    slli    t3, t3, 1
    srli    t4, t4, 1
    bne     t4, x0, .Lbf16_mul_asm_mul_loop

    # The product lies in [2^14, 2^16): keep 8 bits and truncate the rest.
    srli    t6, t2, 15
    beq     t6, x0, .Lbf16_mul_asm_shift7
    srli    t2, t2, 8
    addi    t1, t1, 1
    jal     x0, .Lbf16_mul_asm_frac
.Lbf16_mul_asm_shift7:
    srli    t2, t2, 7
.Lbf16_mul_asm_frac:
    andi    t2, t2, 127

    # Exponent range: 255 and up is Inf; below 1 only the fraction shifts
    # right, and below -6 nothing is left.
    bge     t1, t5, .Lbf16_mul_asm_inf
    blt     x0, t1, .Lbf16_mul_asm_pack
    addi    t6, x0, -6
    blt     t1, t6, .Lbf16_mul_asm_zero
    addi    t6, x0, 1
    sub     t6, t6, t1
    srl     t2, t2, t6
    addi    t1, x0, 0
.Lbf16_mul_asm_pack:
    slli    t1, t1, 7
    or      a0, t0, t1
    or      a0, a0, t2
    jalr    x0, ra, 0

    # a has exponent 0xFF: a NaN a is returned, Inf times zero is the quiet
    # NaN, anything else is Inf.
.Lbf16_mul_asm_a_special:
    bne     t3, x0, .Lbf16_mul_asm_ret
    or      t6, t2, t4
    beq     t6, x0, .Lbf16_mul_asm_nan
    jal     x0, .Lbf16_mul_asm_inf

    # b has exponent 0xFF: the same, returning a NaN b.
.Lbf16_mul_asm_b_special:
    bne     t4, x0, .Lbf16_mul_asm_ret_b
    or      t6, t1, t3
    beq     t6, x0, .Lbf16_mul_asm_nan
.Lbf16_mul_asm_inf:
    lui     t6, 0x8
    addi    t6, t6, -128
    or      a0, t0, t6
    jalr    x0, ra, 0
.Lbf16_mul_asm_nan:
    lui     a0, 0x8
    addi    a0, a0, -64
    jalr    x0, ra, 0
.Lbf16_mul_asm_zero:
    addi    a0, t0, 0
    jalr    x0, ra, 0
.Lbf16_mul_asm_ret_b:
    addi    a0, a1, 0
.Lbf16_mul_asm_ret:
    jalr    x0, ra, 0
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    # Split the operand and sort out the special classes in contract order.
    srli    t0, a0, 7
    andi    t0, t0, 255
    andi    t1, a0, 127
    addi    t2, x0, 255
    beq     t0, t2, .Lbf16_sqrt_asm_special
    # Zero comes before the sign test, so -0 gives +0.
    or      t2, t0, t1
    beq     t2, x0, .Lbf16_sqrt_asm_zero
    srli    t2, a0, 15
    bne     t2, x0, .Lbf16_sqrt_asm_nan
    beq     t0, x0, .Lbf16_sqrt_asm_zero

    # m gets the hidden one and doubles when the stored exponent is even,
    # that is, when the unbiased exponent is odd. Halving is (E + 127) >> 1.
    ori     t1, t1, 128
    andi    t2, t0, 1
    bne     t2, x0, .Lbf16_sqrt_asm_exp
    slli    t1, t1, 1
.Lbf16_sqrt_asm_exp:
    addi    t0, t0, 127
    srli    t0, t0, 1

    # Binary search over [90, 256] for the largest mid with
    # (mid * mid) / 128 <= m.
    addi    t2, x0, 90
    addi    t3, x0, 256
    addi    t4, x0, 128
.Lbf16_sqrt_asm_loop:
    bltu    t3, t2, .Lbf16_sqrt_asm_done
    add     t5, t2, t3
    srli    t5, t5, 1
    # mid * mid by shift-and-add.
    addi    a2, x0, 0
    addi    t6, t5, 0
    addi    a1, t5, 0
.Lbf16_sqrt_asm_mul_loop:
    andi    a3, a1, 1
    beq     a3, x0, .Lbf16_sqrt_asm_mul_skip
    add     a2, a2, t6
.Lbf16_sqrt_asm_mul_skip:
    slli    t6, t6, 1
    srli    a1, a1, 1
    bne     a1, x0, .Lbf16_sqrt_asm_mul_loop
    srli    a2, a2, 7
    bltu    t1, a2, .Lbf16_sqrt_asm_high
    addi    t4, t5, 0
    addi    t2, t5, 1
    jal     x0, .Lbf16_sqrt_asm_loop
.Lbf16_sqrt_asm_high:
    addi    t3, t5, -1
    jal     x0, .Lbf16_sqrt_asm_loop

    # result lies in [128, 255] and the exponent in [64, 190]: just pack.
.Lbf16_sqrt_asm_done:
    andi    t4, t4, 127
    slli    t0, t0, 7
    or      a0, t0, t4
    jalr    x0, ra, 0

    # Exponent 0xFF: a NaN or +Inf is returned unchanged, -Inf gives NaN.
.Lbf16_sqrt_asm_special:
    bne     t1, x0, .Lbf16_sqrt_asm_ret
    srli    t2, a0, 15
    beq     t2, x0, .Lbf16_sqrt_asm_ret
.Lbf16_sqrt_asm_nan:
    lui     a0, 0x8
    addi    a0, a0, -64
    jalr    x0, ra, 0
.Lbf16_sqrt_asm_zero:
    addi    a0, x0, 0
.Lbf16_sqrt_asm_ret:
    jalr    x0, ra, 0
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
