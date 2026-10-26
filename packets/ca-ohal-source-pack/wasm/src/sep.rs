// Combined metaball contact sampler. Inputs are renderer sources and obstacle samples.
static mut SOURCES: Vec<f64> = Vec::new(); // x,y,weighted r2,cutoff,owner
static mut POINTS: Vec<f64> = Vec::new(); // x,y,nx,ny (zero normal = glyph)
static mut CENTRES: Vec<f64> = Vec::new(); // x,y,bound
static mut MOVES: Vec<f64> = Vec::new();
#[no_mangle] pub extern "C" fn sep_alloc(kind:usize,n:usize)->*mut f64 {unsafe{let v=match kind{0=>&mut *std::ptr::addr_of_mut!(SOURCES),1=>&mut *std::ptr::addr_of_mut!(POINTS),_=>&mut *std::ptr::addr_of_mut!(CENTRES)};v.resize(n,0.);v.as_mut_ptr()}}
#[no_mangle] pub extern "C" fn sep_moves()->*const f64 {unsafe{(&*std::ptr::addr_of!(MOVES)).as_ptr()}}
#[no_mangle] pub extern "C" fn sep_run(ns:usize,np:usize,nc:usize,threshold:f64)->f64 {unsafe{
 let src=&*std::ptr::addr_of!(SOURCES);let pts=&*std::ptr::addr_of!(POINTS);let cs=&*std::ptr::addr_of!(CENTRES);let mv=&mut *std::ptr::addr_of_mut!(MOVES);mv.resize(nc*2,0.);mv.fill(0.);let mut parts=vec![0.;nc];let mut hit=0.;
 for p in 0..np {parts.fill(0.);let b=p*4;let (x,y,nx,ny)=(pts[b],pts[b+1],pts[b+2],pts[b+3]);let mut total=0.;
  for q in 0..ns{let z=q*5;let dx=x-src[z];let dy=y-src[z+1];if dx.abs()>src[z+3]||dy.abs()>src[z+3]{continue}let f=src[z+2]/(dx*dx+dy*dy+0.0001);parts[src[z+4] as usize]+=f;total+=f;}
  if total<=threshold{continue}hit+=1.;
  for k in 0..nc{if parts[k]<=threshold*0.002{continue}let z=k*3;let dx=cs[z]-x;let dy=cs[z+1]-y;let(mx,my)=if nx!=0.||ny!=0.{let side=if dx*nx+dy*ny>=0.{1.}else{-1.};(nx*side,ny*side)}else{let d=dx.hypot(dy).max(0.0001);(dx/d,dy/d)};let step=(cs[z+2]+2.).min((cs[z+2]*((total/threshold).sqrt()-1.)).max(1.));if (mx*step).abs()>mv[k*2].abs(){mv[k*2]=mx*step}if(my*step).abs()>mv[k*2+1].abs(){mv[k*2+1]=my*step}}
 }hit
}}
