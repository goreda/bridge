/* SPDX-License-Identifier: LGPL-2.1-or-later
 * Exact mpv v0.41.0 geometry parser/apply excerpts from:
 * https://raw.githubusercontent.com/mpv-player/mpv/v0.41.0/options/m_option.c
 * Test-only, unchanged function bodies. bstr boundary adapters live in negative.py.
 */
static bool eat_num_per(bstr *s, int *out_num, bool *out_per)
{
    bstr rest;
    long long v = bstrtoll(*s, &rest, 10);
    if (s->len == rest.len || v < INT_MIN || v > INT_MAX)
        return false;
    *out_num = v;
    *out_per = false;
    *s = rest;
    if (bstr_eatstart0(&rest, "%") && v >= 0 && v <= 100) {
        *out_per = true;
        *s = rest;
    }
    return true;
}

static bool parse_geometry_str(struct m_geometry *gm, bstr s)
{
    *gm = (struct m_geometry) { .x = INT_MIN, .y = INT_MIN };
    if (s.len == 0)
        return true;
    // Approximate grammar:
    // [[W][xH]][{+-}X{+-}Y][/WS] | [X:Y]
    // (meaning: [optional] {one character of} one|alternative)
    // Every number can be followed by '%'
    int num;
    bool per;

#define READ_NUM(F, F_PER) do {         \
    if (!eat_num_per(&s, &num, &per))   \
        goto error;                     \
    gm->F = num;                        \
    gm->F_PER = per;                    \
} while(0)

#define READ_SIGN(F) do {               \
    if (bstr_eatstart0(&s, "+")) {      \
        gm->F = false;                  \
    } else if (bstr_eatstart0(&s, "-")) {\
        gm->F = true;                   \
    } else goto error;                  \
} while(0)

    if (bstrchr(s, ':') < 0) {
        gm->wh_valid = true;
        if (!bstr_startswith0(s, "+") && !bstr_startswith0(s, "-")) {
            if (!bstr_startswith0(s, "x"))
                READ_NUM(w, w_per);
            if (bstr_eatstart0(&s, "x"))
                READ_NUM(h, h_per);
        }
        if (s.len > 0) {
            gm->xy_valid = true;
            READ_SIGN(x_sign);
            READ_NUM(x, x_per);
            READ_SIGN(y_sign);
            READ_NUM(y, y_per);
        }
        if (bstr_eatstart0(&s, "/")) {
            bstr rest;
            long long v = bstrtoll(s, &rest, 10);
            if (s.len == rest.len || v < 1 || v > INT_MAX)
                goto error;
            s = rest;
            gm->ws = v;
        }
    } else {
        gm->xy_valid = true;
        READ_NUM(x, x_per);
        if (!bstr_eatstart0(&s, ":"))
            goto error;
        READ_NUM(y, y_per);
    }

    return s.len == 0;

error:
    return false;
}

#undef READ_NUM
#undef READ_SIGN

#define APPEND_PER(F, F_PER) \
    res = talloc_asprintf_append(res, "%d%s", gm->F, gm->F_PER ? "%" : "")
void m_geometry_apply(int *xpos, int *ypos, int *widw, int *widh,
                      int scrw, int scrh, bool center, struct m_geometry *gm)
{
    if (gm->wh_valid) {
        int prew = *widw, preh = *widh;
        if (gm->w > 0)
            *widw = gm->w_per ? scrw * (gm->w / 100.0) : gm->w;
        if (gm->h > 0)
            *widh = gm->h_per ? scrh * (gm->h / 100.0) : gm->h;
        // keep aspect if the other value is not set
        double asp = (double)prew / preh;
        if (gm->w > 0 && !(gm->h > 0)) {
            *widh = *widw / asp;
        } else if (!(gm->w > 0) && gm->h > 0) {
            *widw = *widh * asp;
        }
        if (center) {
            *xpos += prew / 2 - *widw / 2;
            *ypos += preh / 2 - *widh / 2;
        }
    }

    if (gm->xy_valid) {
        if (gm->x != INT_MIN) {
            *xpos = gm->x;
            if (gm->x_per)
                *xpos = (scrw - *widw) * (*xpos / 100.0);
            if (gm->x_sign)
                *xpos = scrw - *widw - *xpos;
        }
        if (gm->y != INT_MIN) {
            *ypos = gm->y;
            if (gm->y_per)
                *ypos = (scrh - *widh) * (*ypos / 100.0);
            if (gm->y_sign)
                *ypos = scrh - *widh - *ypos;
        }
    }
}
