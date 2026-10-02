# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Truls Aagedal
from pathlib import Path
import subprocess
p=Path(__file__).resolve().parent
p.joinpath('numbered-grid.rgb').write_bytes(bytes(v for frame in range(10) for y in range(16) for x in range(16) for v in ((x*13+frame*17)%256,y*13,(x+y)*7)))
subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','rawvideo','-pixel_format','rgb24','-video_size','16x16','-framerate','5','-i',str(p/'numbered-grid.rgb'),'-c:v','ffv1','-pix_fmt','bgr0',str(p/'numbered-grid.mkv')],check=True)

# Genuine container transform/PAR rejection fixtures; verify their metadata.
import json
base=['ffmpeg','-hide_banner','-loglevel','error','-y']
subprocess.run(base+['-i',str(p/'numbered-grid.mkv'),'-c:v','libx264rgb','-crf','0',str(p/'square-rgb.mp4')],check=True)
subprocess.run(base+['-display_rotation','90','-i',str(p/'square-rgb.mp4'),'-c','copy',str(p/'square-rotated.mp4')],check=True)
subprocess.run(base+['-i',str(p/'numbered-grid.mkv'),'-vf','setsar=2/1','-c:v','ffv1',str(p/'anamorphic.mkv')],check=True)
rotation=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream_side_data=rotation','-of','json',str(p/'square-rotated.mp4')]))
assert rotation['streams'][0]['side_data_list'][0]['rotation']==90
sar=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=sample_aspect_ratio','-of','json',str(p/'anamorphic.mkv')]))
assert sar['streams'][0]['sample_aspect_ratio']=='2:1'
