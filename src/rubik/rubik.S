# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
#
# Same algorithm and tables as rubik.c. A position is a pair (p, o): p is the
# permutation rank 0..5039, o the twist rank 0..728. rank = p * 729 + o.
# t5 and t11 (rubik_tables.inc) hold rank << 4 | first move, sorted.
#
# Registers kept for the whole call:
#   s0 out          s1 cap          s2 perm_move    s3 ori_move
#   s4 t5           s5 move_info    s6 T5_LEN       s7 len (moves in path)
#   s8 depth limit  s9 level        s10 face of the move before the search
# Helpers (leaf routines, called with jal ra, use only a- and t-registers):
#   .Lrubik_turn  a0 = p, a1 = o, a2 = move  ->  a0 = p', a1 = o'
#   .Lfind  a0 = p, a1 = o, a3 = table, a4 = length  ->  a5 = move or -1
#
# Stack frame (FRAME bytes):
#   0..51     ra, s0..s11
#   PATH      path[11], the moves of the solution
#   CUB       the seven cubie digits while parsing
#   STP, STO  p and o of each search level 0..5 (words)
#   STN       next move to try at each level (bytes)
#   STL       face of the move that led to each level (bytes)

    .equ    FRAME, 144
    .equ    PATH, 52
    .equ    CUB, 64
    .equ    STP, 72
    .equ    STO, 96
    .equ    STN, 120
    .equ    STL, 128
    .equ    NOFACE, 3

    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -FRAME
    sw      ra, 0(sp)
    sw      s0, 4(sp)
    sw      s1, 8(sp)
    sw      s2, 12(sp)
    sw      s3, 16(sp)
    sw      s4, 20(sp)
    sw      s5, 24(sp)
    sw      s6, 28(sp)
    sw      s7, 32(sp)
    sw      s8, 36(sp)
    sw      s9, 40(sp)
    sw      s10, 44(sp)
    sw      s11, 48(sp)
    addi    s0, a1, 0
    addi    s1, a2, 0
    lui     s2, %hi(perm_move)
    addi    s2, s2, %lo(perm_move)
    lui     s3, %hi(ori_move)
    addi    s3, s3, %lo(ori_move)
    lui     s4, %hi(t5)
    addi    s4, s4, %lo(t5)
    lui     s5, %hi(move_info)
    addi    s5, s5, %lo(move_info)
    lui     s6, %hi(T5_LEN)
    addi    s6, s6, %lo(T5_LEN)

    # Cubie digits: each in '1'..'7' and not seen before; t1 = seen mask.
    # A NUL fails the range check, so nothing past it is read.
    addi    t0, x0, 0
    addi    t1, x0, 0
.Lrubik_parse_p:
    add     t3, a0, t0
    lbu     t4, 0(t3)
    addi    t4, t4, -49
    addi    t5, x0, 7
    bgeu    t4, t5, .Lrubik_invalid
    srl     t5, t1, t4
    andi    t5, t5, 1
    bne     t5, x0, .Lrubik_invalid
    addi    t5, x0, 1
    sll     t5, t5, t4
    or      t1, t1, t5
    add     t3, sp, t0
    sb      t4, CUB(t3)
    addi    t0, t0, 1
    addi    t5, x0, 7
    bne     t0, t5, .Lrubik_parse_p

    # Twist digits: each in '1'..'3'; t1 = base 3 of the first six,
    # t2 = sum of all seven.
    addi    t0, x0, 0
    addi    t1, x0, 0
    addi    t2, x0, 0
.Lrubik_parse_o:
    add     t3, a0, t0
    lbu     t4, 7(t3)
    addi    t4, t4, -49
    addi    t5, x0, 3
    bgeu    t4, t5, .Lrubik_invalid
    add     t2, t2, t4
    addi    t5, x0, 6
    bgeu    t0, t5, .Lrubik_parse_o_next
    slli    t5, t1, 1
    add     t1, t1, t5
    add     t1, t1, t4
.Lrubik_parse_o_next:
    addi    t0, t0, 1
    addi    t5, x0, 7
    bne     t0, t5, .Lrubik_parse_o
    lbu     t4, 14(a0)
    bne     t4, x0, .Lrubik_invalid

    # The twist sum (at most 14) must be a multiple of 3.
    addi    t5, x0, 3
.Lrubik_mod3:
    bltu    t2, t5, .Lrubik_mod3_done
    sub     t2, t2, t5
    jal     x0, .Lrubik_mod3
.Lrubik_mod3_done:
    bne     t2, x0, .Lrubik_invalid
    addi    a1, t1, 0

    # Lehmer code in Horner form: p = p * (7 - i) + (later cubies smaller
    # than cubie i), for i = 0..5. The multiply is a short loop of adds.
    addi    t0, x0, 0
    addi    t6, x0, 0
.Lrubik_lehmer:
    add     t3, sp, t0
    lbu     t4, CUB(t3)
    addi    t5, x0, 0
    addi    t1, t0, 1
.Lrubik_lehmer_count:
    add     t3, sp, t1
    lbu     t2, CUB(t3)
    sltu    t2, t2, t4
    add     t5, t5, t2
    addi    t1, t1, 1
    addi    t3, x0, 7
    bne     t1, t3, .Lrubik_lehmer_count
    addi    t1, x0, 7
    sub     t1, t1, t0
    addi    t2, x0, 0
.Lrubik_lehmer_mul:
    add     t2, t2, t6
    addi    t1, t1, -1
    bne     t1, x0, .Lrubik_lehmer_mul
    add     t6, t2, t5
    addi    t0, t0, 1
    addi    t3, x0, 6
    bne     t0, t3, .Lrubik_lehmer
    addi    a0, t6, 0

    # Within five moves: follow the stored moves.
    addi    s7, x0, 0
    addi    a3, s4, 0
    addi    a4, s6, 0
    jal     ra, .Lrubik_find
    bge     a5, x0, .Lrubik_follow

    # Distance 11: take the stored move first, which reaches distance 10.
    lui     a3, %hi(t11)
    addi    a3, a3, %lo(t11)
    lui     a4, %hi(T11_LEN)
    addi    a4, a4, %lo(T11_LEN)
    jal     ra, .Lrubik_find
    addi    s10, x0, NOFACE
    blt     a5, x0, .Lrubik_search
    sb      a5, PATH(sp)
    addi    s7, x0, 1
    slli    t0, a5, 2
    add     t0, s5, t0
    lbu     s10, 0(t0)
    addi    a2, a5, 0
    jal     ra, .Lrubik_turn

    # Iterative deepening: depth limit s8 = 1, 2, ... until a leaf at that
    # depth is in t5. Level s9 runs from 0 to s8 on the explicit stack.
.Lrubik_search:
    addi    s8, x0, 1
.Lrubik_depth:
    sw      a0, STP(sp)
    sw      a1, STO(sp)
    sb      x0, STN(sp)
    sb      s10, STL(sp)
    addi    s9, x0, 0
.Lrubik_dfs:
    slli    t0, s9, 2
    add     t0, sp, t0
    lw      a0, STP(t0)
    lw      a1, STO(t0)
    bne     s9, s8, .Lrubik_expand

    # Leaf: done if it is within five moves of solved.
    addi    a3, s4, 0
    addi    a4, s6, 0
    jal     ra, .Lrubik_find
    bge     a5, x0, .Lrubik_found
.Lrubik_back:
    beq     s9, x0, .Lrubik_deeper
    addi    s9, s9, -1
    jal     x0, .Lrubik_dfs

    # Next move at this level, skipping the face turned last.
.Lrubik_expand:
    add     t1, sp, s9
    lbu     a2, STN(t1)
    lbu     t2, STL(t1)
.Lrubik_skip:
    addi    t3, x0, 9
    beq     a2, t3, .Lrubik_back
    slli    t0, a2, 2
    add     t0, s5, t0
    lbu     t4, 0(t0)
    bne     t4, t2, .Lrubik_take
    addi    a2, a2, 1
    jal     x0, .Lrubik_skip
.Lrubik_take:
    addi    t3, a2, 1
    sb      t3, STN(t1)
    sb      t4, STL+1(t1)
    sb      x0, STN+1(t1)
    add     t3, t1, s7
    sb      a2, PATH(t3)
    jal     ra, .Lrubik_turn
    addi    s9, s9, 1
    slli    t0, s9, 2
    add     t0, sp, t0
    sw      a0, STP(t0)
    sw      a1, STO(t0)
    jal     x0, .Lrubik_dfs

.Lrubik_deeper:
    lw      a0, STP(sp)
    lw      a1, STO(sp)
    addi    s8, s8, 1
    jal     x0, .Lrubik_depth

.Lrubik_found:
    add     s7, s7, s8

    # Follow the first moves stored in t5 down to the solved cube (15).
.Lrubik_follow:
    addi    t0, x0, 15
    beq     a5, t0, .Lrubik_output
    add     t1, sp, s7
    sb      a5, PATH(t1)
    addi    s7, s7, 1
    addi    a2, a5, 0
    jal     ra, .Lrubik_turn
    addi    a3, s4, 0
    addi    a4, s6, 0
    jal     ra, .Lrubik_find
    jal     x0, .Lrubik_follow

    # Bytes needed: 2 or 3 per move (name plus space or NUL), 1 if no move.
.Lrubik_output:
    sltiu   t0, s7, 1
    addi    t1, x0, 0
.Lrubik_need:
    beq     t1, s7, .Lrubik_need_done
    add     t2, sp, t1
    lbu     t2, PATH(t2)
    slli    t2, t2, 2
    add     t2, s5, t2
    lbu     t3, 3(t2)
    sltu    t3, x0, t3
    addi    t0, t0, 2
    add     t0, t0, t3
    addi    t1, t1, 1
    jal     x0, .Lrubik_need
.Lrubik_need_done:
    bgeu    s1, t0, .Lrubik_write
    beq     s1, x0, .Lrubik_too_small
    sb      x0, 0(s0)
.Lrubik_too_small:
    addi    a0, x0, -2
    jal     x0, .Lrubik_return

.Lrubik_write:
    addi    t1, x0, 0
    addi    t4, s0, 0
.Lrubik_write_move:
    beq     t1, s7, .Lrubik_write_done
    beq     t1, x0, .Lrubik_write_name
    addi    t2, x0, 32
    sb      t2, 0(t4)
    addi    t4, t4, 1
.Lrubik_write_name:
    add     t2, sp, t1
    lbu     t2, PATH(t2)
    slli    t2, t2, 2
    add     t2, s5, t2
    lbu     t3, 2(t2)
    sb      t3, 0(t4)
    addi    t4, t4, 1
    lbu     t3, 3(t2)
    beq     t3, x0, .Lrubik_write_next
    sb      t3, 0(t4)
    addi    t4, t4, 1
.Lrubik_write_next:
    addi    t1, t1, 1
    jal     x0, .Lrubik_write_move
.Lrubik_write_done:
    sb      x0, 0(t4)
    addi    a0, s7, 0
    jal     x0, .Lrubik_return

.Lrubik_invalid:
    addi    a0, x0, -1
.Lrubik_return:
    lw      ra, 0(sp)
    lw      s0, 4(sp)
    lw      s1, 8(sp)
    lw      s2, 12(sp)
    lw      s3, 16(sp)
    lw      s4, 20(sp)
    lw      s5, 24(sp)
    lw      s6, 28(sp)
    lw      s7, 32(sp)
    lw      s8, 36(sp)
    lw      s9, 40(sp)
    lw      s10, 44(sp)
    lw      s11, 48(sp)
    addi    sp, sp, FRAME
    jalr    x0, ra, 0

    # .Lrubik_turn: apply move a2 to (a0, a1): its face's quarter turn, 1 to 3
    # times. A table row is 3 halfwords, so row x starts at x * 6 bytes.
.Lrubik_turn:
    slli    t0, a2, 2
    add     t0, s5, t0
    lbu     t1, 0(t0)
    lbu     t2, 1(t0)
    slli    t1, t1, 1
.Lrubik_turn_quarter:
    slli    t0, a0, 2
    slli    t3, a0, 1
    add     t0, t0, t3
    add     t0, t0, s2
    add     t0, t0, t1
    lhu     a0, 0(t0)
    slli    t0, a1, 2
    slli    t3, a1, 1
    add     t0, t0, t3
    add     t0, t0, s3
    add     t0, t0, t1
    lhu     a1, 0(t0)
    addi    t2, t2, -1
    bne     t2, x0, .Lrubik_turn_quarter
    jalr    x0, ra, 0

    # .Lrubik_find: binary search of rank(a0, a1) << 4 in table a3 of a4
    # words. a5 = the low 4 bits of the match, or -1.
    # rank = p * 729 + o, 729 = 512 + 128 + 64 + 16 + 8 + 1.
    # lo (t2) and hi (t3) are addresses, so the middle word is found with
    # one mask instead of a shift and an add, and the loop test sits at
    # the bottom of each path.
.Lrubik_find:
    add     t1, a0, a1
    slli    t0, a0, 3
    add     t1, t1, t0
    slli    t0, a0, 4
    add     t1, t1, t0
    slli    t0, a0, 6
    add     t1, t1, t0
    slli    t0, a0, 7
    add     t1, t1, t0
    slli    t0, a0, 9
    add     t1, t1, t0
    slli    t1, t1, 4
    addi    t2, a3, 0
    slli    t3, a4, 2
    add     t3, a3, t3
    addi    t6, t3, 0
.Lrubik_find_loop:
    add     t4, t2, t3
    srli    t4, t4, 1
    andi    t4, t4, -4
    lw      t5, 0(t4)
    bgeu    t5, t1, .Lrubik_find_upper
    addi    t2, t4, 4
    bltu    t2, t3, .Lrubik_find_loop
    jal     x0, .Lrubik_find_check
.Lrubik_find_upper:
    addi    t3, t4, 0
    bltu    t2, t3, .Lrubik_find_loop
.Lrubik_find_check:
    addi    a5, x0, -1
    bgeu    t2, t6, .Lrubik_find_done
    lw      t5, 0(t2)
    andi    t0, t5, -16
    bne     t0, t1, .Lrubik_find_done
    andi    a5, t5, 15
.Lrubik_find_done:
    jalr    x0, ra, 0
    .size   rubik_solve_asm, .-rubik_solve_asm

    # Per move: face (0 R, 1 B, 2 D), quarter turns, and the two characters
    # of its name (second one 0 when absent). 82 'R', 66 'B', 68 'D',
    # 50 '2', 39 '\''.
    .section .rodata
    .align  2
move_info:
    .byte   0, 1, 82, 0
    .byte   0, 2, 82, 50
    .byte   0, 3, 82, 39
    .byte   1, 1, 66, 0
    .byte   1, 2, 66, 50
    .byte   1, 3, 66, 39
    .byte   2, 1, 68, 0
    .byte   2, 2, 68, 50
    .byte   2, 3, 68, 39
    .size   move_info, .-move_info

    .include "src/rubik/rubik_tables.inc"
