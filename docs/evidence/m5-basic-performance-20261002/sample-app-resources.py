import datetime,json,pathlib,signal,subprocess,sys,time,os
root=pathlib.Path(__file__).parent
needle='aagedal-m5-basic-performance-20261002/DerivedData/Build/Products/Release/Aagedal Media Player.app/Contents/MacOS/Aagedal Media Player'
pathlib.Path(sys.argv[1]+'.pid').write_text(str(os.getpid()))
running=True
def stop(*_):
    global running
    running=False
signal.signal(signal.SIGTERM,stop)
with pathlib.Path(sys.argv[1]).open('x') as target:
    while running:
        output=subprocess.run(['ps','-axo','pid,ppid,%cpu,rss,comm'],text=True,capture_output=True,check=True).stdout
        for row in output.splitlines()[1:]:
            fields=row.split(None,4)
            if len(fields)==5 and needle in fields[4]:
                target.write(json.dumps({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pid':int(fields[0]),'parentPid':int(fields[1]),'cpuPercentOneCore':float(fields[2]),'rssKiB':int(fields[3])})+'\n');target.flush()
        time.sleep(1)
