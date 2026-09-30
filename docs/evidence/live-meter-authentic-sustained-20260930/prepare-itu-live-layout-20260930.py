from pathlib import Path
import struct,hashlib,json
base=Path('/private/tmp/aagedal-live-authentic-20260930')
source=Path('/private/tmp/aagedal-itu-live-references-20260930/1770-2 Conf 6ch VinCntr-23LKFS.wav')
original=source.read_bytes();assert hashlib.sha256(original).hexdigest()=='ef2a0baef7f50db39eddfb1ba6f2a5445646050d113f81c6365cddca7f0448a0'
assert original[:4]==b'RIFF' and original[8:12]==b'WAVE'
chunks={};at=12
while at<len(original):
 assert at+8<=len(original)
 tag=original[at:at+4];size=struct.unpack_from('<I',original,at+4)[0];payload=original[at+8:at+8+size];assert len(payload)==size
 assert tag not in chunks;chunks[tag]=payload;at+=8+size+(size&1)
fmt=chunks[b'fmt '];pcm=chunks[b'data'];tag,channels,rate,byte_rate,align,bits=struct.unpack_from('<HHIIHH',fmt)
assert (tag,channels,rate,byte_rate,align,bits)==(1,6,48000,576000,12,16)
assert len(pcm)%align==0
pcm_hash=hashlib.sha256(pcm).hexdigest();assert pcm_hash=='5e1020672b02d963f98aab2d827961656f941da79ab4b14733f62b574737848f'
# WAVE_FORMAT_EXTENSIBLE: PCM GUID, unchanged declared ITU L/R/C/LFE/Ls/Rs order.
ext=struct.pack('<HHIIHHHHI',0xfffe,channels,rate,byte_rate,align,bits,22,bits,0x60f)+bytes.fromhex('0100000000001000800000aa00389b71')
body=b'WAVE'+b'fmt '+struct.pack('<I',len(ext))+ext+b'data'+struct.pack('<I',len(pcm))+pcm
out=base/'itu-6ch-unchanged-pcm-5.1-side.wav';out.write_bytes(b'RIFF'+struct.pack('<I',len(body))+body)
assert out.read_bytes()[68:]==pcm
receipt={'sourcePath':str(source),'sourceSHA256':hashlib.sha256(original).hexdigest(),'preparedPath':str(out),'preparedSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'pcmSHA256':pcm_hash,'originalPCMEqualsPreparedPCM':True,'channels':6,'sampleRate':rate,'sampleFrames':len(pcm)//align,'durationSeconds':len(pcm)/align/rate,'speakerMask':'0x60f','layout':'5.1(side)','channelOrder':['L','R','C','LFE','Ls','Rs'],'preparation':'Unchanged PCM words/order; explicit5.1(side) WAVE speaker mask0x60f, matching existing ITU reference preparation.'}
(base/'itu-layout-preparation.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
