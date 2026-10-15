// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded native scope computation. Input: encoded, full-range RGBA16.
#ifndef AAGEDAL_SCOPE_MATH_H
#define AAGEDAL_SCOPE_MATH_H
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>

struct scope_bin { uint32_t count; float r, g, b; };
struct scope_plots { uint8_t *wave, *parade, *vector; int w, h; };
static float scope_nits(float e, int transfer, float peak)
{
    if (e <= 0) return 0;
    if (transfer == 1) {
        float p = powf(e, 1.0f / 78.84375f);
        return 10000 * powf(fmaxf(p - 0.8359375f, 0) /
                           (18.8515625f - 18.6875f * p), 1.0f / 0.1593017578125f);
    }
    if (transfer == 2) {
        float a = 0.17883277f, b = 1 - 4 * a, c = 0.5f - a * logf(4 * a);
        float scene = e <= 0.5f ? e * e / 3 : (expf((e-c)/a) + b) / 12;
        // Display-referred HLG, fixed 1.2 system gamma at the declared peak.
        return peak * powf(scene, 1.2f);
    }
    return e;
}
static int scope_level(float v, int h, int transfer, float peak)
{
    float n = transfer ? (log10f(fmaxf(0.1f, fminf(v, peak))) + 1) /
                         (log10f(peak) + 1) : v;
    return (int)(fmaxf(0, fminf(n, 1)) * (h - 1));
}
static void scope_add(struct scope_bin *p, float r, float g, float b)
{
    p->count++; p->r += r; p->g += g; p->b += b;
}
static void scope_paint(struct scope_bin *bins, int n, uint8_t *out, bool vector)
{
    uint32_t maximum = 1;
    for (int i = 0; i < n; i++) if (bins[i].count > maximum) maximum = bins[i].count;
    float norm = log2f(1 + (float)maximum);
    for (int i = 0; i < n; i++) {
        struct scope_bin p = bins[i];
        if (!p.count) continue;
        float r = p.r/p.count, g = p.g/p.count, b = p.b/p.count;
        float gray = (r+g+b)/3, boost = vector ? 2 : 2.5f;
        float saturation = fminf(fmaxf(fabsf(r-gray), fmaxf(fabsf(g-gray), fabsf(b-gray))) /
                                 fmaxf(gray, 0.01f) * 3, 1);
        r = fmaxf(gray + (r-gray)*boost, vector ? 0.05f : 0);
        g = fmaxf(gray + (g-gray)*boost, vector ? 0.05f : 0);
        b = fmaxf(gray + (b-gray)*boost, vector ? 0.05f : 0);
        float mx = fmaxf(0.01f, fmaxf(r, fmaxf(g,b)));
        float alpha = fminf(log2f(1+(float)p.count)/norm * (vector ? 3 : 2.5f), 1);
        float mix = vector ? 1 : saturation;
        out[4*i] = (uint8_t)((b/mx*mix + 1-mix)*alpha*255);
        out[4*i+1] = (uint8_t)((g/mx*mix + 1-mix)*alpha*255);
        out[4*i+2] = (uint8_t)((r/mx*mix + 1-mix)*alpha*255);
        out[4*i+3] = vector ? 255 : (uint8_t)(alpha*255);
    }
}
static bool scope_compute(const uint16_t *rgba, int sw, int sh, int stride,
                          int rotation, bool flip, bool bt2020, int transfer,
                          float peak, struct scope_plots out)
{
    int w = out.w, h = out.h;
    if (!rgba || sw < 1 || sh < 1 || sw > 1440 || sh > 1440 || stride < sw*8 ||
        w < 16 || w > 1440 || h < 8 || h > 810 || rotation < 0 || rotation >= 360 ||
        rotation % 90 || transfer < 0 || transfer > 2 || !isfinite(peak) ||
        peak <= 0.1f || peak > 10000 || !out.wave || !out.parade || !out.vector) return false;
    int cw = (w-6)/4, n = w*h, vn = h*h;
    struct scope_bin *wave = calloc(n, sizeof(*wave)), *vec = calloc(vn, sizeof(*vec));
    uint32_t *par = calloc(cw*h*4, sizeof(*par));
    if (!wave || !vec || !par) { free(wave); free(vec); free(par); return false; }
    float kr = bt2020 ? 0.2627f : 0.2126f, kb = bt2020 ? 0.0593f : 0.0722f;
    // A transfer LUT avoids three expensive PQ/HLG exponent evaluations per sample.
    float *lut = malloc(65536 * sizeof(*lut));
    if (!lut) { free(wave); free(vec); free(par); return false; }
    for (int i = 0; i < 65536; i++) lut[i] = scope_nits(i/65535.0f, transfer, peak);
    for (int y = 0; y < sh; y++) {
        const uint16_t *row = (const void *)((const uint8_t *)rgba + y*stride);
        for (int x = 0; x < sw; x++) {
            const uint16_t *p = row+4*x;
            float r = p[0]/65535.0f, g = p[1]/65535.0f, b = p[2]/65535.0f;
            int fy = flip ? sh-1-y : y;
            int ox = x, ow = sw;
            if (rotation == 90) { ox = sh-1-fy; ow = sh; }
            if (rotation == 180) ox = sw-1-x;
            if (rotation == 270) { ox = fy; ow = sh; }
            float rn = lut[p[0]], gn = lut[p[1]], bn = lut[p[2]];
            float values[4] = {rn, gn, bn, kr*rn+(1-kr-kb)*gn+kb*bn};
            int col = ox*w/ow, pc = ox*cw/ow;
            int level = scope_level(values[3], h, transfer, peak);
            float colorMax = transfer ? fmaxf(0.001f, fmaxf(r, fmaxf(g,b))) : 1;
            scope_add(&wave[(h-1-level)*w+col], r/colorMax, g/colorMax, b/colorMax);
            for (int c = 0; c < 4; c++) {
                level = scope_level(values[c], h, transfer, peak);
                par[(c*cw+pc)*h+level]++;
            }
            // Source-space chroma. The app selects matching BT.709/2020 targets.
            float luma = kr*r+(1-kr-kb)*g+kb*b;
            float cb = (b-luma)/(2*(1-kb)), cr = (r-luma)/(2*(1-kr));
            int vx = (int)(h/2.0f + cb*h*0.9f), vy = (int)(h/2.0f-cr*h*0.9f);
            if (vx >= 0 && vx < h && vy >= 0 && vy < h)
                scope_add(&vec[vy*h+vx], r, g, b);
        }
    }
    scope_paint(wave, n, out.wave, false);
    scope_paint(vec, vn, out.vector, true);
    uint32_t maximum = 1;
    for (int i = 0; i < cw*h*4; i++) if (par[i] > maximum) maximum = par[i];
    const float colors[4][3] = {{1,.2,.2},{.2,1,.2},{.3,.4,1},{.85,.85,.85}};
    for (int c = 0; c < 4; c++) for (int x = 0; x < cw; x++) for (int l = 0; l < h; l++) {
        uint32_t count = par[(c*cw+x)*h+l];
        if (!count) continue;
        float v = fminf(count*4.0f/maximum, 1);
        int i = ((h-1-l)*w+c*(cw+2)+x)*4;
        out.parade[i] = colors[c][2]*v*255;
        out.parade[i+1] = colors[c][1]*v*255;
        out.parade[i+2] = colors[c][0]*v*255;
        out.parade[i+3] = 255;
    }
    free(lut); free(wave); free(vec); free(par);
    return true;
}
#endif
