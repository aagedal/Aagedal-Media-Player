import os,json,collections,pathlib,time
source=pathlib.Path('/Users/truls.aagedal/Movies/TestVideo/A1_v_FX6/FX6/OJ_FX6A0021.MXF')
size=source.stat().st_size;page_size=os.sysconf('SC_PAGE_SIZE');fd=os.open(source,os.O_RDONLY)
start=time.monotonic();at=0;count=0;keys=collections.Counter();pages=set();logical=0;peek_bytes=0;maximum=0;limit=250000
while size-at>=17 and count<limit:
 header=os.pread(fd,25,at)
 if len(header)<17:break
 first=header[16];n=0 if first<128 else first&127
 if n>8 or len(header)<17+n:break
 length=first if n==0 else int.from_bytes(header[17:17+n],'big')
 value_start=at+17+n
 if length>size-value_start:break
 peek=min(length,512);end=value_start+peek
 if end>at:pages.update(range(at//page_size,(end-1)//page_size+1))
 keys[header[:16].hex()]+=1;count+=1;logical+=17+n+peek;peek_bytes+=peek;maximum=max(maximum,length)
 at=value_start+length
os.close(fd)
# Existing ARRI scan unconditionally touches min(fileSize,16MiB) prefix too.
prefix=min(size,16*1024*1024);prefix_pages=set(range((prefix+page_size-1)//page_size))
r={'sourcePath':str(source),'sourceSize':size,'pageSize':page_size,'klvCount':count,'visitedThroughOffset':at,'completeStructuralWalk':size-at<17,'iterationCap':limit,'actuallyReadHeaderBytes':count*25,'codeWouldPeekBytes':peek_bytes,'codeLogicalHeaderAndPeekBytes':logical,'largestKLVValue':maximum,'klvHeaderAndPeekMappedPageCount':len(pages),'klvHeaderAndPeekMappedPageBytes':len(pages)*page_size,'includingUnconditional16MiBARRIPrefixPageCount':len(pages|prefix_pages),'includingUnconditional16MiBARRIPrefixMappedPageBytes':len(pages|prefix_pages)*page_size,'wallSeconds':time.monotonic()-start,'keyCounts':dict(keys),'qualification':'Read-only structural header inventory, not RSS measurement. Computes source pages touched by existing key/BER/512-byte-peek path plus unconditional ARRI prefix scan; OS resident/readahead behaviour and allocations may differ.'}
print(json.dumps(r,indent=2))
