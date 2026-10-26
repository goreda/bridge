//! Real-scan economy evaluation coverage: the 5 pinned fixture PNGs are
//! repo-internal binary fixtures under core/tests/fixtures/ (real glyph scans,
//! sha256-pinned below). No env var, no skipping: a missing or corrupted
//! fixture fails loudly. The synthetic-fixture sibling (economy_eval.rs) keeps
//! the always-on fast coverage; this file keeps the real-raster one.
fn same(a:&Option<FontAssessment>,b:&Option<FontAssessment>)->bool{format!("{:?}",a)==format!("{:?}",b)}
use kni_core::{capture::capture_png,capture_fit::{fit_captured,fit_captured_with_economy},cubic_fit::FitPolicy,economy::*,economy_eval::*,reference_slice::{DrawnGlyph,Point,Span}};
const K:f64=690.0/403.5087719298246;
const FX:[(&str,&str);5]=[
 ("r_scan.png","e820c617cd40ec517bb5e6e6daa01f948ae847de804474b3a78fc85071b3cbe0"),
 ("s_scan.png","4d167e3b92af1fa27db5103bf87bd55048e926cd9f64406b769ac05be7b59add"),
 ("u_scan.png","daf95988f8e779e0dfa361c86d798957f74a60b41c72d1191d27624282068fae"),
 ("dot_00b7.png","33f0a1b27a357115174e881c168bc9df6989bf47e06aa627dfe894523349eae4"),
 ("quote_2018.png","d7459752a33e6c80c95c31c06992b8e66908c233453c85e7e0c077878a0e3518")];
fn dir()->String{concat!(env!("CARGO_MANIFEST_DIR"),"/tests/fixtures").to_string()}
fn cfg(sha:&str)->EvalConfig{EvalConfig{frame_id:"CAP690-SCAN128-FITK-CFFINTEGER-RAWORIGIN".into(),scale_k:K,threshold:128,canvas:(1485,1050),capture_eps:0.5,flatten_steps:32,expected_source_sha256:sha.into(),advance:1000,render_limits:RenderLimits{max_pixels:1485*1050,max_flatten_steps:32,max_edges:1485*1050,max_working_bytes:1<<28}}}
struct Fx{ev:ProductionEvaluator,base:DrawnGlyph,econ:DrawnGlyph}
fn load(i:usize)->Fx{
 let png=std::fs::read(format!("{}/{}",dir(),FX[i].0)).unwrap();
 let ev=ProductionEvaluator::new(cfg(FX[i].1),&png).unwrap();
 let mc=capture_png(&png,0.5).unwrap();let pol=FitPolicy{squared_error:0.1,max_refits:6};
 let (br,..)=fit_captured(&mc.rings,K,&pol);let (er,..)=fit_captured_with_economy(&mc.rings,K,&pol);
 Fx{ev,base:DrawnGlyph{glyph_id:"g".into(),rings:br},econ:DrawnGlyph{glyph_id:"g".into(),rings:er}}
}
/// Split one even-delta Line span at its integer midpoint: same geometry, one more segment.
fn split_line(g:&DrawnGlyph)->Option<DrawnGlyph>{
 let mut o=g.clone();
 for r in &mut o.rings{let mut cur=r.start;for k in 0..r.spans.len(){
  if let Span::Line{end}=r.spans[k].clone(){let (dx,dy)=(end.x-cur.x,end.y-cur.y);
   if dx.rem_euclid(2.0)==0.0&&dy.rem_euclid(2.0)==0.0&&(dx!=0.0||dy!=0.0){r.spans.insert(k,Span::Line{end:Point{x:cur.x+dx/2.0,y:cur.y+dy/2.0}});return Some(o);}}
  cur=match &r.spans[k]{Span::Line{end}|Span::Cubic{end,..}=>*end};}}
 None
}
fn loose(ev:&mut ProductionEvaluator,base:&DrawnGlyph)->FontEconomyBound{
 // TEST-ONLY bound derived from the measured baseline, labelled as such.
 let a=ev.assess(base,base).unwrap();
 let m=a.regions.iter().map(|r|r.maximum_deviation).fold(0.,f64::max);let s=a.regions.iter().map(|r|r.squared_fit_error).fold(0.,f64::max);
 FontEconomyBound{font_measurement_pin:"test-only-baseline-derived".into(),loss_derivation:LossDerivation{source_measurement_pin:"test-only".into(),method:"test-only: baseline max x1.01".into(),measurements:vec![("max_sfe".into(),s),("max_dev".into(),m)]},squared_fit_budget:s*1.01+1e-6,maximum_deviation:m*1.01+1e-6,allowed_iou_loss:1e-6}
}
#[test] fn five_fixtures_real_assessment_and_byte_identity(){
 for i in 0..5{let mut f=load(i);
  let a=f.ev.assess(&f.base,&f.base).expect("baseline assessable");
  assert!(a.font_iou>0.0&&a.font_iou<=1.0);assert!(a.regions.iter().all(|r|r.construction==ConstructionComparison::Preserved&&r.extrema_preserved&&r.corners_preserved&&r.continuity_preserved));
  assert!(same(&Some(a.clone()),&f.ev.assess(&f.base,&f.base.clone())));
  if f.ev.final_font_bytes(&f.base)==f.ev.final_font_bytes(&f.econ){assert!(same(&Some(a),&f.ev.assess(&f.base,&f.econ)));}
  println!("{} iou={}",FX[i].0,f.ev.assess(&f.base,&f.base).unwrap().font_iou);}
}
#[test] fn pin_failures_are_errors(){
 let png=std::fs::read(format!("{}/{}",dir(),FX[0].0)).unwrap();
 assert!(ProductionEvaluator::new(cfg(FX[1].1),&png).is_err());
 let mut c=cfg(FX[0].1);c.canvas=(1484,1050);assert!(ProductionEvaluator::new(c,&png).is_err());
 let mut c=cfg(FX[0].1);c.scale_k=f64::NAN;assert!(ProductionEvaluator::new(c,&png).is_err());
 let mut c=cfg(FX[0].1);c.flatten_steps=0;assert!(ProductionEvaluator::new(c,&png).is_err());
}
#[test] fn unverifiable_candidates_return_none(){
 let mut f=load(0);
 let mut g=f.base.clone();if let Span::Line{end}=&mut g.rings[0].spans[0]{end.x+=0.5;}else if let Span::Cubic{end,..}=&mut g.rings[0].spans[0]{end.x+=0.5;}
 assert!(f.ev.assess(&f.base,&g).is_none());                       // non-integer, cannot encode
 let mut g=f.base.clone();g.rings.pop();assert!(f.ev.assess(&f.base,&g).is_none()); // ring count differs
 let g=DrawnGlyph{glyph_id:"g".into(),rings:vec![]};assert!(f.ev.assess(&g,&g).is_none());
}
fn reason(f:&mut Fx,cands:Vec<DrawnGlyph>,b:&FontEconomyBound,base:&DrawnGlyph)->SelectionReason{
 select_economical_glyph(base.clone(),cands,b,&mut f.ev).1[0].reason.clone()
}
#[test] fn accepted_economy_on_exact_split(){
 for i in 0..5{let mut f=load(i);if let Some(split)=split_line(&f.base){let b=loose(&mut f.ev,&split);
  let c=f.base.clone();assert_eq!(reason(&mut f,vec![c],&b,&split),SelectionReason::AcceptedEconomy);return;}}
 panic!("no splittable line in any fixture");
}
#[test] fn rejection_reasons_each_have_a_negative_case(){
 let mut f=load(0);let base=f.base.clone();let b=loose(&mut f.ev,&base);
 assert_eq!(reason(&mut f,vec![base.clone()],&b,&base),SelectionReason::NoEconomyGain);
 let mut bad=b.clone();bad.font_measurement_pin.clear();assert_eq!(reason(&mut f,vec![base.clone()],&bad,&base),SelectionReason::InvalidBound);
 let mut other=base.clone();other.glyph_id="other".into();assert_eq!(reason(&mut f,vec![other],&b,&base),SelectionReason::GlyphMismatch);
 let mut ni=base.clone();if let Span::Line{end}=&mut ni.rings[0].spans[0]{end.x+=0.5;}else if let Span::Cubic{end,..}=&mut ni.rings[0].spans[0]{end.x+=0.5;}
 assert_eq!(reason(&mut f,vec![ni],&b,&base),SelectionReason::UnverifiedCandidate);
 // Baseline unverifiable: empty glyph cannot be assessed.
 let empty=DrawnGlyph{glyph_id:"g".into(),rings:vec![]};
 assert_eq!(select_economical_glyph(empty.clone(),vec![base.clone()],&b,&mut f.ev).1[0].reason,SelectionReason::UnverifiedBaseline);
 // Real displacement of a ring point by 40 units breaks the fit bound.
 let mut shifted=base.clone();shifted.rings[0].start.x+=40.0;
 let (Span::Line{end}|Span::Cubic{end,..})=shifted.rings[0].spans.last_mut().unwrap();end.x+=40.0;
 assert_ne!(reason(&mut f,vec![shifted],&b,&base),SelectionReason::AcceptedEconomy);
 // Dropping a corner (replace two spans by one line, geometry changes) must hit a guard or the fit bound.
 let mut loosest=b.clone();loosest.squared_fit_budget=1e12;loosest.maximum_deviation=1e12;loosest.allowed_iou_loss=1.0;
 let mut nc=base.clone();let r=&mut nc.rings[0];let n=r.spans.len();
 if n>=3{let e=match &r.spans[1]{Span::Line{end}|Span::Cubic{end,..}=>*end};r.spans.drain(0..2);r.spans.insert(0,Span::Line{end:e});}
 assert_ne!(reason(&mut f,vec![nc],&loosest,&base),SelectionReason::AcceptedEconomy);
}
/// Wrapper over the real evaluator that edits the returned real assessment to exercise selector-level reasons.
struct Tamper{inner:ProductionEvaluator,n:usize,f:fn(&mut FontAssessment)}
impl FontEconomyEvaluator for Tamper{fn assess(&mut self,b:&DrawnGlyph,c:&DrawnGlyph)->Option<FontAssessment>{let mut a=self.inner.assess(b,c)?;self.n+=1;if self.n>1{(self.f)(&mut a);}Some(a)}}
#[test] fn frame_region_and_fidelity_tampering_is_rejected(){
 let cases:[(fn(&mut FontAssessment),SelectionReason);5]=[
  (|a|a.regions[0].squared_fit_error+=1.0,SelectionReason::RegionRegression),
  (|a|a.render_frame_pin.push('x'),SelectionReason::FrameMismatch),
  (|a|{a.regions.pop();},SelectionReason::RegionMismatch),
  (|a|a.font_iou-=0.5,SelectionReason::FidelityBound),
  (|a|a.regions[0].extrema_preserved=false,SelectionReason::ConstructionGuard)];
 for (f,expect) in cases{
  let mut fx=load(0);let base=fx.base.clone();let mut b=loose(&mut fx.ev,&base);b.squared_fit_budget=1e12;b.maximum_deviation=1e12;b.allowed_iou_loss=1e-3;
  let split=split_line(&base).expect("splittable");
  let ev=load(0).ev;let mut t=Tamper{inner:ev,n:0,f};
  let r=select_economical_glyph(split,vec![base],&b,&mut t).1[0].reason.clone();
  assert_eq!(r,expect);}
}

fn pt(x:f64,y:f64)->Point{Point{x,y}}
fn ring(start:Point,spans:Vec<Span>)->kni_core::reference_slice::ReferenceRing{kni_core::reference_slice::ReferenceRing{start,spans}}
fn ln(x:f64,y:f64)->Span{Span::Line{end:pt(x,y)}}
#[test] fn exact_extrema_vertex_collinear_and_interior_root(){
 let sq=ring(pt(0.,0.),vec![ln(10.,0.),ln(10.,10.),ln(0.,10.),ln(0.,0.)]);
 let ev=extrema_vertices(&sq);
 assert!(ev.iter().any(|e|e.contains("Vertex(10, 0")),"{ev:?}");
 // collinear midpoint is not an extremum and does not change the event list
 let sp=ring(pt(0.,0.),vec![ln(5.,0.),ln(10.,0.),ln(10.,10.),ln(0.,10.),ln(0.,0.)]);
 assert_eq!(ev,extrema_vertices(&sp));
 // cubic whose controls lie on its chord but traverses forth, back, forth: two interior x roots
 let cu=ring(pt(0.,0.),vec![Span::Cubic{control_one:pt(20.,0.),control_two:pt(0.,0.),end:pt(10.,0.)},ln(0.,0.)]);
 assert!(extrema_vertices(&cu).iter().any(|e|e.contains("Interior")&&e.contains(", 0, 2)")),"{:?}",extrema_vertices(&cu));
 // monotone chord cubic has no interior event
 let mo=ring(pt(0.,0.),vec![Span::Cubic{control_one:pt(3.,0.),control_two:pt(7.,0.),end:pt(10.,0.)},ln(0.,0.)]);
 assert!(!extrema_vertices(&mo).iter().any(|e|e.contains("Interior")));
}
#[test] fn gate_measurement_fields_node_count_curve_and_budget(){
 for i in 0..5{let f=load(i);
  let n=f.ev.node_count(&f.base).expect("countable");
  let by_hand:usize=f.base.rings.iter().map(|r|r.spans.len()).sum();
  assert_eq!(n,by_hand,"on-curve points = spans per closed ring");
  let p=f.ev.curve_point(&f.base).unwrap();assert_eq!(p.nodes,n);
  {let mut ev2=load(i).ev;assert_eq!(p.font_iou.to_bits(),ev2.assess(&f.base,&f.base).unwrap().font_iou.to_bits());}
  if let Some(split)=split_line(&f.base){assert_eq!(f.ev.node_count(&split),Some(n+1));
   let q=f.ev.curve_point(&split).unwrap();assert_eq!(q.font_iou.to_bits(),p.font_iou.to_bits(),"same geometry, same IoU");}
  let b=f.ev.potrace_budget(&f.base).unwrap();
  assert_eq!(b.potrace_nodes,n);assert_eq!(b.node_count_parser_pin,f.ev.node_count_parser_pin());
  assert!(b.node_count_parser_pin.contains("CAP690-SCAN128")&&b.potrace_glyph_sha256.len()==64);
  // unverifiable outline -> None, no fallback count
  let mut bad=f.base.clone();bad.rings.clear();assert!(f.ev.node_count(&bad).is_none()&&f.ev.curve_point(&bad).is_none()&&f.ev.potrace_budget(&bad).is_none());
 }
}
/// Rule: a collinear vertex inside an axis-aligned plateau is NOT an extremum event, applied identically to base and econ.
#[test] fn plateau_rule_is_symmetric_for_the_three_tile_patterns(){
 // the three dropped-vertex patterns: two same-direction vertical lines, collinear middle vertex
 for (x,y0,ym,y1) in [(439.,516.,640.,643.),(451.,516.,639.,641.),(422.,529.,652.,653.)]{
  let mk=|mid:bool|{let mut s=vec![ln(x,y0)];if mid{s.push(ln(x,ym));}s.push(ln(x,y1));s.push(ln(x-300.,y1));s.push(ln(x-300.,0.));s.push(ln(0.,0.));ring(pt(0.,0.),s)};
  let (base,merged)=(mk(true),mk(false));
  assert_eq!(extrema_vertices(&base),extrema_vertices(&merged),"collinear plateau vertex must not create an event ({x},{ym})");
  assert!(!extrema_vertices(&base).iter().any(|e|e.contains(&format!("Vertex({x}, {ym},"))),"{:?}",extrema_vertices(&base));
 }
}
/// Positive control: removing a REAL axis extremum must still be flagged. A guard that never fires would also stay silent for the wrong reason.
#[test] fn positive_control_real_extremum_removal_is_flagged(){
 let mut flagged=0;let mut collinear_clean=0;
 for i in 0..5{let mut f=load(i);
  for ri in 0..f.base.rings.len(){let n=f.base.rings[ri].spans.len();
   for k in 0..n.saturating_sub(1){
    let mut cand=f.base.clone();let r=&mut cand.rings[ri];
    let e=match &r.spans[k+1]{Span::Line{end}|Span::Cubic{end,..}=>*end};
    r.spans.drain(k..k+2);r.spans.insert(k,Span::Line{end:e});
    let before=extrema_vertices(&f.base.rings[ri]);let after=extrema_vertices(&cand.rings[ri]);
    if before==after{continue;} // no real event removed here
    if let Some(a)=f.ev.assess(&f.base,&cand){
     assert!(!a.regions[ri].extrema_preserved,"event list changed but extrema_preserved=true (tile {i}, ring {ri}, span {k})");flagged+=1;
    }
   }}
  if let Some(split)=split_line(&f.base){let a=f.ev.assess(&f.base,&split).unwrap();assert!(a.regions.iter().all(|r|r.extrema_preserved));collinear_clean+=1;}
 }
 assert!(flagged>0,"no real extremum removal was assessable: positive control did not run");
 assert!(collinear_clean>0,"no collinear split was assessable");
}

#[test] fn fixture_files_are_the_pinned_real_scans(){
 for (name,pin) in FX{
  let bytes=std::fs::read(format!("{}/{name}",dir())).expect("repo-internal fixture must exist");
  assert_eq!(sha256_hex(&bytes),pin,"fixture {name} corrupted or replaced");
 }
}
