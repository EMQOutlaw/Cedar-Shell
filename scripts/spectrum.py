#!/usr/bin/env python3
"""CAVA's real PipeWire spectrum. Lifetime belongs to the visible instrument."""
import os, shutil, sys, tempfile
if not shutil.which('cava'): raise SystemExit('CAVA is unavailable')
config='''[general]
framerate = 30
bars = 24
[input]
method = pipewire
source = auto
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
bar_delimiter = 59
frame_delimiter = 10
channels = mono
'''
# memfd avoids leaving configuration files behind when the panel closes.
fd=os.memfd_create('cedar-spectrum',0);os.write(fd,config.encode());os.lseek(fd,0,0);os.set_inheritable(fd,True)
os.execvp('cava',['cava','-p',f'/proc/self/fd/{fd}'])
