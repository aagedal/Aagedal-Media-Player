from pathlib import Path
import subprocess,plistlib,hashlib,json,datetime
repo=Path('/Users/truls.aagedal/Developer/Aagedal-Media-Player')
root=Path('/tmp/aagedal-authentic-production-metadata-v3-20260930');root.mkdir(exist_ok=False)
derived=Path('/tmp/aagedal-live-authentic-current-dd-20260930')
template=next((derived/'Build/Products').glob('*.xctestrun'))
app=derived/'Build/Products/Release/Aagedal Media Player.app'
inputs=[Path('/Users/truls.aagedal/Movies/TestVideo/testmappe_agedal_media_stitch/M4ROOT/CLIP/rre_8073.MP4'),Path('/Users/truls.aagedal/Movies/TestVideo/Sony A1 Card/M4ROOT/CLIP/20260502_TRA_MOV_0240.MP4'),Path('/Users/truls.aagedal/Movies/TestVideo/A1_v_FX6/FX6/OJ_FX6A0021.MXF')]
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()
tracked=[app/'Contents/MacOS/Aagedal Media Player',app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests',repo/'Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',repo/'Aagedal Media Player Tests/ProductionMetadataMemoryPerformanceTests.swift',repo/'Aagedal Media Player/Logic/MetadataService.swift',template,*inputs]
for p in inputs:
 tracked += [q for q in p.parent.iterdir() if q.is_file() and q.suffix.lower()=='.xml' and q.stem.startswith(p.stem)]
before={str(p):{'sha256':digest(p),'bytes':p.stat().st_size} for p in tracked}
env={'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceHEAD':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'worktreeStatus':subprocess.check_output(['git','status','--short'],cwd=repo,text=True),'buildEnvironment':'Current shipping-pin Release build-for-testing; development Review edits; concurrent clean dependency build. No throughput/thermal acceptance.','inputsAndBinariesBefore':before}
(root/'environment.json').write_text(json.dumps(env,indent=2)+'\n')
for i,p in enumerate(inputs):
 data=plistlib.loads(template.read_bytes().replace(b'__TESTROOT__',str(derived/'Build/Products').encode()))
 for config in data['TestConfigurations']:
  for target in config['TestTargets']:
   target.setdefault('EnvironmentVariables',{}).update({'METADATA_MEMORY_PROFILE_INPUT':str(p),'METADATA_MEMORY_PROFILE_INPUT_INDEX':str(i)})
 manifest=root/f'input-{i}.xctestrun';manifest.write_bytes(plistlib.dumps(data))
 run=root/'runs'/f'input-{i}';run.mkdir(parents=True)
 print(f'Running authentic metadata input {i}: {p.name}',flush=True)
 with (run/'profile.log').open('w') as log:
  subprocess.run(['xcodebuild','test-without-building','-xctestrun',str(manifest),'-destination','platform=macOS','-derivedDataPath',str(derived),'-parallel-testing-enabled','NO','-test-timeouts-enabled','NO','-resultBundlePath',str(run/'Profile.xcresult'),'-only-testing:Aagedal Media Player Tests/ProductionMetadataMemoryPerformanceTests/testProductionMetadataMemoryProfileWhenRequested'],stdout=log,stderr=subprocess.STDOUT,check=True)
 subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(run/'Profile.xcresult'),'--output-path',str(root/'attachments'/f'input-{i}')],stdout=subprocess.DEVNULL,check=True)
after={str(p):{'sha256':digest(p),'bytes':p.stat().st_size} for p in tracked}
assert before==after, 'source/media/binary identity changed'
env['inputsAndBinariesUnchangedAfter']=True;env['endedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
(root/'environment.json').write_text(json.dumps(env,indent=2)+'\n')
with (root/'validation.log').open('w') as log:
 subprocess.run(['python3',str(repo/'scripts/validate-production-metadata-memory-profile.py'),str(root),'3'],stdout=log,stderr=subprocess.STDOUT,check=True)
print('All three fresh-host authentic metadata runs passed.',flush=True)
