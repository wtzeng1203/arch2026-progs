#include "rubik.h"
#include "rubik_tables.h"

/* A position is two ranks: p, the Lehmer code of the seven cubies (0..5039),
 * and o, the first six twists in base 3 (0..728). A move changes each part
 * independently, so rubik_perm_move and rubik_ori_move turn them by lookup.
 * Move m turns face m / 3 by m % 3 + 1 quarter turns: R R2 R' B B2 B' D D2 D'.
 */
static const uint8_t move_face[9] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
static const uint8_t move_turns[9] = {1, 2, 3, 1, 2, 3, 1, 2, 3};
static const char move_name[9][2] = {{'R', 0}, {'R', '2'}, {'R', '\''},
                                     {'B', 0}, {'B', '2'}, {'B', '\''},
                                     {'D', 0}, {'D', '2'}, {'D', '\''}};

struct pos {
    uint32_t p, o;
};

static void turn(struct pos *x, unsigned m)
{
    unsigned f = move_face[m];
    for (unsigned t = 0; t < move_turns[m]; t++) {
        x->p = rubik_perm_move[x->p][f];
        x->o = rubik_ori_move[x->o][f];
    }
}

/* p * 729 + o with shifts: 729 = 512 + 128 + 64 + 16 + 8 + 1. */
static uint32_t rank_of(const struct pos *x)
{
    uint32_t p = x->p;
    return (p << 9) + (p << 7) + (p << 6) + (p << 4) + (p << 3) + p + x->o;
}

/* The first move stored for rank in table t (15 for the solved cube), or -1
 * when rank is not in t. Entries are rank << 4 | move, sorted, so the search
 * looks for the first entry not below rank << 4.
 */
static int lookup(const uint32_t *t, uint32_t n, uint32_t rank)
{
    uint32_t key = rank << 4, lo = 0, hi = n;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        if (t[mid] < key)
            lo = mid + 1;
        else
            hi = mid;
    }
    if (lo < n && (t[lo] >> 4) == rank)
        return (int) (t[lo] & 15);
    return -1;
}

/* Count of later cubies smaller than c[i]: one digit of the Lehmer code. */
static uint32_t smaller_after(const uint8_t *c, int i)
{
    uint32_t n = 0;
    for (int j = i + 1; j < 7; j++)
        n += c[j] < c[i];
    return n;
}

/* Reads the 14 characters in order and stops at the first bad one, so a short
 * string is never read past its NUL. Returns 0 and fills x, or -1.
 */
static int parse(const char *s, struct pos *x)
{
    uint8_t c[7];
    uint32_t seen = 0, sum = 0, o = 0;
    for (int i = 0; i < 7; i++) {
        uint32_t d = (uint32_t) (unsigned char) s[i] - '1';
        if (d > 6 || ((seen >> d) & 1))
            return -1;
        seen |= 1u << d;
        c[i] = (uint8_t) d;
    }
    for (int i = 0; i < 7; i++) {
        uint32_t d = (uint32_t) (unsigned char) s[7 + i] - '1';
        if (d > 2)
            return -1;
        sum += d;
        if (i < 6)
            o = (o << 1) + o + d;
    }
    if (s[14] != '\0')
        return -1;
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return -1;

    /* Horner form of c0*720 + c1*120 + c2*24 + c3*6 + c4*2 + c5. */
    uint32_t p = smaller_after(c, 0);
    p = (p << 2) + (p << 1) + smaller_after(c, 1);
    p = (p << 2) + p + smaller_after(c, 2);
    p = (p << 2) + smaller_after(c, 3);
    p = (p << 1) + p + smaller_after(c, 4);
    p = (p << 1) + smaller_after(c, 5);
    x->p = p;
    x->o = o;
    return 0;
}

/* Depth-first search for `left` more moves, never turning the face turned
 * last. Succeeds when the leaf is within 5 moves of solved (in rubik_t5).
 */
static int dfs(const struct pos *x, int left, unsigned last, uint8_t *path)
{
    if (left == 0)
        return lookup(rubik_t5, RUBIK_T5_LEN, rank_of(x)) >= 0;
    for (unsigned m = 0; m < 9; m++) {
        if (move_face[m] == last)
            continue;
        struct pos y = *x;
        turn(&y, m);
        path[0] = (uint8_t) m;
        if (dfs(&y, left - 1, move_face[m], path + 1))
            return 1;
    }
    return 0;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    struct pos x;
    if (parse(state, &x) < 0)
        return -1;

    uint8_t path[11];
    int len = 0;
    int m = lookup(rubik_t5, RUBIK_T5_LEN, rank_of(&x));
    if (m < 0) {
        /* Distance 6..11. A distance-11 state first steps to distance 10. */
        int first = lookup(rubik_t11, RUBIK_T11_LEN, rank_of(&x));
        unsigned last = 3; /* no face */
        if (first >= 0) {
            path[len++] = (uint8_t) first;
            turn(&x, (unsigned) first);
            last = move_face[first];
        }
        /* The first depth with a leaf in rubik_t5 is distance - 5. */
        int depth = 1;
        while (!dfs(&x, depth, last, path + len))
            depth++;
        for (int i = 0; i < depth; i++)
            turn(&x, path[len + i]);
        len += depth;
        m = lookup(rubik_t5, RUBIK_T5_LEN, rank_of(&x));
    }
    /* Follow the stored first moves down to the solved cube. */
    while (m != 15) {
        path[len++] = (uint8_t) m;
        turn(&x, (unsigned) m);
        m = lookup(rubik_t5, RUBIK_T5_LEN, rank_of(&x));
    }

    /* Each name is 1 or 2 characters, plus a space or the final NUL. */
    size_t need = len ? 0 : 1;
    for (int i = 0; i < len; i++)
        need += move_name[path[i]][1] ? 3 : 2;
    if (cap < need) {
        if (cap >= 1)
            out[0] = '\0';
        return -2;
    }
    char *w = out;
    for (int i = 0; i < len; i++) {
        if (i > 0)
            *w++ = ' ';
        *w++ = move_name[path[i]][0];
        if (move_name[path[i]][1])
            *w++ = move_name[path[i]][1];
    }
    *w = '\0';
    return len;
}
