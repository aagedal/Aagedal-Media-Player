// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Truls Aagedal
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "mpv/client.h"
static void check(int code,const char *what) {if(code<0){fprintf(stderr,"%s: %s\n",what,mpv_error_string(code));exit(2);}}
static void option(mpv_handle*m,const char*k,const char*v){check(mpv_set_option_string(m,k,v),k);}
static void set(mpv_handle*m,const char*k,const char*v){check(mpv_set_property_string(m,k,v),k);}
static void command(mpv_handle*m,const char **args){check(mpv_command(m,args),args[0]);}
static mpv_node *field(mpv_node*n,const char*k,mpv_format format) {
 if(n->format!=MPV_FORMAT_NODE_MAP){fprintf(stderr,"map type\n");exit(3);}
 for(int i=0;i<n->u.list->num;i++)if(!strcmp(n->u.list->keys[i],k)){
  mpv_node*r=&n->u.list->values[i];if(r->format!=format){fprintf(stderr,"type: %s\n",k);exit(3);}return r;
 }
 fprintf(stderr,"missing: %s\n",k);exit(3);
}
static long long integer(mpv_node*n,const char*k){return field(n,k,MPV_FORMAT_INT64)->u.int64;}
static void reject(mpv_handle*m,const char*label){double pts=NAN;int r=mpv_get_property(m,"aagedal-decoder-raster-pts",MPV_FORMAT_DOUBLE,&pts);printf("{\"%s\":%s}\n",label,r<0?"true":"false");if(r>=0)exit(5);}
static int capture(mpv_handle*m,double expected){
 const char*cmd[]={"aagedal-decoder-raster",NULL};mpv_node n={0};int r=mpv_command_ret(m,cmd,&n);if(r<0)return r;
 double pts=field(&n,"pts",MPV_FORMAT_DOUBLE)->u.double_;if(!isfinite(pts)||pts<0)exit(3);
 if(fabs(pts-expected)>1e-9){mpv_free_node_contents(&n);return -1;}
 int64_t vid=0;check(mpv_get_property(m,"vid",MPV_FORMAT_INT64,&vid),"vid");
 if(integer(&n,"protocol")!=1||integer(&n,"w")!=16||integer(&n,"h")!=16||integer(&n,"coded-w")!=16||integer(&n,"coded-h")!=16||integer(&n,"rotation")!=0||integer(&n,"track-id")!=vid||strcmp(field(&n,"format",MPV_FORMAT_STRING)->u.string,"bgra")||field(&n,"mirrored",MPV_FORMAT_FLAG)->u.flag||!field(&n,"pixel-preserving",MPV_FORMAT_FLAG)->u.flag||!field(&n,"presented-frame",MPV_FORMAT_FLAG)->u.flag)exit(3);
 long long stride=integer(&n,"stride");mpv_byte_array*b=field(&n,"data",MPV_FORMAT_BYTE_ARRAY)->u.ba;
 if(stride<64||stride>1048576||!b||!b->data||b->size<(size_t)stride*16)exit(3);
 unsigned char*data=b->data;int mismatch=0;
 for(int y=0;y<16;y++)for(int x=0;x<16;x++){
  unsigned char*pixel=data+y*stride+x*4;
  if(pixel[0]!=(x+y)*7||pixel[1]!=y*13||pixel[2]!=(x*13+(int)llround(expected*5)*17)%256||pixel[3]!=255)mismatch++;
 }
 double fresh=NAN;check(mpv_get_property(m,"aagedal-decoder-raster-pts",MPV_FORMAT_DOUBLE,&fresh),"freshness");if(fresh!=pts)exit(4);
 printf("{\"capture\":\"passed\",\"expectedPTS\":%.9f,\"pts\":%.9f,\"freshness\":true,\"pixelMismatches\":%d}\n",expected,pts,mismatch);
 mpv_free_node_contents(&n);if(mismatch)exit(4);return 0;
}
static int wait_capture(mpv_handle*m,double expected){for(int i=0;i<100;i++){mpv_wait_event(m,0.03);if(capture(m,expected)>=0)return 1;}return 0;}
int main(int argc,char**argv){
 if(argc<2)return 1;mpv_handle*m=mpv_create();if(!m)return 1;
 option(m,"vo","null");option(m,"ao","null");option(m,"hwdec","no");option(m,"log-file","/tmp/aagedal-decoder-provider-runtime.log");option(m,"msg-level","all=trace");
 if(argc<3||strcmp(argv[2],"queue"))option(m,"vd-queue-enable","no");option(m,"pause","yes");
 if(argc<3||strcmp(argv[2],"default"))option(m,"aagedal-decoder-raster",argc>2&&!strcmp(argv[2],"no")?"no":"yes");check(mpv_initialize(m),"initialize");
 const char*load[]={"loadfile",argv[1],NULL};command(m,load);int good=wait_capture(m,0);printf("{\"available\":%s}\n",good?"true":"false");
 int expected_available=argc<3||!strcmp(argv[2],"queue");if(good!=expected_available)return 6;
 if(good){
  set(m,"pause","no");reject(m,"playingPropertyRejected");set(m,"pause","yes");
  const char*seek[]={"seek","1","absolute+exact",NULL};command(m,seek);reject(m,"seekPropertyRejectedImmediately");if(!wait_capture(m,1))return 7;
  const char*step[]={"frame-step",NULL};command(m,step);if(!wait_capture(m,1.2))return 8;printf("{\"frameStepQualified\":true}\n");
  set(m,"video-crop","8x8+0+0");reject(m,"cropPropertyRejected");set(m,"video-crop","");if(!wait_capture(m,1.2))return 9;
  set(m,"video-aspect-override","2");reject(m,"aspectOverridePropertyRejected");set(m,"video-aspect-override","-2");if(!wait_capture(m,1.2))return 9;
  set(m,"deinterlace","yes");reject(m,"deinterlacePropertyRejected");set(m,"deinterlace","no");if(!wait_capture(m,1.2))return 9;
  set(m,"video-rotate","90");reject(m,"rotateOverridePropertyRejected");set(m,"video-rotate","0");if(!wait_capture(m,1.2))return 9;
  const char*vf[]={"vf","add","hflip",NULL};command(m,vf);reject(m,"filterPropertyRejected");
 }
 mpv_terminate_destroy(m);return 0;
}
