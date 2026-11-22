#!/usr/bin/python3
import json,sys
p=sys.argv[-1]
print(json.dumps({'streams':[{'width':64,'height':48,'pix_fmt':'rgb24' if 'rgb' in p else 'gray16le','color_range':'pc','sample_aspect_ratio':'1:1'}],'format':{'duration':'400'}}))
