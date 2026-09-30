from pathlib import Path
import json,hashlib,subprocess,plistlib,shlex
base=Path('/private/tmp/aagedal-live-authentic-20260930')
derived=Path('/private/tmp/aagedal-live-authentic-current-dd-20260930')
original_app=derived/'Build/Products/Release/Aagedal Media Player.app'
candidate_dir=base/'current-repaired-candidate';candidate_dir.mkdir(exist_ok=True)
assert not (candidate_dir/'relink-command.json').exists()
candidate_app=candidate_dir/original_app.name
subprocess.run(['/usr/bin/ditto',str(original_app),str(candidate_app)],check=True)
executable='Contents/MacOS/Aagedal Media Player'
lines=(base/'current-build.log').read_text().splitlines()
commands=[]
for line in lines:
 if '/usr/bin/clang ' in line and '-o ' in line:
  parsed=shlex.split(line.strip())
  if Path(parsed[parsed.index('-o')+1]).resolve()==(original_app/executable).resolve():commands.append(parsed)
assert len(commands)==1, len(commands)
original_command=commands[0]
(base/'current-original-link-command.json').write_text(json.dumps(original_command,indent=2)+'\n')
command=original_command[:]
# All newly written linker outputs stay in this isolated candidate, while the
# existing build objects/package archives remain read-only inputs.
command[command.index('-o')+1]=str(candidate_app/executable)
for option,name in [('-object_path_lto','player_lto.o'),('-dependency_info','player_dependency_info.dat')]:
 index=command.index(option)+1
 assert command[index]=='-Xlinker'
 command[index+1]=str(candidate_dir/name)
command.insert(1,'-F/private/tmp/aagedal-coreaudio-rebuilt-final-20260930')
command.extend(['-Xlinker','-map','-Xlinker',str(candidate_dir/'link.map')])
(candidate_dir/'relink-command.json').write_text(json.dumps(command,indent=2)+'\n')
with (candidate_dir/'relink.log').open('w') as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run(['/usr/bin/codesign','--force','--deep','--sign','-',str(candidate_app)],capture_output=True,text=True,check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(candidate_app)],capture_output=True,text=True,check=True)
manifest_files=list((derived/'Build/Products').glob('*.xctestrun'));assert len(manifest_files)==1
original_manifest=manifest_files[0]
original=plistlib.loads(original_manifest.read_bytes())
for name,seconds in [('compressed-90s',90),('fx6-selected-120s',120)]:
 d=base/name;inputs=json.loads((d/'inputs.json').read_text());run=plistlib.loads(original_manifest.read_bytes())
 for target in run['TestConfigurations'][0]['TestTargets']:
  target['TestHostPath']=str(candidate_app)
  env=target.setdefault('EnvironmentVariables',{})
  env['LIVE_AUDIO_METER_PROFILE_INPUTS']=json.dumps(inputs)
  env['LIVE_AUDIO_METER_PROFILE_SECONDS']=str(seconds)
 (d/'candidate.xctestrun').write_bytes(plistlib.dumps(run))
 current_head=(base/'current-source-head.txt').read_text().strip()
 environment=(d/'environment.txt').read_text().split('No build:')[0]
 (d/'environment.txt').write_text(environment+'Fresh build-for-testing followed by isolated repaired-dependency relink.\nSource head: '+current_head+'\nTest host: '+str(candidate_app)+'\nConcurrent dependency clean-build work: resource observations under contention.\n')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
paths=[original_app/executable,candidate_app/executable,candidate_app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests',original_manifest,base/'current-original-link-command.json',candidate_dir/'relink-command.json',candidate_dir/'link.map',Path('/private/tmp/aagedal-coreaudio-rebuilt-final-20260930/Libmpv.framework/Versions/A/Libmpv')]
(base/'current-linked-identities-before.json').write_text(json.dumps({str(p):sha(p) for p in paths},indent=2)+'\n')
for name in ['compressed-90s','fx6-selected-120s']:
 (base/name/'candidate-identities.json').write_text((base/'current-linked-identities-before.json').read_text())
print(original_manifest)
print(candidate_app)
