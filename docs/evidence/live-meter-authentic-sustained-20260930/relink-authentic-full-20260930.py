from pathlib import Path
import json,hashlib,subprocess,plistlib
base=Path('/private/tmp/aagedal-live-authentic-20260930')
derived=Path('/private/tmp/aagedal-live-authentic-current-dd-20260930')
original_app=derived/'Build/Products/Release/Aagedal Media Player.app'
dir=base/'fullbuild-repaired-candidate';dir.mkdir(exist_ok=False)
app=dir/original_app.name
subprocess.run(['/usr/bin/ditto',str(original_app),str(app)],check=True)
command=json.loads((base/'current-original-link-command.json').read_text())
command[command.index('-o')+1]=str(app/'Contents/MacOS/Aagedal Media Player')
for option,name in [('-object_path_lto','player_lto.o'),('-dependency_info','player_dependency_info.dat')]:
 i=command.index(option)+1;assert command[i]=='-Xlinker';command[i+1]=str(dir/name)
full=Path('/private/tmp/aagedal-coreaudio-clean-build-v4-20260930/MPVKit')
framework_roots=[full/'dist/libmpv/macos',full/'dist/FFmpeg/macos']
command[1:1]=['-F'+str(p) for p in framework_roots]
command.extend(['-Xlinker','-map','-Xlinker',str(dir/'link.map')])
(dir/'relink-command.json').write_text(json.dumps(command,indent=2)+'\n')
with (dir/'relink.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(app)],capture_output=True,text=True,check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],capture_output=True,text=True,check=True)
manifest_files=list((derived/'Build/Products').glob('*.xctestrun'));assert len(manifest_files)==1
original_manifest=manifest_files[0]
d=base/'fullbuild-authentic-30s';d.mkdir()
inventory=json.loads((base/'input-inventory.json').read_text())
inputs=[{'path':inventory[i]['path'],'sha256':inventory[i]['sha256'],'audioStreamOrderIndex':order,'audioTrackSelectionExplicit':True} for i,order in [(0,0),(2,7)]]
preparation=json.loads((base/'itu-layout-preparation.json').read_text())
inputs.append({'path':preparation['preparedPath'],'sha256':preparation['preparedSHA256'],'audioStreamOrderIndex':0,'audioTrackSelectionExplicit':True})
(d/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
run=plistlib.loads(original_manifest.read_bytes())
for target in run['TestConfigurations'][0]['TestTargets']:
 target['TestHostPath']=str(app)
 env=target.setdefault('EnvironmentVariables',{})
 env['LIVE_AUDIO_METER_PROFILE_INPUTS']=json.dumps(inputs);env['LIVE_AUDIO_METER_PROFILE_SECONDS']='30'
def resolve(x):
 if isinstance(x,dict):return {k:resolve(v) for k,v in x.items()}
 if isinstance(x,list):return [resolve(v) for v in x]
 if isinstance(x,str):return x.replace('__TESTROOT__/Release/Aagedal Media Player.app',str(app)).replace('__TESTROOT__',str(derived/'Build/Products'))
 return x
(d/'candidate.xctestrun').write_bytes(plistlib.dumps(resolve(run)))
environment=(base/'compressed-90s/environment.txt').read_text().split('Observation seconds:')[0]
(d/'environment.txt').write_text(environment+'Observation seconds: 30\nBuild configuration: Release\nFresh current app with full dual-architecture dependency candidate, arm64 playback only.\nSource head: '+(base/'current-source-head.txt').read_text()+'\nTest host: '+str(app)+'\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
frameworks=[p for root in framework_roots for p in root.glob('*.framework')]
assert len(frameworks)==8,len(frameworks)
paths=[app/'Contents/MacOS/Aagedal Media Player',app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests',d/'candidate.xctestrun',dir/'link.map',dir/'relink-command.json']+[p/p.stem for p in frameworks]
(d/'candidate-identities.json').write_text(json.dumps({str(p):sha(p) for p in paths},indent=2)+'\n')
print(app)
