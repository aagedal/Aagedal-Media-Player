from pathlib import Path
import mmap,os,json,hashlib
p=Path('/Users/truls.aagedal/Movies/TestVideo/A1_v_FX6/FX6/OJ_FX6A0021.MXF')
page_size=os.sysconf('SC_PAGE_SIZE'); touched=set();offset=0;klvs=0;peek_bytes=0;total_skipped=0
with p.open('rb') as f, mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as m:
 while len(m)-offset>=17:
  start=offset;offset+=16
  first=m[offset];offset+=1
  if first<128:length=first
  else:
   count=first&127
   if not 1<=count<=8 or offset+count>len(m):break
   length=int.from_bytes(m[offset:offset+count],'big');offset+=count
  if length>len(m)-offset:break
  peek=min(length,512)
  # The dependency accesses the key/BER and this prefix before classifying it.
  for page in range(start//page_size,(offset+peek-1)//page_size+1):touched.add(page)
  klvs+=1;peek_bytes+=peek;total_skipped+=length-peek;offset+=length
result={'file':p.name,'fileBytes':p.stat().st_size,'method':'KLV offsets and projected pages for the exact 3.0.1 key/BER plus512-byte value-peek loop; no metadata decoding or simulated RSS','pageSizeBytes':page_size,'completeKLVCount':klvs,'parsedThroughByteOffset':offset,'distinctProjectedHeaderPeekPages':len(touched),'projectedHeaderPeekMappedBytes':len(touched)*page_size,'totalValuePeekBytes':peek_bytes,'remainingValueBytes':total_skipped,'causalAttributionProven':False}
root=Path('/tmp/aagedal-authentic-production-metadata-v3-20260930')
(root/'mxf-header-page-diagnostic.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
