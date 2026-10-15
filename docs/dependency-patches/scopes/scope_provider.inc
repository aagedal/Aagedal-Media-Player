// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
// Included by player/screenshot.c, but does not use the screenshot pipeline.
#include "scope_math.h"

void cmd_aagedal_scopes(void *p)
{
    struct mp_cmd_ctx *cmd = p;
    struct MPContext *mpctx = cmd->mpctx;
    cmd->success = false;
    int w = cmd->args[0].v.i, h = (int)round(w*9.0/16);
    struct track *track = mpctx->current_track[0][STREAM_VIDEO];
    if (w < 64 || w > 1440 || !track || !track->dec ||
        mpctx->stop_play != KEEP_PLAYING || !mpctx->restart_complete ||
        mpctx->seek.type || mpctx->hrseek_active || !mpctx->video_out ||
        !mpctx->video_out->config_ok) return;
    // VO reference carries the frame's own PTS and post-filter color/geometry.
    // No wait for the next presentation, renderer screenshot, or second decoder.
    struct mp_image *src = vo_get_current_frame(mpctx->video_out);
    struct mp_image *rgb = NULL;
    struct mp_sws_context *sws = NULL;
    if (!src) return;
    if (src->w < 1 || src->h < 1 || src->w > 8192 || src->h > 8192 ||
        (int64_t)src->w * src->h > 33554432) { talloc_free(src); return; }
    int track_id = track->user_tid;
    double pts = src->pts;
    // The spawned command owns this reference while playback continues.
    mp_core_unlock(mpctx);
    bool hardware = IMGFMT_IS_HWACCEL(src->imgfmt);
    if (hardware) {
        struct mp_image *download = mp_image_hw_download(src, NULL);
        talloc_free(src); src = download;
        if (!src) { mp_core_lock(mpctx); return; }
    }
    mp_image_params_guess_csp(&src->params);
    const char *primaries = NULL, *transfer = NULL;
    if (src->w < 1 || src->h < 1 || src->w > 8192 || src->h > 8192 ||
        !isfinite(pts) || pts < 0 || src->params.rotate % 90 ||
        src->params.aagedal_transform_invalid ||
        !aagedal_color_encoding(src, &primaries, &transfer)) goto done;
    // Apply explicit crop before sampling; column ordering applies rotation later.
    if (mp_image_crop_valid(&src->params)) mp_image_crop_rc(src, src->params.crop);
    int maxaxis = MPMAX(src->w, src->h);
    int aw = MPMAX(1, (int)((int64_t)src->w * MPMIN(w,maxaxis)/maxaxis));
    int ah = MPMAX(1, (int)((int64_t)src->h * MPMIN(w,maxaxis)/maxaxis));
    rgb = mp_image_alloc(IMGFMT_RGBA64, aw, ah);
    if (!rgb) goto done;
    mp_image_copy_attributes(rgb, src);
    rgb->params.p_w = rgb->params.p_h = 1;
    rgb->params.rotate = 0; rgb->params.vflip = false;
    sws = mp_sws_alloc(NULL);
    // Encoded source RGB, preserving PQ/HLG. Never tone map or clamp to SDR8.
    if (mp_sws_scale(sws, rgb, src) < 0) goto done;
    int tf = !strcmp(transfer,"pq") ? 1 : !strcmp(transfer,"hlg") ? 2 : 0;
    float peak = tf == 1 ? 10000 : tf == 2 ? 1000 : 100;
    void *tmp = talloc_new(NULL);
    struct scope_plots plots = {.w=w, .h=h,
        .wave=talloc_zero_size(tmp,w*h*4), .parade=talloc_zero_size(tmp,w*h*4),
        .vector=talloc_zero_size(tmp,h*h*4)};
    if (!scope_compute((void *)rgb->planes[0],aw,ah,rgb->stride[0],
                       src->params.rotate,src->params.vflip,
                       !strcmp(primaries,"bt2020"),tf,peak,plots)) {
        talloc_free(tmp); goto done;
    }
    struct mpv_node *res = &cmd->result;
    node_init(res, MPV_FORMAT_NODE_MAP, NULL);
    node_map_add_int64(res,"protocol",1);
    node_map_add_int64(res,"w",w); node_map_add_int64(res,"h",h);
    node_map_add_int64(res,"track-id",track_id);
    node_map_add_double(res,"pts",pts); node_map_add_double(res,"peak-nits",peak);
    node_map_add_string(res,"primaries",primaries); node_map_add_string(res,"transfer",transfer);
    node_map_add_string(res,"format","bgra-premultiplied");
    node_map_add_flag(res,"hardware-transfer",hardware);
    const char *keys[] = {"waveform","parade","vectorscope"};
    uint8_t *data[] = {plots.wave,plots.parade,plots.vector};
    for (int i=0; i<3; i++) {
        struct mpv_byte_array *ba = node_map_add(res,keys[i],MPV_FORMAT_BYTE_ARRAY)->u.ba;
        *ba = (struct mpv_byte_array){data[i],(i==2 ? h*h : w*h)*4};
        talloc_steal(ba,data[i]);
    }
    talloc_free(tmp);
    cmd->success = true;
done:
    talloc_free(sws); talloc_free(rgb); talloc_free(src);
    mp_core_lock(mpctx);
    if (mpctx->stop_play != KEEP_PLAYING || mpctx->seek.type || mpctx->hrseek_active ||
        !mpctx->restart_complete || mpctx->current_track[0][STREAM_VIDEO] != track)
        cmd->success = false;
}
