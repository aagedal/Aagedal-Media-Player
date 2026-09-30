from pathlib import Path
import hashlib,json,os,subprocess
repo=Path('/Users/truls.aagedal/Developer/Aagedal-Media-Player')
clone=Path('/private/tmp/aagedal-2-plan-resource-source-20260930')
artifacts=Path('/private/tmp/aagedal-2-plan-resource-verification-20260930')
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
assert subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True)==''
subprocess.run(['git','clone','--local','--no-checkout',str(repo),str(clone)],check=True)
subprocess.run(['git','checkout','--detach',commit],cwd=clone,check=True)
subprocess.run(['/usr/bin/ditto',str(repo/'Test Fixtures/Generated'),str(clone/'Test Fixtures/Generated')],check=True)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
fixtures={str(p.relative_to(clone)):sha(p) for p in sorted((clone/'Test Fixtures/Generated').rglob('*')) if p.is_file()}
source={str(p.relative_to(clone)):sha(p) for root in ['Aagedal Media Player','Aagedal Media Player Tests'] for p in sorted((clone/root).rglob('*.swift'))}
receipt=dict(sourceCommit=commit,sourceClone=str(clone),sourceStatus=subprocess.check_output(['git','status','--porcelain'],cwd=clone,text=True),generatedFixtures=fixtures,swiftSources=source,packageResolvedSHA256=sha(clone/'Aagedal Media Player.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'),qualification='Source-only local detached clone and copied existing ignored schema-5 fixtures. Entirely fresh DerivedData; no prior build database or products copied.')
assert receipt['sourceStatus']==''
Path('/private/tmp/aagedal-2-plan-resource-source-identity-20260930.json').write_text(json.dumps(receipt,indent=2)+'\n')
environment=os.environ.copy()
environment['AAGEDAL_CANDIDATE_PACKAGE_CACHE']='/private/tmp/aagedal-itu-live-dd-20260930/SourcePackages'
with Path('/private/tmp/aagedal-2-plan-resource-verifier-20260930.log').open('w') as log:
 result=subprocess.run(['bash','scripts/verify-release-candidate.sh',str(artifacts)],cwd=clone,env=environment,stdout=log,stderr=subprocess.STDOUT)
print('verifierExitCode='+str(result.returncode))
raise SystemExit(result.returncode)
