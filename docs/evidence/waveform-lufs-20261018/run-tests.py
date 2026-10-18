from pathlib import Path
import json, plistlib, subprocess, tempfile
base=Path('/private/tmp/aagedal-waveform-lufs-20261018')
products=base/'derived/Build/Products'
source,=products.glob('*.xctestrun')
configuration=plistlib.loads(source.read_bytes())
targets=[target for c in configuration['TestConfigurations'] for target in c['TestTargets'] if 'Aagedal Media Player Tests' in target.get('TestBundlePath','')]
target,=targets
for name in list(target.setdefault('EnvironmentVariables',{})):
 if name.startswith(('LIVE_LOUPE_','MPV_DECODER_RASTER_','MallocStackLogging')):
  del target['EnvironmentVariables'][name]
target['EnvironmentVariables']['WAVEFORM_LUFS_PREVIEW_DIR']=str(base)
target['ParallelizationEnabled']=False
out=base/'tests'
out.mkdir(exist_ok=False)
(out/'configuration.plist').write_bytes(plistlib.dumps(configuration))
with tempfile.NamedTemporaryFile(suffix='.xctestrun',dir=source.parent) as f:
 f.write(plistlib.dumps(configuration));f.flush()
 command=['xcodebuild','test-without-building','-xctestrun',f.name,'-destination','platform=macOS,arch=arm64','-parallel-testing-enabled','NO','-resultBundlePath',str(out/'results.xcresult')]
 for suite in ['WaveformLoudnessTests','AudioWaveformGeneratorTests','ProgrammeLoudnessControllerTests','ProgrammeLoudnessTests','LoudnessAnalysisTests','TrackSelectionControllerTests']:
  command+=['-only-testing:Aagedal Media Player Tests/'+suite]
 (out/'command.json').write_text(json.dumps(command,indent=2))
 with (out/'xcodebuild.log').open('w') as log:
  result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
summary=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(out/'results.xcresult')],capture_output=True,text=True,check=True)
(out/'summary.json').write_text(summary.stdout)
s=json.loads(summary.stdout)
print(json.dumps({key:s[key] for key in ['result','passedTests','failedTests','skippedTests','runtimeWarnings']},indent=2))
raise SystemExit(result.returncode or int(s['failedTests']>0 or s['skippedTests']>0 or bool(s['runtimeWarnings'])))
