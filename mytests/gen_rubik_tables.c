/* Host-only table generator for src/rubik/. Not part of the submission.
 *
 * Writes three files into the directory given as argv[1] (src/rubik):
 *   rubik_tables.h    declarations and lengths for the C version
 *   rubik_tables.c    the tables for the C version
 *   rubik_tables.inc  the same tables for the assembly version (.include)
 *
 * The cube model is the one of tests/trubik.c: three faces R, B, D, each
 * destination i takes the cubie and twist of source[face][i].
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    CUBIES = 7,
    NPERM = 5040,
    NORI = 729,
    NSTATE = NPERM * NORI,
    NMOVES = 9,
};

static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

/* Lehmer code: c[i] = how many later cubies are smaller than p[i]. */
static int rank_perm(const uint8_t p[CUBIES])
{
    int r = 0;
    for (int i = 0; i < CUBIES - 1; i++) {
        int c = 0;
        for (int j = i + 1; j < CUBIES; j++)
            c += p[j] < p[i];
        r = r * (CUBIES - i) + c;
    }
    return r;
}

static void unrank_perm(int r, uint8_t p[CUBIES])
{
    int c[CUBIES];
    c[CUBIES - 1] = 0;
    for (int i = CUBIES - 2; i >= 0; i--) {
        c[i] = r % (CUBIES - i);
        r /= CUBIES - i;
    }
    int used[CUBIES] = {0};
    for (int i = 0; i < CUBIES; i++) {
        int k = c[i];
        for (int v = 0; v < CUBIES; v++) {
            if (used[v])
                continue;
            if (k-- == 0) {
                p[i] = (uint8_t) v;
                used[v] = 1;
                break;
            }
        }
    }
}

/* Base 3 of o[0..5]; o[6] follows from the sum being a multiple of 3. */
static int rank_ori(const uint8_t o[CUBIES])
{
    int r = 0;
    for (int i = 0; i < CUBIES - 1; i++)
        r = r * 3 + o[i];
    return r;
}

static void unrank_ori(int r, uint8_t o[CUBIES])
{
    int sum = 0;
    for (int i = CUBIES - 2; i >= 0; i--) {
        o[i] = (uint8_t) (r % 3);
        r /= 3;
        sum += o[i];
    }
    o[CUBIES - 1] = (uint8_t) ((3 - sum % 3) % 3);
}

static uint16_t perm_move[NPERM][3], ori_move[NORI][3];

static void build_move_tables(void)
{
    uint8_t p[CUBIES], o[CUBIES], q[CUBIES];
    for (int r = 0; r < NPERM; r++) {
        unrank_perm(r, p);
        if (rank_perm(p) != r) {
            fprintf(stderr, "perm rank round trip failed at %d\n", r);
            exit(1);
        }
        for (int f = 0; f < 3; f++) {
            for (int i = 0; i < CUBIES; i++)
                q[i] = p[source[f][i]];
            perm_move[r][f] = (uint16_t) rank_perm(q);
        }
    }
    for (int r = 0; r < NORI; r++) {
        unrank_ori(r, o);
        if (rank_ori(o) != r) {
            fprintf(stderr, "ori rank round trip failed at %d\n", r);
            exit(1);
        }
        for (int f = 0; f < 3; f++) {
            for (int i = 0; i < CUBIES; i++)
                q[i] = (uint8_t) ((o[source[f][i]] + twist[f][i]) % 3);
            ori_move[r][f] = (uint16_t) rank_ori(q);
        }
    }
    /* Four quarter turns of a face must give the identity. */
    for (int f = 0; f < 3; f++) {
        for (int r = 0; r < NPERM; r++) {
            int x = r;
            for (int t = 0; t < 4; t++)
                x = perm_move[x][f];
            if (x != r) {
                fprintf(stderr, "perm face %d has no order 4\n", f);
                exit(1);
            }
        }
        for (int r = 0; r < NORI; r++) {
            int x = r;
            for (int t = 0; t < 4; t++)
                x = ori_move[x][f];
            if (x != r) {
                fprintf(stderr, "ori face %d has no order 4\n", f);
                exit(1);
            }
        }
    }
}

/* Move m: face m / 3, turned m % 3 + 1 quarter turns (R R2 R' B B2 B' ...). */
static int apply(int s, int m)
{
    int p = s / NORI, o = s % NORI, f = m / 3;
    for (int t = 0; t <= m % 3; t++) {
        p = perm_move[p][f];
        o = ori_move[o][f];
    }
    return p * NORI + o;
}

static uint8_t dist[NSTATE];

static void bfs(void)
{
    int *queue = malloc(sizeof(int) * NSTATE);
    if (!queue) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }
    memset(dist, 0xFF, sizeof dist);
    int head = 0, tail = 0;
    dist[0] = 0; /* rank 0 is the solved cube */
    queue[tail++] = 0;
    while (head < tail) {
        int s = queue[head++];
        for (int m = 0; m < NMOVES; m++) {
            int t = apply(s, m);
            if (dist[t] == 0xFF) {
                dist[t] = (uint8_t) (dist[s] + 1);
                queue[tail++] = t;
            }
        }
    }
    free(queue);
    if (tail != NSTATE) {
        fprintf(stderr, "BFS reached %d states, not %d\n", tail, NSTATE);
        exit(1);
    }
}

/* The smallest move that takes s one step closer to solved; 15 for solved. */
static int first_move(int s)
{
    if (dist[s] == 0)
        return 15;
    for (int m = 0; m < NMOVES; m++) {
        if (dist[apply(s, m)] == dist[s] - 1)
            return m;
    }
    fprintf(stderr, "no first move for %d\n", s);
    exit(1);
}

static FILE *open_out(const char *dir, const char *name)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *f = fopen(path, "w");
    if (!f) {
        perror(path);
        exit(1);
    }
    return f;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s OUTDIR\n", argv[0]);
        return 2;
    }
    build_move_tables();
    bfs();

    int count[16] = {0}, n5 = 0, n11 = 0;
    for (int s = 0; s < NSTATE; s++) {
        count[dist[s]]++;
        n5 += dist[s] <= 5;
        n11 += dist[s] == 11;
    }
    for (int d = 0; d < 16 && count[d]; d++)
        fprintf(stderr, "distance %2d: %7d states\n", d, count[d]);
    fprintf(stderr, "table5: %d entries, table11: %d entries\n", n5, n11);

    /* Header for the C version. */
    FILE *h = open_out(argv[1], "rubik_tables.h");
    fprintf(h, "/* Generated by mytests/gen_rubik_tables.c. Do not edit. */\n");
    fprintf(h, "#pragma once\n\n#include <stdint.h>\n\n");
    fprintf(h, "#define RUBIK_T5_LEN %d\n#define RUBIK_T11_LEN %d\n\n", n5,
            n11);
    fprintf(h, "extern const uint16_t rubik_perm_move[%d][3];\n", NPERM);
    fprintf(h, "extern const uint16_t rubik_ori_move[%d][3];\n", NORI);
    fprintf(h, "extern const uint32_t rubik_t5[RUBIK_T5_LEN];\n");
    fprintf(h, "extern const uint32_t rubik_t11[RUBIK_T11_LEN];\n");
    fclose(h);

    /* Tables for the C version; run clang-format-20 -i on it afterwards. */
    FILE *c = open_out(argv[1], "rubik_tables.c");
    fprintf(c, "/* Generated by mytests/gen_rubik_tables.c. Do not edit.\n");
    fprintf(c, " * rubik_t5 and rubik_t11 hold rank << 4 | first move, ");
    fprintf(c, "sorted by rank.\n */\n");
    fprintf(c, "#include \"rubik_tables.h\"\n\n");
    fprintf(c, "const uint16_t rubik_perm_move[%d][3] = {\n", NPERM);
    for (int r = 0; r < NPERM; r++)
        fprintf(c, "{%d, %d, %d},\n", perm_move[r][0], perm_move[r][1],
                perm_move[r][2]);
    fprintf(c, "};\n\nconst uint16_t rubik_ori_move[%d][3] = {\n", NORI);
    for (int r = 0; r < NORI; r++)
        fprintf(c, "{%d, %d, %d},\n", ori_move[r][0], ori_move[r][1],
                ori_move[r][2]);
    fprintf(c, "};\n\nconst uint32_t rubik_t5[RUBIK_T5_LEN] = {\n");
    for (int s = 0; s < NSTATE; s++) {
        if (dist[s] <= 5)
            fprintf(c, "0x%06xu,\n",
                    ((unsigned) s << 4) | (unsigned) first_move(s));
    }
    fprintf(c, "};\n\nconst uint32_t rubik_t11[RUBIK_T11_LEN] = {\n");
    for (int s = 0; s < NSTATE; s++) {
        if (dist[s] == 11)
            fprintf(c, "0x%06xu,\n",
                    ((unsigned) s << 4) | (unsigned) first_move(s));
    }
    fprintf(c, "};\n");
    fclose(c);

    /* The same tables for the assembly version, pulled in with .include. */
    FILE *a = open_out(argv[1], "rubik_tables.inc");
    fprintf(a, "# Generated by mytests/gen_rubik_tables.c. Do not edit.\n");
    fprintf(a, "# Same content as rubik_tables.c, local to rubik.S.\n\n");
    fprintf(a, "    .equ    T5_LEN, %d\n    .equ    T11_LEN, %d\n\n", n5, n11);
    fprintf(a, "    .section .rodata\n    .align  2\n");
    const char *names[] = {"perm_move", "ori_move"};
    for (int k = 0; k < 2; k++) {
        int rows = k == 0 ? NPERM : NORI;
        fprintf(a, "%s:\n", names[k]);
        for (int r = 0; r < rows; r++) {
            const uint16_t *row = k == 0 ? perm_move[r] : ori_move[r];
            fprintf(a, "    .half   %d, %d, %d\n", row[0], row[1], row[2]);
        }
        fprintf(a, "    .size   %s, .-%s\n    .align  2\n", names[k], names[k]);
    }
    fprintf(a, "t5:\n");
    for (int s = 0; s < NSTATE; s++) {
        if (dist[s] <= 5)
            fprintf(a, "    .word   0x%06x\n",
                    ((unsigned) s << 4) | (unsigned) first_move(s));
    }
    fprintf(a, "    .size   t5, .-t5\nt11:\n");
    for (int s = 0; s < NSTATE; s++) {
        if (dist[s] == 11)
            fprintf(a, "    .word   0x%06x\n",
                    ((unsigned) s << 4) | (unsigned) first_move(s));
    }
    fprintf(a, "    .size   t11, .-t11\n");
    fclose(a);
    return 0;
}
