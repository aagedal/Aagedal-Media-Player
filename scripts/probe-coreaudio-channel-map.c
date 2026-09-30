// SPDX-License-Identifier: GPL-3.0-or-later
// Initialization-only reproduction of mpv 0.41.0's CoreAudio property mismatch.
// Build: clang -Wall -Wextra -Werror -framework AudioToolbox -framework CoreAudio \
//          scripts/probe-coreaudio-channel-map.c -o /tmp/probe-coreaudio-channel-map
// Run on a native macOS host; no render callback, playback or device setting changes.
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>

static OSStatus probe(UInt32 channels, int planar, int typed_map, int repetition)
{
    AudioComponentDescription desc = {
        kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
        kAudioUnitManufacturer_Apple, 0, 0
    };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    AudioUnit unit;
    OSStatus err = AudioComponentInstanceNew(comp, &unit);
    if (err) {
        fprintf(stderr, "AudioComponentInstanceNew failed: %d (native host access required)\n", (int)err);
        return err;
    }
    AudioDeviceID device = 0;
    UInt32 size = sizeof(device);
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);
    if (err) goto cleanup;
    err = AudioUnitInitialize(unit);
    if (err) goto cleanup;
    UInt32 bytes_per_frame = 4 * (planar ? 1 : channels);
    AudioStreamBasicDescription asbd = {
        .mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked |
            (planar ? kAudioFormatFlagIsNonInterleaved : 0),
        .mBytesPerPacket = bytes_per_frame, .mFramesPerPacket = 1,
        .mBytesPerFrame = bytes_per_frame, .mChannelsPerFrame = channels,
        .mBitsPerChannel = 32
    };
    err = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                              kAudioUnitScope_Input, 0, &asbd, sizeof(asbd));
    if (err) goto cleanup;
    err = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                              kAudioUnitScope_Global, 0, &device, sizeof(device));
    if (err) goto cleanup;

    AudioStreamBasicDescription output;
    size = sizeof(output);
    err = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                              kAudioUnitScope_Output, 0, &output, &size);
    if (err) goto cleanup;
    if (output.mChannelsPerFrame < 2 || output.mChannelsPerFrame > 8) {
        fprintf(stderr, "Probe needs a default output device with 2–8 channels.\n");
        err = kAudioUnitErr_FormatNotSupported;
        goto cleanup;
    }
    // Read physical preferred stereo positions instead of assuming channels 1/2.
    UInt32 stereo[2] = {0};
    size = sizeof(stereo);
    address = (AudioObjectPropertyAddress){
        kAudioDevicePropertyPreferredChannelsForStereo,
        kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain
    };
    err = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, stereo);
    if (err) goto cleanup;
    if (size != sizeof(stereo) || !stereo[0] || !stereo[1] || stereo[0] == stereo[1] ||
        stereo[0] > output.mChannelsPerFrame || stereo[1] > output.mChannelsPerFrame) {
        err = kAudioUnitErr_InvalidPropertyValue;
        goto cleanup;
    }
    SInt32 map[8];
    for (UInt32 n = 0; n < output.mChannelsPerFrame; ++n) map[n] = -1;
    map[stereo[0] - 1] = 0;
    map[stereo[1] - 1] = channels == 1 ? 0 : 1;

    // Match ca_get_acl's allocation size. Zero padding is deliberate: accepting
    // these malformed bytes is still not proof of a semantically correct map.
    size_t layout_size = sizeof(AudioChannelLayout) +
        (channels - 1) * sizeof(AudioChannelDescription);
    AudioChannelLayout *layout = calloc(1, layout_size);
    if (!layout) { err = kAudioUnitErr_FailedInitialization; goto cleanup; }
    layout->mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo;
    err = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap,
        typed_map ? kAudioUnitScope_Output : kAudioUnitScope_Global, 0,
        typed_map ? (const void *)map : (const void *)layout,
        typed_map ? output.mChannelsPerFrame * sizeof(map[0]) : (UInt32)layout_size);
    printf("{\"repetition\":%d,\"inputChannels\":%u,\"outputChannels\":%u,"
           "\"planar\":%s,\"typedMap\":%s,\"layoutTag\":%u,\"status\":%d}\n",
           repetition, channels, output.mChannelsPerFrame, planar ? "true" : "false",
           typed_map ? "true" : "false", layout->mChannelLayoutTag, (int)err);
    free(layout);
cleanup:
    AudioUnitUninitialize(unit);
    AudioComponentInstanceDispose(unit);
    return err;
}

int main(void)
{
    int corrected_failures = 0;
    for (int repetition = 0; repetition < 3; ++repetition)
        for (UInt32 channels = 1; channels <= 2; ++channels)
            for (int planar = 0; planar <= 1; ++planar) {
                (void)probe(channels, planar, 0, repetition);
                if (probe(channels, planar, 1, repetition) != noErr) ++corrected_failures;
            }
    return corrected_failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
