// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "mpv/client.h"
#ifdef SCOPE_GPU
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
static NSWindow *window;
static CAMetalLayer *layer;
static void configure(mpv_handle *m) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,360)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    layer = [CAMetalLayer layer]; layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.frame = CGRectMake(0,0,640,360); layer.drawableSize = CGSizeMake(640,360);
    window.contentView.layer = layer; window.contentView.wantsLayer = YES;
    [window orderBack:nil];
    int64_t wid = (int64_t)(__bridge void *)layer;
    mpv_set_option(m,"wid",MPV_FORMAT_INT64,&wid);
    mpv_set_option_string(m,"vo","gpu-next");
    mpv_set_option_string(m,"gpu-api","vulkan");
    mpv_set_option_string(m,"gpu-context","moltenvk");
}
static void pump(void) {
    @autoreleasepool {
        NSEvent *e;
        while ((e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate date]
                     inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:e];
        [NSApp updateWindows];
    }
}
#else
static void configure(mpv_handle *m) { mpv_set_option_string(m,"vo","null"); }
static void pump(void) {}
#endif
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void check(int r) { if(r<0) { fprintf(stderr,"%s\n",mpv_error_string(r)); exit(2); } }
static mpv_node *field(mpv_node *n,const char *key) {
    if(n->format!=MPV_FORMAT_NODE_MAP) exit(3);
    for(int i=0;i<n->u.list->num;i++) if(!strcmp(n->u.list->keys[i],key)) return &n->u.list->values[i];
    fprintf(stderr,"missing %s\n",key);exit(3);
}
static int capture(mpv_handle*m,mpv_node *result,const char *width) {
    const char *args[]={"aagedal-scopes",width,NULL}; return mpv_command_ret(m,args,result);
}
int main(int argc,char **argv) {
    if(argc<5) return 1; // input output-prefix hwdec width [play]
    mpv_handle*m=mpv_create(); configure(m);
    mpv_set_option_string(m,"ao","null");mpv_set_option_string(m,"hwdec",argv[3]);
    mpv_set_option_string(m,"pause","yes");mpv_set_option_string(m,"keep-open","yes");
    mpv_set_option_string(m,"msg-level","all=error");check(mpv_initialize(m));
    mpv_node n={0}; if(capture(m,&n,argv[4])>=0) return 4;mpv_free_node_contents(&n);
    const char *load[]={"loadfile",argv[1],NULL};check(mpv_command(m,load));
    int ready=0;
    for(int i=0;i<300;i++) {pump();mpv_wait_event(m,.01);if(capture(m,&n,argv[4])>=0) {ready=1;break;}mpv_free_node_contents(&n);}
    if(!ready) return 5;
    int w=field(&n,"w")->u.int64,h=field(&n,"h")->u.int64;
    const char *keys[]={"waveform","parade","vectorscope"};
    for(int i=0;i<3;i++) {
        mpv_node *f=field(&n,keys[i]);if(f->format!=MPV_FORMAT_BYTE_ARRAY) return 6;
        mpv_byte_array *ba=f->u.ba;if(ba->size!=(size_t)(i==2?h*h:w*h)*4) return 6;
        char path[4096];snprintf(path,sizeof(path),"%s-%s.bgra",argv[2],keys[i]);
        FILE *file=fopen(path,"wb");if(!file)return 7;
        if(fwrite(ba->data,1,ba->size,file)!=ba->size)return 7;fclose(file);
    }
    printf("{\"w\":%d,\"h\":%d,\"pts\":%.9f,\"primaries\":\"%s\",\"transfer\":\"%s\",\"hardware\":%d,",
           w,h,field(&n,"pts")->u.double_,field(&n,"primaries")->u.string,
           field(&n,"transfer")->u.string,field(&n,"hardware-transfer")->u.flag);
    if(strcmp(argv[3],"no") && !field(&n,"hardware-transfer")->u.flag) return 8;
    mpv_free_node_contents(&n);
    const char *bad[]={"aagedal-scopes","2000000000",NULL};if(mpv_command_ret(m,bad,&n)>=0)return 9;mpv_free_node_contents(&n);
    if(argc>5) check(mpv_set_property_string(m,"pause","no"));
    double native=0,screenshot=0,first=-1,last=-1; int fresh=0;
    for(int i=0;i<30;i++) {
        pump();double start=now();check(capture(m,&n,argv[4]));native+=now()-start;
        last=field(&n,"pts")->u.double_;if(first<0)first=last;
        if(last>first)fresh++;mpv_free_node_contents(&n);
        const char *shot[]={"screenshot-raw","video",NULL};start=now();check(mpv_command_ret(m,shot,&n));screenshot+=now()-start;mpv_free_node_contents(&n);
        if(argc>5)mpv_wait_event(m,.01);
    }
    printf("\"nativeMeanMS\":%.4f,\"screenshotOnlyMeanMS\":%.4f,\"fresh\":%d,\"lastPTS\":%.9f,",native/30*1000,screenshot/30*1000,fresh,last);
    if(argc>5&&last<=first)return 10;
    check(mpv_set_property_string(m,"pause","yes"));
    const char *seek[]={"seek","1","absolute+exact",NULL};check(mpv_command(m,seek));
    ready=0;
    for(int i=0;i<300;i++){pump();mpv_wait_event(m,.01);if(capture(m,&n,argv[4])>=0){if(fabs(field(&n,"pts")->u.double_-1)<1e-6)ready=1;}mpv_free_node_contents(&n);if(ready)break;}
    if(!ready)return 11;
    const char *stop[]={"stop",NULL};check(mpv_command(m,stop));
    if(capture(m,&n,argv[4])>=0)return 12;mpv_free_node_contents(&n);
    mpv_terminate_destroy(m);printf("\"seekAndStop\":true}\n");return 0;
}
