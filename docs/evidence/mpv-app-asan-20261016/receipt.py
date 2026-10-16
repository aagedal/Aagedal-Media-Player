# SPDX-License-Identifier: GPL-3.0-or-later
# Exact local acceptance helper; paths refer to the retained run.
from pathlib import Path
import hashlib,json,subprocess,re
root=Path.cwd(); base=Path('/private/tmp/aagedal-app-asan-20261016')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
app=base/'derived/Build/Products/Release/Aagedal Media Player.app'
binaries=[app/'Contents/MacOS/Aagedal Media Player',app/'Contents/PlugIns/Aagedal Media Player Tests.xctest/Contents/MacOS/Aagedal Media Player Tests']
data={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(), 'sourceFilesSHA256':{},'binaries':{},'scope':'arm64 app and XCTest ASan; native dependency is uninstrumented'}
for folder in ['Aagedal Media Player','Aagedal Media Player Tests']:
 for p in sorted((root/folder).rglob('*.swift')):
  relative=p.relative_to(root)
  assert sha(p)==sha(base/'app'/relative),relative
  data['sourceFilesSHA256'][str(relative)]=sha(p)
for p in binaries:
 symbols=subprocess.check_output(['nm','-u',str(p)],text=True)
 asan=sorted(set(line.strip() for line in symbols.splitlines() if '__asan' in line))
 assert any('__asan_report_load' in s for s in asan),p
 arch=subprocess.check_output(['lipo','-archs',str(p)],text=True).strip()
 assert arch=='arm64',arch
 data['binaries'][str(p.relative_to(app))]={'sha256':sha(p),'architecture':arch,'asanUndefinedSymbols':asan}
log=(base/'build.log').read_text()
commands=[line for line in log.splitlines() if 'swiftc ' in line and '-sanitize\\=address' in line]
assert any('-module-name Aagedal_Media_Player ' in line for line in commands)
assert any('-module-name Aagedal_Media_Player_Tests ' in line for line in commands)
(base/'instrumented-compile-commands.txt').write_text('\n'.join(commands)+'\n')
data['buildLogSHA256']=sha(base/'build.log')
data['buildCommand']=log.splitlines()[1] if log.startswith('Command line invocation:') else log.splitlines()[0]
data['dependencyDescriptorsSHA256']={str(p):sha(p) for p in [Path('docs/mpv-decoder-raster-handoff.json'),Path('docs/mpv-scopes-handoff.json')]}
lib=Path('/private/tmp/aagedal-scopes-delta-restored-r3-20261015/delta/libmpv.a')
data['uninstrumentedLibmpvSHA256']=sha(lib)
data['fixtureManifestSHA256']=sha(base/'native-fixtures.json')
data['runnerSHA256']=sha(root/'docs/evidence/mpv-app-asan-20261016/run.py')
data['host']={cmd[0]:subprocess.check_output(cmd,text=True).strip() for cmd in [['sw_vers'],['uname','-m']]}
(base/'candidate-receipt.json').write_text(json.dumps(data,indent=2)+'\n')
(base/'source.patch').write_bytes(subprocess.check_output(['git','diff','--','Aagedal Media Player','Aagedal Media Player Tests']))
print('Verified matching app/test sources, arm64 binaries and ASan compiler/symbol evidence')
