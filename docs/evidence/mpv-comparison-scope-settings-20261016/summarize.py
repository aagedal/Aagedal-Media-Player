from pathlib import Path
import json,re,collections
base=Path('/private/tmp/aagedal-scope-settings-20261016')
s=(base/'soak/xcodebuild.log').read_text()
rows=collections.defaultdict(list)
for line in s.splitlines():
 if not line.startswith('MPV_'):continue
 tag,_,body=line.partition(': ')
 row={k:v.strip() for k,v in re.findall(r'(\w+)=([^,]+)',body)}
 rows[tag].append(row)
loupes=rows['MPV_COMPARISON_LOUPE_WINDOW'];scopes=rows['MPV_COMPARISON_SCOPE_WINDOW'];cycles=rows['MPV_COMPARISON_LOUPE_SOAK_CYCLE'];mem=rows['MPV_COMPARISON_LOUPE_MEMORY']
out={'loupeWindows':len(loupes),'scopeWindows':len(scopes),'completedCycles':len(cycles)}
if loupes:
 out.update(minimumLoupeFPS=min(float(r['fps']) for r in loupes),maximumDriftSeconds=max(float(r['maxDrift']) for r in loupes),usableClockSamples=sum(int(r['validSamples'].split('/')[0]) for r in loupes),expectedClockSamples=30*len(loupes))
if scopes:
 out['scopePublicationsBySelection']={k:{'windows':len(v),'minimumObservedFPS':min(float(r['fps']) for r in v),'maximumObservedFPS':max(float(r['fps']) for r in v),'publications':sum(int(r['renders']) for r in v)} for k,v in ((k,[r for r in scopes if r['selection']==k]) for k in ['primary','secondary','difference']) if v}
if cycles:
 vals=[int(r['physicalFootprintBytes']) for r in cycles]
 out['cycleEndPhysicalFootprintBytes']=vals;out['maximumGrowthAboveWarmupBytes']=max(vals)-vals[0]
if mem:out['maximumSampledInPlaybackPhysicalFootprintBytes']=max(int(r['physicalFootprintBytes']) for r in mem)
out['assertionFailures']=[l for l in s.splitlines() if ': error:' in l or 'failed -' in l]
(base/'soak-stats.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
