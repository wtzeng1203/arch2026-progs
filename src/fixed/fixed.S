# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.
#
# Register use:
#   op1    a0 = a, a1 = b, a2 = n, t0 = carry, t1 = pass count; leaf
#   op2    a0 and a1 only; leaf
#   op3    t0 = a ^ b; leaf
#   q_mul  s0 = a, s1 = b, s2 = low word, s3 = high word of the product;
#          calls __mulsi3 four times, so ra and s0-s3 sit in a 32-byte frame

    .equ    Q, 20

    .text

# a + b by XOR and carries; the pass count stays in t1 and is stored once.
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi    t1, zero, 0
.Lop1_top:
    beq     a1, zero, .Lop1_done
    and     t0, a0, a1
    slli    t0, t0, 1
    xor     a0, a0, a1
    addi    a1, t0, 0
    addi    t1, t1, 1
    jal     x0, .Lop1_top
.Lop1_done:
    sw      t1, 0(a2)
    jalr    x0, ra, 0
    .size   op1_asm, .-op1_asm

# a - b modulo 2^32.
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    jalr    x0, ra, 0
    .size   op2_asm, .-op2_asm

# (a & b) + ((a ^ b) >> 1); the XOR is taken before a0 is overwritten.
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    xor     t0, a0, a1
    and     a0, a0, a1
    srli    t0, t0, 1
    add     a0, a0, t0
    jalr    x0, ra, 0
    .size   op3_asm, .-op3_asm

# Q11.20 product from four 16-bit partial products, as in the C version.
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      s0, 24(sp)
    sw      s1, 20(sp)
    sw      s2, 16(sp)
    sw      s3, 12(sp)
    addi    s0, a0, 0
    addi    s1, a1, 0

    # al * bh, kept in s2 until the second cross term arrives
    slli    a0, s0, 16
    srli    a0, a0, 16
    srli    a1, s1, 16
    jal     ra, __mulsi3
    addi    s2, a0, 0

    # ah * bl; mid = sum of both cross terms, up to 33 bits
    srli    a0, s0, 16
    slli    a1, s1, 16
    srli    a1, a1, 16
    jal     ra, __mulsi3
    add     t0, s2, a0
    sltu    t1, t0, a0
    slli    s2, t0, 16
    srli    t0, t0, 16
    slli    t1, t1, 16
    add     s3, t0, t1

    # ah * bh goes to the high word
    srli    a0, s0, 16
    srli    a1, s1, 16
    jal     ra, __mulsi3
    add     s3, s3, a0

    # al * bl goes to the low word, with its carry into the high word
    slli    a0, s0, 16
    srli    a0, a0, 16
    slli    a1, s1, 16
    srli    a1, a1, 16
    jal     ra, __mulsi3
    add     s2, s2, a0
    sltu    t0, s2, a0
    add     s3, s3, t0

    # signed product: subtract b from the high word if a < 0, a if b < 0
    bge     s0, zero, .Lqm_a_pos
    sub     s3, s3, s1
.Lqm_a_pos:
    bge     s1, zero, .Lqm_b_pos
    sub     s3, s3, s0
.Lqm_b_pos:

    # add 2^19 = 0x80 << 12, then keep bits 20..51
    lui     t0, 0x80
    add     t1, s2, t0
    sltu    t2, t1, t0
    add     t2, s3, t2
    slli    t2, t2, 32 - Q
    srli    t1, t1, Q
    or      a0, t2, t1

    lw      s3, 12(sp)
    lw      s2, 16(sp)
    lw      s1, 20(sp)
    lw      s0, 24(sp)
    lw      ra, 28(sp)
    addi    sp, sp, 32
    jalr    x0, ra, 0
    .size   q_mul_asm, .-q_mul_asm
