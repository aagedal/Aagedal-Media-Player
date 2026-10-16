# SPDX-License-Identifier: GPL-3.0-or-later
# Exact local acceptance helper; paths refer to the retained run.
from pathlib import Path
import importlib.util,json,hashlib
root=Path.cwd()
spec=importlib.util.spec_from_file_location('restore',root/'scripts/restore-mpv-decoder-raster-candidate.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
baseline=Path('/private/tmp/aagedal-native-raster-20261014/restored-handoff')
scopes=Path('/private/tmp/aagedal-scopes-delta-restored-r3-20261015')
r.verify_restored(baseline,json.loads((root/'docs/mpv-decoder-raster-handoff.json').read_text()))
r.verify_restored(scopes/'delta',json.loads((root/'docs/mpv-scopes-handoff.json').read_text()))
original=r.inventory(baseline/'MPVKit');current=r.inventory(scopes/'MPVKit')
changed=[p for p in original if original[p]!=current.get(p)]
assert changed==['Candidate/Libmpv-GPL/Libmpv.xcframework/macos-arm64/Libmpv.framework/Versions/A/Libmpv'],changed
assert original.keys()==current.keys()
assert r.sha(scopes/'MPVKit'/changed[0])==r.sha(scopes/'delta/libmpv.a')
base=Path('/private/tmp/aagedal-app-asan-20261016')
r.prepare_app(root,scopes/'MPVKit',base/'app')
fixtures=json.loads((baseline/'fixtures/fixtures.json').read_text())
for case in fixtures['cases']:
 case['input']=str(baseline/'fixtures'/Path(case['input']).name)
 if case.get('references'):case['references']=[str(baseline/'fixtures'/Path(p).name) for p in case['references']]
(base/'native-fixtures.json').write_text(json.dumps(fixtures,indent=2)+'\n')
print('Verified baseline, scope delta, all package files; prepared current app sources')
