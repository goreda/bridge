from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/GorFit.swift').read_text()
a=s.index('    static func clampGeometry(');e=s.index('{',a)+1;n=1
while n:n+=(s[e]=='{')-(s[e]=='}');e+=1
method=s[a:e]
swift='''import Foundation
final class NSScreen {var visibleFrame=CGRect(x:-1920,y:0,width:1920,height:1000);var backingScaleFactor=2.0}
enum NSWindow {typealias StyleMask=Int;static func frameRect(forContentRect r:CGRect,styleMask:Int)->CGRect{r}}
enum GorOpeningFit {static let mpvWindowMask=0
'''+method+'''
}
print(GorOpeningFit.clampGeometry(frame:CGRect(x:-1940,y:624,width:800,height:400),screen:NSScreen())!)
'''
c='''#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <limits.h>
#include <string.h>
#include <assert.h>
typedef struct {char *start;int len;} bstr;
struct m_geometry {int x,y,w,h,ws;bool x_per,y_per,w_per,h_per,x_sign,y_sign,xy_valid,wh_valid;};
static long long bstrtoll(bstr s,bstr *rest,int base){char *end;long long v=strtoll(s.start,&end,base);*rest=(bstr){end,s.len-(int)(end-s.start)};return v;}
static bool bstr_startswith0(bstr s,const char *prefix){return s.len>=(int)strlen(prefix) && !strncmp(s.start,prefix,strlen(prefix));}
static bool bstr_eatstart0(bstr *s,const char *prefix){if(!bstr_startswith0(*s,prefix))return false;s->start+=strlen(prefix);s->len-=strlen(prefix);return true;}
static int bstrchr(bstr s,int c){char *p=memchr(s.start,c,s.len);return p?(int)(p-s.start):-1;}
'''+(r/'Tests/GeometryTransitions/mpv-geometry-v0.41.0.c.inc').read_text()+'''
int main(int argc,char **argv){
 assert(argc==2);struct m_geometry g;char *s=argv[1];assert(parse_geometry_str(&g,(bstr){s,(int)strlen(s)}));
 int x=0,y=0,w=1,h=1;m_geometry_apply(&x,&y,&w,&h,3840,2000,false,&g);
 assert(x==-40 && y==-48 && w==1600 && h==800);
 char anchored[]="1600x800-40-48";assert(parse_geometry_str(&g,(bstr){anchored,strlen(anchored)}));
 m_geometry_apply(&x,&y,&w,&h,3840,2000,false,&g);
 assert(x==2200 && y==1152);
 puts("PASS actual Swift clampGeometry emits absolute negative offsets; actual mpv v0.41.0 C parser/apply accepts '+-N' and preserves -40,-48; bare '-N' instead anchors opposite edge");
}
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(swift);(t/'main.c').write_text(c)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(t/'main.swift'),'-o',str(t/'swift')],check=True)
 g=subprocess.check_output([str(t/'swift')],text=True).strip();print('emitted',g)
 subprocess.run(['cc','-Wall',str(t/'main.c'),'-o',str(t/'c')],check=True)
 subprocess.run([str(t/'c'),g],check=True)
