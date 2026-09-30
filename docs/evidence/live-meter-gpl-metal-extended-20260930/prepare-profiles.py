from pathlib import Path
import hashlib,json,plistlib,subprocess
root=Path('/private/tmp/aagedal-gpl-metal-meter-repeat-20260930')
root.mkdir(exist_ok=False)
previous=Path('/private/tmp/aagedal-live-meter-gpl-metal-native-ready-20260930/authentic-5s')
paths=[(Path('/Users/truls.aagedal/Movies/TestVideo/A1_v_FX6/FX6/OJ_FX6A0021.MXF'),7,120,'fx6-120s'),(Path('/Users/truls.aagedal/Movies/TestVideo/GoPro/DolomitesSet1-Hero9-GX019609.MP4'),0,90,'aac-90s'),(Path('/Users/truls.aagedal/Movies/TestVideo/Interstellar_2014_copy.mkv'),0,30,'dts-30s'),(Path('/Users/truls.aagedal/Movies/TestVideo/Interstellar_2014_copy.mkv'),2,30,'ac3-30s')]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
identities=json.loads((previous/'candidate-identities-after.json').read_text())
for p,h in identities.items():
 assert sha(Path(p))==h,p
(root/'candidate-identities-before.json').write_text(json.dumps(identities,indent=2)+'\n')
for p,ordinal,seconds,name in paths:
 d=root/name;d.mkdir()
 inputs=[dict(path=str(p),sha256=sha(p),audioStreamOrderIndex=ordinal,audioTrackSelectionExplicit=True)]
 (d/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
 r=plistlib.loads((previous/'candidate.xctestrun').read_bytes())
 for target in r['TestConfigurations'][0]['TestTargets']:
  env=target.setdefault('EnvironmentVariables',{})
  env['LIVE_AUDIO_METER_PROFILE_INPUTS']=json.dumps(inputs)
  env['LIVE_AUDIO_METER_PROFILE_SECONDS']=str(seconds)
 (d/'candidate.xctestrun').write_bytes(plistlib.dumps(r))
 (d/'environment.txt').write_text(subprocess.check_output(['git','rev-parse','HEAD'],text=True)+subprocess.check_output(['sw_vers'],text=True)+f'Build configuration: Release\nObservation seconds: {seconds}\nExisting independently linked GPL/Metal candidate; prior source and original app/test identities retained.\n')
print(root)
