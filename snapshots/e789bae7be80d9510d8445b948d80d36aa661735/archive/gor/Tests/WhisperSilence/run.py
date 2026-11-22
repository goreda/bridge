from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(r/'whisper-cpp-src/examples/whisper-live/main.cpp').read_text();a=s[s.index('class PCMRingBuffer {'):s.index('static std::atomic<bool> g_running')]
test='''
int main(){
 std::vector<float> quiet(19200,0.0f),speech(19200,0.05f);
 assert(has_silence_tail(quiet)); assert(!has_silence_tail(speech));
 quiet.resize(19199); assert(!has_silence_tail(quiet));
 quiet.resize(19200,0); quiet[19000]=1; assert(!has_silence_tail(quiet));
 PCMRingBuffer ring(40000); ring.push(speech.data(),speech.size());
 size_t through; auto snap=ring.snapshot(&through);
 float next[]={0.3f,0.4f};ring.push(next,2);ring.discardThrough(through);
 assert(ring.snapshot()==std::vector<float>({0.3f,0.4f}));
 ring.discardThrough(through);assert(ring.size()==2);
 PCMRingBuffer capped(4); capped.push(speech.data(),10); capped.snapshot(&through);
 capped.push(next,2); capped.discardThrough(through);assert(capped.size()==2);
 std::cout<<"PASS actual C++ silence window, transient/noise guard, concurrent append survives reset, capped-ring stale reset safety\\n";
}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.cpp').write_text('#include <vector>\n#include <deque>\n#include <mutex>\n#include <algorithm>\n#include <cmath>\n#include <cassert>\n#include <iostream>\n'+a+test)
 subprocess.run(['g++','-std=c++17',str(p/'main.cpp'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
assert 'silence_boundary || n_segments == 0' in s and 'discardThrough(snapshot_through)' in s
print('PASS inference boundary wiring (static); full whisper build/Mach-O/real speech unverified')
