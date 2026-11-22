public enum PhotonMeasurementShader { public static let source = #"""
#include <metal_stdlib>
using namespace metal;
// A thread computes one tile's local residual statistics; no global float atomics.
// Encode BEFORE color/sharp/grain. Input is decoded luma, not a rendered RGB texture.
struct PhotonMeasureParams { uint4 rect; uint2 textureSize; uint tilesX; float edgeThreshold; };
struct PhotonTile { float sums[8]; float squares[8]; uint counts[8]; };
float photonDenoise(texture2d<float,access::read> src, uint2 p) {
 float s=0;for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++)s+=src.read(uint2(int2(p)+int2(x,y))).r;return s/25.0;
}
kernel void photonSourceMeasure(texture2d<float,access::read> src [[texture(0)]],
 device PhotonTile* out [[buffer(0)]], constant PhotonMeasureParams& p [[buffer(1)]], uint2 tile [[thread_position_in_grid]]) {
 uint tilesY=(p.rect.w+15)/16;
 if(tile.x>=p.tilesX||tile.y>=tilesY)return;
 PhotonTile t;for(uint b=0;b<8;b++){t.sums[b]=0;t.squares[b]=0;t.counts[b]=0;}
 for(uint yy=0;yy<16;yy++)for(uint xx=0;xx<16;xx++) {
  uint2 q=p.rect.xy+tile*16+uint2(xx,yy);
  if(q.x<p.rect.x+3||q.y<p.rect.y+3||q.x+3>=p.rect.x+p.rect.z||q.y+3>=p.rect.y+p.rect.w)continue;
  float m=photonDenoise(src,q);
  float gx=abs(photonDenoise(src,q+uint2(1,0))-photonDenoise(src,q-uint2(1,0)));
  float gy=abs(photonDenoise(src,q+uint2(0,1))-photonDenoise(src,q-uint2(0,1)));
  if(!isfinite(m)||max(gx,gy)>p.edgeThreshold)continue;
  float v=src.read(q).r;if(!isfinite(v))continue;
  uint b=min(7u,uint(clamp(m,0.0,1.0)*8.0));float r=v-m;
  t.sums[b]+=r;t.squares[b]+=r*r;t.counts[b]++;
 }
 out[tile.y*p.tilesX+tile.x]=t;
}
// Same-command-buffer reduction. Bind this 64-byte output directly to the
// following parameter-update encoder; do not CPU-read before completion.
struct PhotonGPUStats { float sigma[8]; uint counts[8]; };
kernel void photonSourceReduce(device const PhotonTile* tiles [[buffer(0)]],
 device PhotonGPUStats* result [[buffer(1)]], constant uint& tileCount [[buffer(2)]], uint bin [[thread_position_in_grid]]) {
 if(bin>=8)return;
 float sum=0, square=0;uint count=0;
 for(uint i=0;i<tileCount;i++){sum+=tiles[i].sums[bin];square+=tiles[i].squares[bin];count+=tiles[i].counts[bin];}
 result->counts[bin]=count;
 result->sigma[bin]=count>=32?sqrt(max(0.0,(square-sum*sum/float(count))/float(count-1))):0.0;
}
"""# + "\n"
}
