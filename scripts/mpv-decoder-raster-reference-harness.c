// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Truls Aagedal
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mpv/client.h"
#ifdef AAGEDAL_GPU_HARNESS
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
static NSWindow *gpu_window;
static CAMetalLayer *gpu_layer;
static void configure_output(mpv_handle *player)
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    gpu_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    gpu_window.releasedWhenClosed = NO;
    gpu_window.title = @"Native raster validation";
    gpu_layer = [CAMetalLayer layer];
    gpu_layer.device = MTLCreateSystemDefaultDevice();
    gpu_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    gpu_layer.frame = CGRectMake(0, 0, 640, 360);
    gpu_layer.drawableSize = CGSizeMake(640, 360);
    gpu_window.contentView.wantsLayer = YES;
    gpu_window.contentView.layer = gpu_layer;
    [gpu_window orderBack:nil];
    int64_t wid = (int64_t)(__bridge void *)gpu_layer;
    if (mpv_set_option(player, "wid", MPV_FORMAT_INT64, &wid) < 0 ||
        mpv_set_option_string(player, "vo", "gpu-next") < 0 ||
        mpv_set_option_string(player, "gpu-api", "vulkan") < 0 ||
        mpv_set_option_string(player, "gpu-context", "moltenvk") < 0) exit(2);
}
static void pump(void)
{
    @autoreleasepool {
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate date]
                inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
        [NSApp updateWindows];
    }
}
#else
static void configure_output(mpv_handle *player) { if (mpv_set_option_string(player, "vo", "null") < 0) exit(2); }
static void pump(void) {}
#endif

static void check(int status, const char *operation)
{
    if (status < 0) { fprintf(stderr, "%s: %s\n", operation, mpv_error_string(status)); exit(2); }
}

static mpv_node *field(mpv_node *node, const char *key, mpv_format format)
{
    if (node->format != MPV_FORMAT_NODE_MAP) exit(3);
    for (int i = 0; i < node->u.list->num; i++) {
        if (!strcmp(node->u.list->keys[i], key)) {
            mpv_node *value = &node->u.list->values[i];
            if (value->format != format) exit(3);
            return value;
        }
    }
    fprintf(stderr, "missing field: %s\n", key);
    exit(3);
}

static int64_t integer(mpv_node *node, const char *key)
{
    return field(node, key, MPV_FORMAT_INT64)->u.int64;
}

static void unavailable(mpv_handle *player)
{
    const char *args[] = {"aagedal-decoder-raster", NULL};
    mpv_node node = {0};
    int status = mpv_command_ret(player, args, &node);
    mpv_free_node_contents(&node);
    double pts;
    if (status >= 0 || mpv_get_property(player, "aagedal-decoder-raster-pts", MPV_FORMAT_DOUBLE, &pts) >= 0) exit(8);
}

static int capture(mpv_handle *player, double expected_pts, const char *reference, char **argv)
{
    const char *args[] = {"aagedal-decoder-raster", NULL};
    mpv_node node = {0};
    if (mpv_command_ret(player, args, &node) < 0) return 0;
    double pts = field(&node, "pts", MPV_FORMAT_DOUBLE)->u.double_;
    if (!isfinite(pts) || fabs(pts - expected_pts) > 1e-8) { mpv_free_node_contents(&node); return 0; }
    int width = atoi(argv[4]), height = atoi(argv[5]);
    int bytes_per_pixel = atoi(argv[15]), tolerance = atoi(argv[14]);
    int64_t track = 0;
    check(mpv_get_property(player, "vid", MPV_FORMAT_INT64, &track), "vid");
    printf("{\"descriptor\":true,\"protocol\":%lld,\"codedWidth\":%lld,\"codedHeight\":%lld,\"rotation\":%lld,\"mirrored\":%d,\"depth\":%lld,\"transfer\":\"%s\",\"primaries\":\"%s\",\"hardwareTransfer\":%d}\n",
        (long long)integer(&node,"protocol"), (long long)integer(&node,"coded-w"), (long long)integer(&node,"coded-h"),
        (long long)integer(&node,"rotation"), field(&node,"mirrored",MPV_FORMAT_FLAG)->u.flag,
        (long long)integer(&node,"source-bit-depth"), field(&node,"transfer",MPV_FORMAT_STRING)->u.string,
        field(&node,"primaries",MPV_FORMAT_STRING)->u.string, field(&node,"hardware-transfer",MPV_FORMAT_FLAG)->u.flag);
    if (integer(&node, "protocol") != 2 || integer(&node, "track-id") != track ||
        integer(&node, "w") != width || integer(&node, "h") != height ||
        integer(&node, "coded-w") != atoi(argv[6]) || integer(&node, "coded-h") != atoi(argv[7]) ||
        integer(&node, "rotation") != atoi(argv[8]) ||
        field(&node, "mirrored", MPV_FORMAT_FLAG)->u.flag != atoi(argv[9]) ||
        integer(&node, "source-bit-depth") != atoi(argv[10]) ||
        strcmp(field(&node, "transfer", MPV_FORMAT_STRING)->u.string, argv[11]) ||
        strcmp(field(&node, "primaries", MPV_FORMAT_STRING)->u.string, argv[12]) ||
        strcmp(field(&node, "format", MPV_FORMAT_STRING)->u.string, bytes_per_pixel == 8 ? "rgba64" : "bgra") ||
        !field(&node, "pixel-preserving", MPV_FORMAT_FLAG)->u.flag ||
        !field(&node, "presented-frame", MPV_FORMAT_FLAG)->u.flag) exit(4);
    int hardware = strcmp(argv[13], "no") != 0;
    if (field(&node, "hardware-transfer", MPV_FORMAT_FLAG)->u.flag != hardware) exit(4);
    char *decoder = mpv_get_property_string(player, "hwdec-current");
    if (hardware && (!decoder || strcmp(decoder, argv[13]))) {
        fprintf(stderr, "hardware decode fell back: %s\n", decoder ? decoder : "missing"); exit(5);
    }
    mpv_free(decoder);
    int64_t stride = integer(&node, "stride");
    mpv_byte_array *data = field(&node, "data", MPV_FORMAT_BYTE_ARRAY)->u.ba;
    if (stride < (int64_t)width * bytes_per_pixel || stride > (72 * 1024 * 1024) / height ||
        !data || !data->data || data->size != (size_t)stride * height) exit(4);
    size_t expected_size = (size_t)width * height * bytes_per_pixel;
    FILE *file = fopen(reference, "rb");
    if (!file) exit(6);
    uint8_t *expected = malloc(expected_size);
    if (!expected || fread(expected, 1, expected_size, file) != expected_size || fgetc(file) != EOF) exit(6);
    fclose(file);
    uint8_t *actual = data->data;
    size_t mismatches = 0;
    int maximum_error = 0, component_size = bytes_per_pixel == 8 ? 2 : 1;
    uint8_t actual_levels[65536] = {0}, expected_levels[65536] = {0};
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width * bytes_per_pixel; x += component_size) {
            size_t a = (size_t)y * stride + x, e = (size_t)y * width * bytes_per_pixel + x;
            int av = actual[a], ev = expected[e];
            if (component_size == 2) { av |= actual[a + 1] << 8; ev |= expected[e + 1] << 8; }
            int error = abs(av - ev);
            if (error > maximum_error) maximum_error = error;
            if (error > tolerance) mismatches++;
            if (component_size == 2 && y == 0 && x % bytes_per_pixel == 0) {
                actual_levels[av] = expected_levels[ev] = 1;
            }
        }
    }
    free(expected);
    int actual_unique = 0, expected_unique = 0;
    for (int i = 0; i < 65536; i++) { actual_unique += actual_levels[i]; expected_unique += expected_levels[i]; }
    double fresh;
    check(mpv_get_property(player, "aagedal-decoder-raster-pts", MPV_FORMAT_DOUBLE, &fresh), "freshness");
    printf("{\"pts\":%.9f,\"width\":%d,\"height\":%d,\"hardwareTransfer\":%s,\"maximumComponentError\":%d,\"tolerance\":%d,\"mismatches\":%zu,\"actualUniqueLevels\":%d,\"referenceUniqueLevels\":%d}\n",
           pts, width, height, hardware ? "true" : "false", maximum_error, tolerance, mismatches, actual_unique, expected_unique);
    if (fresh != pts || mismatches || (expected_unique > 256 && actual_unique <= 256)) exit(7);
    mpv_free_node_contents(&node);
    return 1;
}

int main(int argc, char **argv)
{
    if (argc != 17) return 1;
    mpv_handle *player = mpv_create();
    if (!player) return 1;
    configure_output(player);
    check(mpv_set_option_string(player, "ao", "null"), "ao");
    check(mpv_set_option_string(player, "pause", "yes"), "pause");
    check(mpv_set_option_string(player, "vd-queue-enable", "no"), "queue");
    check(mpv_set_option_string(player, "hwdec", argv[13]), "hwdec");
    check(mpv_set_option_string(player, "deinterlace", "no"), "deinterlace");
    check(mpv_set_option_string(player, "keep-open", "yes"), "keep-open");
    check(mpv_set_option_string(player, "aagedal-decoder-raster", "yes"), "provider");
    check(mpv_initialize(player), "initialize");
    const char *load[] = {"loadfile", argv[1], NULL};
    check(mpv_command(player, load), "loadfile");
    int captured = 0;
    for (int i = 0; i < 1000 && !captured; i++) { pump(); mpv_wait_event(player, 0.01); captured = capture(player, 0, argv[2], argv); }
    if (!captured) return 9;
    const char *seek[] = {"seek", argv[16], "absolute+exact", NULL};
    check(mpv_command(player, seek), "seek");
    unavailable(player);
    captured = 0;
    for (int i = 0; i < 1000 && !captured; i++) { pump(); mpv_wait_event(player, 0.01); captured = capture(player, strtod(argv[16], NULL), argv[3], argv); }
    if (!captured) return 10;
    check(mpv_set_property_string(player, "pause", "no"), "resume");
    unavailable(player);
    mpv_terminate_destroy(player);
#ifdef AAGEDAL_GPU_HARNESS
    [gpu_window close];
#endif
    return 0;
}
