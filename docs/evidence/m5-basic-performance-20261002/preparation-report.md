Generating 3840x2160, 24 fps, 10-bit HDR comparison fixtures…
Building the Compare Mode integration tests…
Profiling all four backend pairings plus mixed-backend visual, live-scope, and loupe canvases for 30 seconds each…
# Compare Mode production-resolution profile

- Hardware: MacBook Pro / Apple M5 Pro / 64 GB
- Model identifier: Mac17,8
- macOS: 27.0.1
- Xcode: Xcode 27.0 Build version 27A266a
- Git: 53d055b7f1839f5a6c209e9441c1c4e764592f15 (clean at profile start)
- Power before measured run: Now drawing from 'Battery Power'
- Low Power Mode values before measured run: Unknown
- Thermal state before measured run: Note: No thermal warning level has been recorded Note: No performance warning level has been recorded Note: No CPU power status has been recorded 
- Thermal state after measured run: Note: No thermal warning level has been recorded Note: No performance warning level has been recorded Note: No CPU power status has been recorded 
- Thermal sampling: pmset every 2 seconds during the run (thermal.log retained with raw artifacts)
- Fixture: 3840x2160 at 24 fps, HEVC Main 10, BT.2020/PQ
- Container horizontal reflection (both sources): 0
- Fixture bytes (A/B): 59758910/61411578
- Approximate fixture bitrate Mbps (A/B): 13.66/13.65
- Fixture encoder: ffmpeg version 9.0.2 Copyright (c) 2000-2026 the FFmpeg developers
- Render surface: 3840x2160 per decoder
- Sustained observation: 30 seconds per backend pairing
- Resource totals: xcodebuild command accounting; separately hosted app processes may be excluded

```text
COMPARE_PROFILE_VISUAL pair=avFoundation/mpv, canvas=3840x2160, visualUpdates=300, coveredModes=7/7, coveredGuideStates=20/20, maxMainActorDelay=0.007s, pair=avFoundation/mpv, samples=1118, withinFrame=99.0%, worstDrift=0.063s, longestExcursion=0.056s, signedDrift=0.063s→0.032s, finalDrift=0.032s, secondaryRate=0.87–1.00, primaryAdvance=30.016s, secondaryAdvance=29.958s
COMPARE_PROFILE pair=mpv/mpv, samples=1119, withinFrame=98.8%, worstDrift=0.125s, longestExcursion=0.215s, signedDrift=-0.125s→-0.042s, finalDrift=0.042s, secondaryRate=1.00–1.25, primaryAdvance=30.042s, secondaryAdvance=30.125s
COMPARE_PROFILE pair=avFoundation/avFoundation, samples=1135, withinFrame=100.0%, worstDrift=0.021s, longestExcursion=0.000s, signedDrift=-0.021s→-0.021s, finalDrift=0.021s, secondaryRate=1.00–1.00, primaryAdvance=30.014s, secondaryAdvance=30.014s
COMPARE_PROFILE_SCOPE pair=mpv/avFoundation, scopeRenders=344, coveredSources=3/3, renderedSourceNames=difference,primary,secondary, captureAdvance=387/316, maxMainActorDelay=0.090s, pair=mpv/avFoundation, samples=494, withinFrame=72.9%, worstDrift=0.201s, longestExcursion=0.722s, signedDrift=-0.125s→-0.010s, finalDrift=0.010s, secondaryRate=1.00–1.00, primaryAdvance=30.000s, secondaryAdvance=30.115s
COMPARE_PROFILE pair=avFoundation/mpv, samples=1126, withinFrame=99.5%, worstDrift=0.055s, longestExcursion=0.027s, signedDrift=-0.042s→-0.020s, finalDrift=0.020s, secondaryRate=1.00–1.13, primaryAdvance=30.005s, secondaryAdvance=30.042s
COMPARE_PROFILE_LOUPE pair=mpv/avFoundation, canvas=3840x2160, loupeUpdates=555, coveredMagnifications=3/3, scopeRenders=198, coveredScopeSources=3/3, freshCaptures=174/143, observationSeconds=30.136, captureFPS=5.77/4.75, maxCaptureGap=0.351s/0.569s, maxMainActorDelay=0.123s, pair=mpv/avFoundation, samples=389, withinFrame=49.6%, worstDrift=0.194s, longestExcursion=0.717s, signedDrift=0.013s→0.027s, finalDrift=0.027s, secondaryRate=1.00–1.00, primaryAdvance=30.083s, secondaryAdvance=30.081s
COMPARE_PROFILE pair=mpv/avFoundation, samples=1122, withinFrame=83.3%, worstDrift=0.242s, longestExcursion=0.350s, signedDrift=0.011s→0.026s, finalDrift=0.026s, secondaryRate=1.00–1.00, primaryAdvance=30.000s, secondaryAdvance=29.999s
COMPARE_PROFILE_VISUAL pair=mpv/avFoundation, canvas=3840x2160, visualUpdates=300, coveredModes=7/7, coveredGuideStates=20/20, maxMainActorDelay=0.010s, pair=mpv/avFoundation, samples=1108, withinFrame=52.3%, worstDrift=0.224s, longestExcursion=0.339s, signedDrift=0.007s→-0.006s, finalDrift=0.006s, secondaryRate=1.00–1.00, primaryAdvance=30.000s, secondaryAdvance=29.972s
COMPARE_PROFILE_LOUPE pair=avFoundation/mpv, canvas=3840x2160, loupeUpdates=584, coveredMagnifications=3/3, scopeRenders=230, coveredScopeSources=3/3, freshCaptures=172/175, observationSeconds=30.027, captureFPS=5.73/5.83, maxCaptureGap=0.400s/0.320s, maxMainActorDelay=0.120s, pair=avFoundation/mpv, samples=439, withinFrame=100.0%, worstDrift=0.042s, longestExcursion=0.000s, signedDrift=-0.042s→-0.019s, finalDrift=0.019s, secondaryRate=1.00–1.10, primaryAdvance=30.049s, secondaryAdvance=30.083s
COMPARE_PROFILE_SCOPE pair=avFoundation/mpv, scopeRenders=476, coveredSources=3/3, renderedSourceNames=difference,primary,secondary, captureAdvance=360/361, maxMainActorDelay=0.074s, pair=avFoundation/mpv, samples=620, withinFrame=100.0%, worstDrift=0.041s, longestExcursion=0.000s, signedDrift=0.012s→0.022s, finalDrift=0.022s, secondaryRate=1.00–1.00, primaryAdvance=30.022s, secondaryAdvance=30.042s
real 319.80
user 1.43
sys 0.83
          1080279040  maximum resident set size
```

Distinct thermal observations during the run:
```text
Note: No CPU power status has been recorded
Note: No performance warning level has been recorded
Note: No thermal warning level has been recorded
```

Decoder drift signposts are available in Instruments under the CompareMode category.
Fixtures retained at: /private/tmp/aagedal-m5-basic-performance-20261002/fixtures
Raw artifacts retained at: /private/tmp/aagedal-m5-basic-performance-20261002/preparation-artifacts
