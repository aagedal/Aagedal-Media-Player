import hashlib,json,pathlib,statistics,subprocess,time,datetime
root=pathlib.Path(__file__).parent
binary=pathlib.Path('/Users/truls.aagedal/.t3/worktrees/Aagedal-Media-Player/t3code-5acffa80/Aagedal Media Player/Binaries/ffmpeg')
inputs=[pathlib.Path('/Users/truls.aagedal/Movies/TestVideo/testmappe_agedal_media_stitch/M4ROOT/CLIP/rre_8073.MP4'),pathlib.Path('/Users/truls.aagedal/Movies/TestVideo/A1_v_FX6/FX6/OJ_FX6A0021.MXF')]
def command(args):return subprocess.run(args,check=True,text=True,capture_output=True).stdout.strip()
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        while block:=f.read(8*1024*1024):h.update(block)
    return h.hexdigest()
receipt={'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'metric':'100 * (verified decoded frames / wall seconds) / source FPS','passThreshold':100,'limitation':'Software decode throughput only; no playback/render/audio/comparison/M1 qualification. Startup and output overhead are included.','binary':{'path':str(binary),'sha256':sha(binary),'version':command([str(binary),'-version']).splitlines()[0]},'hardware':{'model':command(['sysctl','-n','hw.model']),'memoryBytes':int(command(['sysctl','-n','hw.memsize'])),'logicalCores':int(command(['sysctl','-n','hw.logicalcpu'])),'macOS':command(['sw_vers','-productVersion'])},'powerBefore':command(['pmset','-g','batt']),'thermalBefore':command(['pmset','-g','therm']),'inputs':[]}
for index,path in enumerate(inputs):
    probe=json.loads((root/f'input-{index}.json').read_text())
    stream=probe['metadata']['streams'][0]
    a,b=map(int,stream['avg_frame_rate'].split('/'));fps=a/b
    item={'path':str(path),'sha256Before':sha(path),'size':path.stat().st_size,'codec':stream['codec_name'],'width':stream['width'],'height':stream['height'],'pixelFormat':stream['pix_fmt'],'sourceFPS':fps,'runs':[]}
    for repetition in range(4):
        frames=200 if repetition==0 else 600
        args=[str(binary),'-hide_banner','-nostdin','-loglevel','info','-benchmark','-i',str(path),'-map','0:v:0','-an','-sn','-dn','-frames:v',str(frames),'-fps_mode','passthrough','-progress','pipe:1','-nostats','-f','null','-']
        start=time.perf_counter();run=subprocess.run(args,text=True,capture_output=True);elapsed=time.perf_counter()-start
        prefix=root/f'decode-{index}-{repetition}'
        prefix.with_suffix('.stderr').write_text(run.stderr);prefix.with_suffix('.progress').write_text(run.stdout)
        progress=dict(line.split('=',1) for line in run.stdout.splitlines() if '=' in line)
        actual=int(progress.get('frame','0'));passed=run.returncode==0 and actual==frames and progress.get('progress')=='end'
        record={'repetition':repetition,'warmupDiscarded':repetition==0,'command':args,'returncode':run.returncode,'requestedFrames':frames,'decodedFrames':actual,'wallSeconds':elapsed,'complete':passed,'score':100*(actual/elapsed)/fps if passed else None}
        item['runs'].append(record)
        print(json.dumps({'input':index,**{k:record[k] for k in ['repetition','wallSeconds','complete','score']}}),flush=True)
        if not passed:raise RuntimeError(f'Decode failed: {prefix}')
    item['sha256After']=sha(path)
    assert item['sha256Before']==item['sha256After']
    scores=[r['score'] for r in item['runs'] if not r['warmupDiscarded']]
    item['medianScore']=statistics.median(scores);item['minimumScore']=min(scores);item['passesCurrentMachineDecodeThreshold']=min(scores)>100
    item['hypotheticalTwentyPercentScore']=item['medianScore']*0.2
    receipt['inputs'].append(item)
receipt['thermalAfter']=command(['pmset','-g','therm']);receipt['completedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
(root/'decode-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
